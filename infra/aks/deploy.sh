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
MODE="automaticManaged"     # or automaticPrivate or standardPrivate
WORKLOAD="aks"
ENV="dev"
PARAMETERS_FILE="$SCRIPT_DIR/main.bicepparam"
AUTO_NAME=false
INTERACTIVE=false
RESUME=false
STAGE="All"                 # Preflight | Plan | Deploy | Smoke | All
SKIP_WHATIF=false
DEPLOYMENT_NAME=""
ENSURE_BYO_NODE_SUBNET=false
BYO_NODE_SUBNET_PREFIX=""
declare -A OVERRIDES

usage() {
  cat <<EOF
Usage: $0 [options]
  -s, --subscription <id>
  -l, --location <region>           default: westus3
  -m, --mode <automaticManaged|automaticPrivate|standardPrivate>
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
      --ensure-byo-node-subnet
      --byo-node-subnet-prefix <cidr>
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
    --ensure-byo-node-subnet) ENSURE_BYO_NODE_SUBNET=true; shift;;
    --byo-node-subnet-prefix) BYO_NODE_SUBNET_PREFIX="$2"; shift 2;;
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

is_valid_subnet_resource_id() {
  local value="${1:-}"
  [[ -n "$value" ]] || return 1
  [[ "$value" =~ ^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\.Network/virtualNetworks/[^/]+/subnets/[^/]+$ ]]
}

