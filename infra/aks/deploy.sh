#!/usr/bin/env bash
# User-friendly progressive deploy for AKS Automatic (Bicep)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$SCRIPT_DIR/.deploy"
mkdir -p "$STATE_DIR"
OUTPUTS_FILE="$STATE_DIR/outputs.json"

# Defaults
SUBSCRIPTION_ID=""
LOCATION="westus3"
MODE="automaticManaged"     # or automaticPrivate
WORKLOAD="aks"
ENV="dev"
PARAMETERS_FILE="$SCRIPT_DIR/main.bicepparam"
AUTO_NAME=false
INTERACTIVE=false
RESUME=false
STAGE="All"                 # Preflight | Plan | Deploy | Smoke | All
SKIP_WHATIF=false
DEPLOYMENT_NAME=""
declare -A OVERRIDES

usage() {
  cat <<EOF
Usage: $0 [options]
  -s, --subscription <id>
  -l, --location <region>           default: westus3
  -m, --mode <automaticManaged|automaticPrivate>
  -w, --workload <name>             default: aks
  -e, --env <name>                  default: dev
  -p, --params <file>               default: main.bicepparam
      --auto-name                   use deterministic naming
      --interactive                 prompt for each name (defaults shown)
      --resume                      resume from saved state
      --stage <Preflight|Plan|Deploy|Smoke|All>
      --skip-whatif
      --set k=v                     parameter override (repeatable)
      --deployment-name <n>
  -h, --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--subscription) SUBSCRIPTION_ID="$2"; shift 2;;
    -l|--location)     LOCATION="$2";        shift 2;;
    -m|--mode)         MODE="$2";            shift 2;;
    -w|--workload)     WORKLOAD="$2";        shift 2;;
    -e|--env)          ENV="$2";             shift 2;;
    -p|--params)       PARAMETERS_FILE="$2"; shift 2;;
    --auto-name)       AUTO_NAME=true;       shift;;
    --interactive)     INTERACTIVE=true;     shift;;
    --resume)          RESUME=true;          shift;;
    --stage)           STAGE="$2";           shift 2;;
    --skip-whatif)     SKIP_WHATIF=true;     shift;;
    --set)             k="${2%%=*}"; v="${2#*=}"; OVERRIDES["$k"]="$v"; shift 2;;
    --deployment-name) DEPLOYMENT_NAME="$2"; shift 2;;
    -h|--help)         usage; exit 0;;
    *) echo "unknown arg: $1"; usage; exit 1;;
  esac
done

cyan() { printf "\n\033[36m=== %s ===\033[0m\n" "$*"; }
ok()   { printf "  \033[32m[OK]\033[0m %s\n"   "$*"; }
warn() { printf "  \033[33m[!!]\033[0m %s\n"   "$*"; }
err()  { printf "  \033[31m[XX]\033[0m %s\n"   "$*"; }

prompt() {
  local label="$1" default="$2" v
  if ! $INTERACTIVE; then echo "$default"; return; fi
  read -rp "  $label [$default]: " v
  echo "${v:-$default}"
}

auto_names() {
  local short_loc; short_loc="$(echo "$LOCATION" | tr -dc 'a-z0-9' | cut -c1-6)"
  local suffix; suffix="$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c4)"
  local base="${WORKLOAD}-${ENV}-${short_loc}-${suffix}"
  base="$(echo "$base" | tr '[:upper:]' '[:lower:]')"
  local cluster="aks-${base}"
  OVERRIDES[resourceGroupName]="$(prompt resourceGroupName "rg-${base}")"
  OVERRIDES[clusterName]="$(prompt clusterName "${cluster}")"
  OVERRIDES[nodeResourceGroupName]="$(prompt nodeResourceGroupName "rg-${base}-nodes")"
  OVERRIDES[dnsPrefix]="$(prompt dnsPrefix "${cluster}")"
  OVERRIDES[controlPlaneIdentityName]="$(prompt controlPlaneIdentityName "id-${base}-cp")"
  OVERRIDES[kubeletIdentityName]="$(prompt kubeletIdentityName "id-${base}-kubelet")"
  OVERRIDES[logAnalyticsWorkspaceName]="$(prompt logAnalyticsWorkspaceName "log-${base}")"
  OVERRIDES[azureMonitorWorkspaceName]="$(prompt azureMonitorWorkspaceName "amw-${base}")"
  OVERRIDES[managedGrafanaName]="$(prompt managedGrafanaName "amg-${base}")"
  local acr_default; acr_default="$(echo "acr${base}" | tr -dc 'a-z0-9' | cut -c1-50)"
  OVERRIDES[acrName]="$(prompt acrName "${acr_default}")"
  OVERRIDES[vnetName]="$(prompt vnetName "vnet-${base}")"
  OVERRIDES[aksNsgName]="$(prompt aksNsgName "nsg-aks-${base}")"
  OVERRIDES[privateDnsZoneName]="$(prompt privateDnsZoneName "privatelink.${LOCATION}.azmk8s.io")"
  OVERRIDES[privateDnsVnetLinkName]="$(prompt privateDnsVnetLinkName "link-${base}")"
}

