# AKS Automatic — progressive Bicep deployment

User-friendly, fully-parameterized deployment for **AKS Automatic** clusters
(with optional **managed system node pools (preview)**) using Bicep + a
staged PowerShell/Bash driver.

## Modes

| Mode | API server | VNet | Managed system node pools |
|---|---|---|---|
| `automaticManaged` *(default)* | Public (API server VNet integration) | AKS-managed | **Enabled** (`hostedSystemProfile`) |
| `automaticPrivate` | **Private** | Customer-supplied VNet + Private DNS zone | Disabled *(not supported in custom VNet — per Microsoft Learn)* |

> The script enforces this automatically — you cannot accidentally combine private + managed system node pools.

## Layout

```
.
├── azure.yaml                     # azd manifest — points azd at infra/aks
├── .github/workflows/lint.yml     # bicep build/lint + PSScriptAnalyzer + shellcheck
└── infra/aks/
    ├── main.bicep                     # subscription-scope orchestrator
    ├── main.bicepparam                # all parameters (override anything you want)
    ├── deploy.ps1                     # progressive driver (Windows / PS Core)
    ├── deploy.sh                      # progressive driver (Linux/macOS)
    ├── deploy-wizard.ps1              # launches browser-based command wizard UI
    ├── wizard/
    │   └── index.html                 # user-friendly deployment wizard
    └── modules/
        ├── identity.bicep             # control-plane + kubelet UAMI
        ├── network.bicep              # VNet, AKS subnet, PE subnet, NSG
        ├── privateDns.bicep           # privatelink.<region>.azmk8s.io + VNet link
      ├── privateDnsLink.bicep       # additional VNet links (e.g., hub)
        ├── logAnalytics.bicep         # Container Insights workspace
        ├── monitoring.bicep           # Azure Monitor workspace + optional Grafana
        ├── acr.bicep                  # optional new ACR
      ├── hub.bicep                  # optional hub VNet + Bastion + jumpbox subnets
      ├── peering.bicep              # bidirectional VNet peering helper
      ├── bastion.bicep              # Bastion host
      ├── jumpbox.bicep              # Linux jumpbox VM
      ├── aksPrivateEndpoint.bicep   # AKS management PE (legacy private clusters)
        ├── roleAssignments.bicep      # kubelet MIO + ACR pull + app-routing DNS
        ├── roleAssignmentAcr.bicep
      ├── roleAssignmentAks.bicep
        ├── roleAssignmentDnsZone.bicep
        ├── roleAssignmentSubnet.bicep      # cross-sub safe Network Contributor on subnet
        ├── roleAssignmentPrivateDns.bicep  # cross-sub safe PDNS Zone Contributor
        ├── clusterAdmin.bicep         # Azure RBAC cluster admin/user roles
        ├── aks.bicep                  # the AKS Automatic cluster itself
        └── maintenance.bicep          # optional planned maintenance windows
```

## Quick start

You can drive the template three ways — pick whichever fits your workflow.

### Option A — `azd up` (Azure Developer CLI)

The repo root [azure.yaml](../../azure.yaml) wires `azd` to `infra/aks/main.bicep`.
The `bicepparam` reads `AZURE_ENV_NAME` / `AZURE_LOCATION` / `AKS_MODE` from
the environment, so `azd env set` flows through cleanly.

```powershell
cd ..\..      # repo root
azd auth login
azd env new aks-dev
azd env set AZURE_LOCATION westus3
azd env set AKS_MODE automaticManaged   # or automaticPrivate
azd up
```

The `preprovision` hook runs the same `deploy.ps1 -Stage Preflight` checks
(prereq install, login, RBAC, region, providers, feature flag). The
`postprovision` hook fetches credentials and runs `kubectl get nodes`
(skipped automatically for `automaticPrivate`).

### Option B — driver script (full control over staging)

```powershell
cd infra\aks
.\deploy.ps1 -SubscriptionId <sub-id> -Location westus3 -AutoName
```

```bash
cd infra/aks
./deploy.sh -s <sub-id> -l westus3 --auto-name
```

### Option B2 — deployment wizard UI (recommended for first-time users)

Launch the local browser wizard to build correct commands for `deploy.ps1` and
for raw `az deployment` usage:

```powershell
cd infra\aks
.\deploy-wizard.ps1
```

The wizard helps with:

- Choosing mode (`automaticManaged` vs `automaticPrivate`)
- Hub connectivity (`none`, `peering`, `privateEndpoint`, `both`)
- Bastion + jumpbox toggles and SSH key path
- Generating copy-paste-ready `deploy.ps1` and `az deployment sub create` commands
- Highlighting validation warnings for incompatible combinations

### Option C — raw `az deployment` (CI-friendly)

```bash
az deployment sub create \
  --location westus3 \
  --template-file infra/aks/main.bicep \
  --parameters infra/aks/main.bicepparam
```

### Interactive (confirm every name)

```powershell
.\deploy.ps1 -SubscriptionId <sub-id> -Location eastus2 -Mode automaticPrivate -WorkloadName payments -Interactive
```

### Bring your own everything (no prompts, file-driven)

