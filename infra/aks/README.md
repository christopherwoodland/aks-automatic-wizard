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
infra/aks/
├── main.bicep                     # subscription-scope orchestrator
├── main.bicepparam                # all parameters (override anything you want)
├── deploy.ps1                     # progressive driver (Windows / PS Core)
├── deploy.sh                      # progressive driver (Linux/macOS)
└── modules/
    ├── identity.bicep             # control-plane + kubelet UAMI
    ├── network.bicep              # VNet, AKS subnet, PE subnet, NSG
    ├── privateDns.bicep           # privatelink.<region>.azmk8s.io + VNet link
    ├── logAnalytics.bicep         # Container Insights workspace
    ├── monitoring.bicep           # Azure Monitor workspace + optional Grafana
    ├── acr.bicep                  # optional new ACR
    ├── roleAssignments.bicep      # all required RBAC (subnet, MI, DNS, ACR, DNS zones)
    ├── roleAssignmentAcr.bicep
    ├── roleAssignmentDnsZone.bicep
    ├── clusterAdmin.bicep         # Azure RBAC cluster admin/user roles
    ├── aks.bicep                  # the AKS Automatic cluster itself
    └── maintenance.bicep          # optional planned maintenance windows
```

## Quick start

### Fully automated (auto-named, managed-VNet public cluster)

```powershell
cd infra\aks
.\deploy.ps1 -SubscriptionId <sub-id> -Location westus3 -AutoName
```

```bash
cd infra/aks
./deploy.sh -s <sub-id> -l westus3 --auto-name
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
| `Preflight` | az CLI version, `aks-preview`, login, provider registrations, `AKS-AutomaticHostedSystemProfilePreview` feature |
| `Plan` | `az deployment sub what-if` (skip with `-SkipWhatIf`) |
| `Deploy` | Submits `main.bicep` at subscription scope; prints operation failures on error |
| `Smoke` | `az aks get-credentials` + `kubectl get nodes` |

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

Created automatically and idempotently:

- **Control-plane MI** ← `Network Contributor` on the AKS subnet (private mode)
- **Control-plane MI** ← `Private DNS Zone Contributor` on the private DNS zone
- **Control-plane MI** ← `Managed Identity Operator` on the kubelet MI
- **Control-plane MI** ← `DNS Zone Contributor` on each app-routing public DNS zone
- **Kubelet MI** ← `AcrPull` on each ACR (new or existing, cross-RG/sub safe)
- **Admin group** ← `Azure Kubernetes Service RBAC Cluster Admin` + `Azure Kubernetes Service Cluster User Role` on the cluster

## Outputs

After a successful run, `infra/aks/.deploy/outputs.json` contains the cluster
FQDN (and private FQDN), OIDC issuer URL, kubelet client ID, node RG, and the
exact `az aks get-credentials` command.

## References

- [Overview of AKS Automatic with managed system node pools (preview)](https://learn.microsoft.com/en-us/azure/aks/automatic/aks-automatic-managed-system-node-pools-about)
- [Quickstart: Create an AKS Automatic cluster with managed system node pools](https://learn.microsoft.com/en-us/azure/aks/automatic/aks-automatic-managed-system-node-pools)
- [What is AKS Automatic?](https://learn.microsoft.com/en-us/azure/aks/intro-aks-automatic)