stage_preflight() {
  cyan "Stage 1/4  Preflight"
  command -v az >/dev/null || { err "Azure CLI not found"; exit 1; }
  local cli_ver; cli_ver="$(az version --query '"azure-cli"' -o tsv)"
  ok "Azure CLI $cli_ver"

  if ! az extension show -n aks-preview >/dev/null 2>&1; then
    warn "aks-preview not installed; installing..."
    az extension add -n aks-preview --only-show-errors
  else
    az extension update -n aks-preview --only-show-errors >/dev/null 2>&1 || true
  fi
  ok "aks-preview ready"

  if ! az account show >/dev/null 2>&1; then err "Run: az login"; exit 1; fi
  if [[ -n "$SUBSCRIPTION_ID" ]]; then az account set --subscription "$SUBSCRIPTION_ID"; fi
  local acct; acct="$(az account show -o json)"
  ok "Subscription: $(echo "$acct" | jq -r '.name')  ($(echo "$acct" | jq -r '.id'))"

  for p in Microsoft.ContainerService Microsoft.Network Microsoft.ManagedIdentity Microsoft.OperationalInsights Microsoft.OperationsManagement Microsoft.Insights Microsoft.Monitor Microsoft.Dashboard Microsoft.ContainerRegistry Microsoft.Authorization; do
    az provider register --namespace "$p" --consent-to-permissions >/dev/null 2>&1 || true
  done
  ok "Providers registered (async)"

  if [[ "$MODE" == "automaticManaged" ]]; then
    local state; state="$(az feature show --namespace Microsoft.ContainerService --name AKS-AutomaticHostedSystemProfilePreview --query properties.state -o tsv)"
    if [[ "$state" != "Registered" ]]; then
      warn "Registering preview feature AKS-AutomaticHostedSystemProfilePreview..."
      az feature register --namespace Microsoft.ContainerService --name AKS-AutomaticHostedSystemProfilePreview >/dev/null
      while [[ "$(az feature show --namespace Microsoft.ContainerService --name AKS-AutomaticHostedSystemProfilePreview --query properties.state -o tsv)" != "Registered" ]]; do
        echo "    waiting..."; sleep 20
      done
      az provider register --namespace Microsoft.ContainerService >/dev/null
    fi
    ok "Feature registered"
  fi
}

build_param_args() {
  local args=()
  for k in "${!OVERRIDES[@]}"; do args+=("--parameters" "$k=${OVERRIDES[$k]}"); done
  printf '%s\n' "${args[@]}"
}

stage_plan() {
  cyan "Stage 2/4  Plan"
  if $SKIP_WHATIF; then warn "Skipping what-if"; return; fi
  mapfile -t parg < <(build_param_args)
  az deployment sub what-if \
    --location "$LOCATION" \
    --name "$DEPLOYMENT_NAME" \
    --template-file "$SCRIPT_DIR/main.bicep" \
    --parameters "$PARAMETERS_FILE" \
    "${parg[@]}"
  if $INTERACTIVE; then
    read -rp "Proceed with deployment? (y/N) " go
    [[ "$go" =~ ^[yY] ]] || { err "Aborted"; exit 1; }
  fi
}

stage_deploy() {
  cyan "Stage 3/4  Deploy"
  mapfile -t parg < <(build_param_args)
  if ! az deployment sub create \
      --location "$LOCATION" \
      --name "$DEPLOYMENT_NAME" \
      --template-file "$SCRIPT_DIR/main.bicep" \
      --parameters "$PARAMETERS_FILE" \
      "${parg[@]}" \
      --output json > "$STATE_DIR/raw.json"; then
    err "Deployment failed. Recent operations:"
    az deployment sub operation list --name "$DEPLOYMENT_NAME" \
      --query "[?properties.provisioningState!='Succeeded'].{Op:properties.targetResource.resourceName,State:properties.provisioningState,Status:properties.statusMessage}" -o table
    exit 1
  fi
  jq '.properties.outputs' "$STATE_DIR/raw.json" > "$OUTPUTS_FILE"
  ok "Deployment succeeded -> $OUTPUTS_FILE"
}

stage_smoke() {
  cyan "Stage 4/4  Smoke test"
  local rg cluster
  rg="$(jq -r '.resourceGroupName.value' "$OUTPUTS_FILE")"
  cluster="$(jq -r '.clusterName.value' "$OUTPUTS_FILE")"
  az aks get-credentials -g "$rg" -n "$cluster" --overwrite-existing
  kubectl get nodes
  ok "Cluster reachable"
}

# ----------------------------------------------------------------------
if [[ -z "$DEPLOYMENT_NAME" ]]; then
  DEPLOYMENT_NAME="aks-automatic-$(date +%Y%m%d-%H%M%S)"
  if $RESUME && [[ -f "$STATE_DIR/state" ]]; then DEPLOYMENT_NAME="$(cat "$STATE_DIR/state")"; fi
fi
echo "$DEPLOYMENT_NAME" > "$STATE_DIR/state"

if $AUTO_NAME || $INTERACTIVE; then auto_names; fi
OVERRIDES[mode]="$MODE"
OVERRIDES[location]="$LOCATION"

case "$STAGE" in
  Preflight) stage_preflight ;;
  Plan)      stage_plan ;;
  Deploy)    stage_deploy ;;
  Smoke)     stage_smoke ;;
  All)       stage_preflight; stage_plan; stage_deploy; stage_smoke ;;
  *) err "unknown stage: $STAGE"; exit 1;;
esac

cyan "DONE"
echo "  kubectl get pods -A"