Edit [main.bicepparam](main.bicepparam) and run:

```powershell
.\deploy.ps1 -SubscriptionId <sub-id> -Location westus3
```

## Progressive / patchable

The driver runs four stages — each independently re-runnable:

| Stage | What it does |
|---|---|
| `Preflight` | PowerShell version, **auto-installs** Azure CLI (winget/apt/brew/dnf), Bicep, `aks-preview`, kubectl; `az login` if needed; caller RBAC sanity (Owner/Contributor/UAA); provider registrations; AKS region availability; `AKS-AutomaticHostedSystemProfilePreview` feature |
| `Plan` | `az deployment sub what-if` (skip with `-SkipWhatIf`) |
| `Deploy` | Submits `main.bicep` at subscription scope; prints operation failures on error |
| `Smoke` | Loads `outputs.json`, runs `az aks get-credentials` + `kubectl get nodes` (works standalone after a prior Deploy) |

Run a single stage:

```powershell
.\deploy.ps1 -Stage Deploy
.\deploy.ps1 -Stage Smoke
```

Resume after a failure (re-uses prior deployment name + name overrides):

```powershell
.\deploy.ps1 -Resume
```

Patch a single parameter without editing the file:

```powershell
.\deploy.ps1 -Resume -Overrides @{ enableManagedGrafana = 'true' }
```

## Hub connectivity modes

`hubConnectivityMode` options:

- `none`: no hub resources
- `peering`: peer hub and spoke VNets
- `privateEndpoint`: request AKS management private endpoint in hub
- `both`: peering + private endpoint request

Important AKS Automatic note:

- In `automaticPrivate`, AKS Automatic uses API server VNet integration.
- The AKS `management` private endpoint path is not supported in that model.
- The template now guards this path and skips PE when API server VNet integration is active.
- For AKS Automatic private, use hub peering + private DNS link as the supported pattern.

## Optional + BYO matrix

The template is designed so most components are optional and many can be
bring-your-own (BYO):

| Area | Optional? | BYO support | Key parameters |
|---|---|---|---|
| AKS cluster | No | No (cluster is the primary resource) | `clusterName`, `mode` |
| Log Analytics | Yes | Name-based reuse in same RG | `logAnalyticsWorkspaceName` (empty = skip) |
| Azure Monitor workspace | Yes | Name-based reuse in same RG | `azureMonitorWorkspaceName` (empty = skip) |
| Managed Grafana | Yes | Name-based reuse in same RG | `enableManagedGrafana`, `managedGrafanaName` |
| ACR | Yes | Yes (cross-sub/RG IDs) | `acrMode`, `acrName`, `existingAcrIds` |
| Spoke VNet/subnet | Yes (for private mode) | Yes | `byoVnetSubnetId`, `byoPodSubnetId` |
| Private DNS zone | Yes | Yes (cross-sub/RG ID) | `byoPrivateDnsZoneId` |
| Hub VNet | Yes | Yes | `hubConnectivityMode`, `byoHubVnetId` |
| Hub Bastion subnet | Yes | Yes | `byoHubBastionSubnetId` |
| Hub jumpbox subnet | Yes | Yes | `byoHubJumpboxSubnetId` |
| Hub PE subnet | Yes | Yes | `byoHubPeSubnetId` |
| Bastion | Yes | N/A (resource optional) | `deployBastion`, `bastionSku` |
| Jumpbox | Yes | N/A (resource optional) | `deployJumpbox`, `jumpboxSshPublicKey` |

Notes:

- BYO IDs can point to other subscriptions/resource groups as long as the
  deploying principal has required rights at those scopes.
- In `automaticPrivate`, if BYO hub VNet is used with Bastion/Jumpbox, provide
  BYO subnet IDs as well.
- AKS Automatic private mode still follows the API server VNet integration
  behavior described above.

## Wizard behavior

The wizard now generates overrides from explicit optional/BYO fields, so users
do not need to handcraft a large `-Overrides` block. A manual append box still
exists for advanced parameters not exposed in the UI.

Built-in one-click presets:

- `1) Minimum Cost`: managed mode, no hub, no Bastion/jumpbox, minimal add-ons.
- `2) Private Enterprise`: private mode, peering + Bastion + jumpbox, monitoring on, existing ACR flow.
- `3) BYO Everything`: private mode with BYO placeholders for spoke subnet, private DNS zone, hub VNet, and hub subnets.

These presets are starting points; every field remains editable after applying a preset.

## Bastion + jumpbox access

For native `az network bastion ssh` client access you need:

- Bastion Standard SKU
- `enableTunneling = true`
- Azure CLI extensions: `bastion` and `ssh`

If `az network bastion ssh` still fails locally, use tunnel mode (works reliably):

```powershell
$vmId = az vm show -g rg-ca -n vm-aks-ca-jb --query id -o tsv
az network bastion tunnel --name bas-aks-ca --resource-group rg-ca --target-resource-id $vmId --resource-port 22 --port 50022
```

Then in another shell:

```powershell
ssh -i .deploy\jumpbox_id_rsa -p 50022 azureuser@127.0.0.1
```