is_valid_cidr() {
  local value="${1:-}"
  [[ "$value" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})/([0-9]{1,2})$ ]] || return 1

  local o1="${BASH_REMATCH[1]}" o2="${BASH_REMATCH[2]}" o3="${BASH_REMATCH[3]}" o4="${BASH_REMATCH[4]}" p="${BASH_REMATCH[5]}"
  for o in "$o1" "$o2" "$o3" "$o4"; do
    (( o >= 0 && o <= 255 )) || return 1
  done
  (( p >= 0 && p <= 32 )) || return 1
  return 0
}

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

  # ---------- Azure CLI ----------
  if ! command -v az >/dev/null; then
    warn "Azure CLI not found."
    if command -v apt-get >/dev/null; then
      echo "  Installing via apt..."
      curl -fsSL https://aka.ms/InstallAzureCLIDeb | sudo bash
    elif command -v brew >/dev/null; then
      echo "  Installing via brew..."
      brew install azure-cli
    elif command -v dnf >/dev/null; then
      echo "  Installing via dnf..."
      sudo dnf install -y azure-cli
    else
      err "Cannot auto-install Azure CLI on this OS. See https://aka.ms/azure-cli"; exit 1
    fi
  fi
  local cli_ver; cli_ver="$(az version --query '"azure-cli"' -o tsv)"
  # Compare versions: require >= 2.77.0
  local req="2.77.0"
  if [[ "$(printf '%s\n%s\n' "$req" "$cli_ver" | sort -V | head -n1)" != "$req" ]]; then
    warn "Azure CLI $cli_ver < $req. Upgrading..."
    az upgrade --yes --only-show-errors >/dev/null 2>&1 || true
    cli_ver="$(az version --query '"azure-cli"' -o tsv)"
  fi
  ok "Azure CLI $cli_ver"

  # ---------- jq ----------
  if ! command -v jq >/dev/null; then
    warn "jq not found."
    if command -v apt-get >/dev/null; then sudo apt-get update -qq && sudo apt-get install -y jq
    elif command -v brew >/dev/null; then brew install jq
    elif command -v dnf >/dev/null; then sudo dnf install -y jq
    else err "Install jq manually"; exit 1; fi
  fi
  ok "jq present"

  # ---------- Bicep ----------
  if ! az bicep version >/dev/null 2>&1; then
    warn "Bicep not installed. Installing..."
    az bicep install --only-show-errors >/dev/null 2>&1
  else
    az bicep upgrade --only-show-errors >/dev/null 2>&1 || true
  fi
  ok "Bicep $(az bicep version 2>/dev/null | sed 's/Bicep CLI version //')"

  # ---------- aks-preview extension ----------
  if ! az extension show -n aks-preview >/dev/null 2>&1; then
    warn "aks-preview not installed; installing..."
    az extension add -n aks-preview --only-show-errors
  else
    az extension update -n aks-preview --only-show-errors >/dev/null 2>&1 || true
  fi
  ok "aks-preview ready"

  # ---------- kubectl ----------
  if ! command -v kubectl >/dev/null; then
    warn "kubectl not found. Installing via 'az aks install-cli'..."
    az aks install-cli --only-show-errors >/dev/null 2>&1 || warn "kubectl install location may not be on PATH"
  fi
  command -v kubectl >/dev/null && ok "kubectl present"

  # ---------- Login ----------
  if ! az account show >/dev/null 2>&1; then
    warn "Not logged in. Running 'az login'..."
    az login --only-show-errors >/dev/null
  fi
  if [[ -n "$SUBSCRIPTION_ID" ]]; then az account set --subscription "$SUBSCRIPTION_ID"; fi
  local acct; acct="$(az account show -o json)"
  ok "Subscription: $(echo "$acct" | jq -r '.name')  ($(echo "$acct" | jq -r '.id'))"

  # ---------- RBAC sanity ----------
  local me; me="$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)"
  if [[ -n "$me" ]]; then
    local roles; roles="$(az role assignment list --assignee "$me" --scope "/subscriptions/$(echo "$acct" | jq -r '.id')" --include-inherited --query "[].roleDefinitionName" -o tsv 2>/dev/null | sort -u | tr '\n' ',')"
    if echo "$roles" | grep -Eq 'Owner|Contributor|User Access Administrator'; then
      ok "Caller roles: ${roles%,}"
    else
      warn "Caller roles: ${roles:-<none>}. Need Contributor + (User Access Administrator OR Owner) for role assignments."
    fi
  fi

  # ---------- Provider registration ----------
  for p in Microsoft.ContainerService Microsoft.Network Microsoft.ManagedIdentity Microsoft.OperationalInsights Microsoft.OperationsManagement Microsoft.Insights Microsoft.Monitor Microsoft.Dashboard Microsoft.ContainerRegistry Microsoft.Authorization; do
    az provider register --namespace "$p" --consent-to-permissions >/dev/null 2>&1 || true
  done
  ok "Providers registered (async)"

  # ---------- Region availability ----------
  if az provider show --namespace Microsoft.ContainerService --query "resourceTypes[?resourceType=='managedClusters'].locations[]" -o tsv 2>/dev/null \
       | tr 'A-Z ' 'a-z' | grep -qx "$(echo "$LOCATION" | tr 'A-Z ' 'a-z')"; then
    ok "AKS available in '$LOCATION'"
  else
    warn "Location '$LOCATION' is not in the AKS region list. Deployment may fail."
  fi

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
  if [[ ! -f "$OUTPUTS_FILE" ]]; then
    err "No deployment outputs found at $OUTPUTS_FILE. Run the Deploy stage first (or pass --resume after a previous Deploy)."
    exit 1
  fi
  local rg cluster oidc
  rg="$(jq -r '.resourceGroupName.value' "$OUTPUTS_FILE")"
  cluster="$(jq -r '.clusterName.value' "$OUTPUTS_FILE")"
  oidc="$(jq -r '.oidcIssuerUrl.value // empty' "$OUTPUTS_FILE")"
  az aks get-credentials -g "$rg" -n "$cluster" --overwrite-existing
  kubectl get nodes
  [[ -n "$oidc" ]] && echo "OIDC issuer URL: $oidc"
  ok "Cluster reachable"
}