## Azure RBAC on cluster (kubectl authorization)

`kubectl` errors like `nodes is forbidden` indicate Azure RBAC role assignment issues,
not network reachability. For jumpbox managed identity access, assign at least:

- `Azure Kubernetes Service Cluster User Role`
- `Azure Kubernetes Service RBAC Cluster Admin` (or a narrower custom role as needed)

at the AKS cluster scope.

## Customization — every name is overridable

Any of these (in `main.bicepparam` or via `-Overrides` / `--set`):

- `resourceGroupName`, `nodeResourceGroupName`, `clusterName`, `dnsPrefix`, `fqdnSubdomain`
- `controlPlaneIdentityName`, `kubeletIdentityName`
- `vnetName`, `vnetAddressPrefixes`, `aksSubnetName`, `aksSubnetPrefix`,
  `privateEndpointSubnetName`, `privateEndpointSubnetPrefix`, `aksNsgName`
- `privateDnsZoneName`, `privateDnsVnetLinkName`
- `byoVnetSubnetId`, `byoPodSubnetId`, `byoPrivateDnsZoneId` *(bring-your-own existing resources)*
- `logAnalyticsWorkspaceName`, `azureMonitorWorkspaceName`, `managedGrafanaName`
- `acrMode` (`none` / `new` / `existing`), `acrName`, `existingAcrIds`, `acrSku`

## AKS knobs exposed

Networking, identity, security, observability, add-ons, mesh, storage CSI,
upgrades — every flag from `az aks create` that's relevant to Automatic is a
Bicep parameter:

- `kubernetesVersion`, `supportPlan` (incl. **AKSLongTermSupport**), `nodeResourceGroupRestrictionLevel`
- `apiServerAuthorizedIpRanges`, `enablePrivateCluster`, `privateDnsZone`, `disablePrivateClusterPublicFqdn`
- `disableLocalAccounts`, `enableAzureRbac`, `tenantId`, `clusterAdminGroupObjectIds`
- `enableWorkloadIdentity`, `enableOidcIssuer`, `enableImageCleaner`, `enableKeyvaultSecretsProvider`, `disableRunCommand`
- `enableDefender`, `enableAzurePolicy`, `diskEncryptionSetId`, `enableCostAnalysis`
- `enableAppRouting`, `appRoutingDnsZoneIds`, `appRoutingNginxDefault`
- `enableIstio`, `istioRevisions`, `enableAiToolchainOperator`
- `enableKeda`, `enableVpa`
- `enableDiskCsi`, `enableFileCsi`, `enableBlobCsi`, `enableSnapshotController`
- `networkPlugin`, `networkPluginMode`, `networkDataplane`, `networkPolicy`,
  `podCidr`, `serviceCidr`, `dnsServiceIp`, `outboundType`, `loadBalancerSku`
- `httpProxyConfig` *(object — supports trustedCa)*
- `systemPoolVmSize`, `systemPoolNodeCount`, `systemPoolOsSku`, `systemPoolZones`
- `autoUpgradeChannel`, `nodeOsUpgradeChannel`, `autoUpgradeMaintenanceWindow`, `nodeOsMaintenanceWindow`

## RBAC included

Created automatically and idempotently — **cross-subscription safe**: the VNet,
private DNS zone, and ACRs can live in completely different subscriptions from
the AKS cluster. Each role assignment is deployed to its target resource's own
sub + RG.

- **Control-plane MI** ← `Network Contributor` on the AKS subnet *(any sub/RG)*
- **Control-plane MI** ← `Private DNS Zone Contributor` on the private DNS zone *(any sub/RG)*
- **Control-plane MI** ← `Managed Identity Operator` on the kubelet MI
- **Control-plane MI** ← `DNS Zone Contributor` on each app-routing public DNS zone *(any sub/RG)*
- **Kubelet MI** ← `AcrPull` on each ACR (new or existing, **cross-sub/RG safe**)
- **Admin group** ← `Azure Kubernetes Service RBAC Cluster Admin` + `Azure Kubernetes Service Cluster User Role` on the cluster

> The deploying principal needs `Microsoft.Authorization/roleAssignments/write`
> (Owner or User Access Administrator) on the target RGs in any subscription
> referenced via `byoVnetSubnetId`, `byoPrivateDnsZoneId`, `existingAcrIds`,
> or `appRoutingDnsZoneIds`.

## Outputs

After a successful run, `infra/aks/.deploy/outputs.json` contains the cluster
FQDN (and private FQDN), OIDC issuer URL, kubelet client ID, node RG, and the
exact `az aks get-credentials` command.

## References

- [Overview of AKS Automatic with managed system node pools (preview)](https://learn.microsoft.com/en-us/azure/aks/automatic/aks-automatic-managed-system-node-pools-about)
- [Quickstart: Create an AKS Automatic cluster with managed system node pools](https://learn.microsoft.com/en-us/azure/aks/automatic/aks-automatic-managed-system-node-pools)
- [What is AKS Automatic?](https://learn.microsoft.com/en-us/azure/aks/intro-aks-automatic)