ensure_byo_node_subnet_if_missing() {
  $ENSURE_BYO_NODE_SUBNET || return 0
  local subnet_id="${OVERRIDES[byoVnetSubnetId]:-}"
  [[ -n "$subnet_id" ]] || { err "--ensure-byo-node-subnet requires --set byoVnetSubnetId=<full subnet resource id>"; exit 1; }
  is_valid_subnet_resource_id "$subnet_id" || { err "Invalid BYO node subnet resource ID format: $subnet_id"; exit 1; }

  if [[ -n "$BYO_NODE_SUBNET_PREFIX" ]] && ! is_valid_cidr "$BYO_NODE_SUBNET_PREFIX"; then
    err "Invalid --byo-node-subnet-prefix '$BYO_NODE_SUBNET_PREFIX'. Use IPv4 CIDR format like 10.240.0.0/22."
    exit 1
  fi

  if az network vnet subnet show --ids "$subnet_id" --query id -o tsv >/dev/null 2>&1; then
    ok "BYO node subnet already exists"
    return 0
  fi

  [[ -n "$BYO_NODE_SUBNET_PREFIX" ]] || { err "BYO node subnet not found. Provide --byo-node-subnet-prefix (for example 10.240.0.0/22) so it can be created."; exit 1; }

  local sub rg vnet subnet active_sub
  sub="$(echo "$subnet_id" | awk -F/ '{print $3}')"
  rg="$(echo "$subnet_id" | awk -F/ '{print $5}')"
  vnet="$(echo "$subnet_id" | awk -F/ '{print $9}')"
  subnet="$(echo "$subnet_id" | awk -F/ '{print $11}')"
  active_sub="$(az account show --query id -o tsv 2>/dev/null || true)"

  warn "BYO node subnet not found. Creating subnet '$subnet' in vnet '$vnet' with prefix '$BYO_NODE_SUBNET_PREFIX'..."
  az account set --subscription "$sub" >/dev/null
  local create_rc=0
  az network vnet subnet create --resource-group "$rg" --vnet-name "$vnet" --name "$subnet" --address-prefixes "$BYO_NODE_SUBNET_PREFIX" --only-show-errors >/dev/null || create_rc=$?
  [[ -n "$active_sub" ]] && az account set --subscription "$active_sub" >/dev/null
  if [[ $create_rc -ne 0 ]]; then
    err "Failed to create BYO node subnet: $subnet_id"
    exit $create_rc
  fi
  ok "Created BYO node subnet"
}

# ----------------------------------------------------------------------
OVERRIDES_FILE="$STATE_DIR/overrides.env"

if [[ -z "$DEPLOYMENT_NAME" ]]; then
  DEPLOYMENT_NAME="aks-automatic-$(date +%Y%m%d-%H%M%S)"
  if $RESUME && [[ -f "$STATE_DIR/state" ]]; then DEPLOYMENT_NAME="$(cat "$STATE_DIR/state")"; fi
fi
echo "$DEPLOYMENT_NAME" > "$STATE_DIR/state"

# On --resume, restore previously saved overrides so we don't try to create a
# different set of resources with a fresh random suffix from auto_names.
if $RESUME && [[ -f "$OVERRIDES_FILE" ]]; then
  # shellcheck disable=SC1090
  while IFS='=' read -r k v; do
    [[ -z "$k" || "$k" =~ ^# ]] && continue
    # CLI --set takes precedence: only fill keys that weren't already provided
    if [[ -z "${OVERRIDES[$k]+x}" ]]; then OVERRIDES["$k"]="$v"; fi
  done < "$OVERRIDES_FILE"
  if $AUTO_NAME; then warn "--resume detected: reusing saved names (ignoring --auto-name regeneration)."; fi
elif $AUTO_NAME || $INTERACTIVE; then
  auto_names
fi
OVERRIDES[mode]="$MODE"
OVERRIDES[location]="$LOCATION"

if [[ -n "${OVERRIDES[ensureByoNodeSubnet]:-}" ]]; then
  case "${OVERRIDES[ensureByoNodeSubnet],,}" in
    true|1|yes|on) ENSURE_BYO_NODE_SUBNET=true ;;
  esac
  unset 'OVERRIDES[ensureByoNodeSubnet]'
fi
if [[ -n "${OVERRIDES[byoNodeSubnetPrefix]:-}" && -z "$BYO_NODE_SUBNET_PREFIX" ]]; then
  BYO_NODE_SUBNET_PREFIX="${OVERRIDES[byoNodeSubnetPrefix]}"
fi
unset 'OVERRIDES[byoNodeSubnetPrefix]'

# Persist overrides for future --resume runs
: > "$OVERRIDES_FILE"
for k in "${!OVERRIDES[@]}"; do printf '%s=%s\n' "$k" "${OVERRIDES[$k]}" >> "$OVERRIDES_FILE"; done

case "$STAGE" in
  Preflight) stage_preflight ;;
  Plan)      stage_plan ;;
  Deploy)    ensure_byo_node_subnet_if_missing; stage_deploy ;;
  Smoke)     stage_smoke ;;
  All)       stage_preflight; stage_plan; ensure_byo_node_subnet_if_missing; stage_deploy; stage_smoke ;;
  *) err "unknown stage: $STAGE"; exit 1;;
esac

cyan "DONE"
echo "  kubectl get pods -A"
