// Example parameters file.
// All names left empty are filled by the deploy.ps1 / deploy.sh wrappers using a
// deterministic naming scheme.  Pass -AutoName to accept all defaults, or fill in below.
// When invoked by `azd up`, AZURE_ENV_NAME / AZURE_LOCATION / AKS_MODE are picked up from env.
using 'main.bicep'

var envName = readEnvironmentVariable('AZURE_ENV_NAME', 'aks-demo')

// ---- Mode ----
param mode = readEnvironmentVariable('AKS_MODE', 'automaticManaged')   // or 'automaticPrivate' or 'standardPrivate'

// ---- Standard mode options (ignored when mode != standardPrivate) ----
param apiServerAccessMode = 'vnetIntegration'   // 'vnetIntegration' or 'privateEndpoint'
param enableOverlay = true                       // true = overlay+cilium; false = flat Azure CNI

// ---- Core ----
param location = readEnvironmentVariable('AZURE_LOCATION', 'westus3')
param resourceGroupName = 'rg-${envName}'
param clusterName = 'aks-${envName}'
param nodeResourceGroupName = 'rg-${envName}-nodes'
param dnsPrefix = 'aks-${envName}'
param controlPlaneIdentityName = 'id-${envName}-cp'
param kubeletIdentityName = 'id-${envName}-kubelet'
param tags = {
  workload: envName
  'azd-env-name': envName
  costCenter: '0000'
  owner: 'platform'
}

// ---- Observability ----
param logAnalyticsWorkspaceName = 'log-${envName}'
param azureMonitorWorkspaceName = 'amw-${envName}'
param enableManagedGrafana = false
param managedGrafanaName = ''

// ---- ACR ----
param acrMode = 'none'                       // 'none' | 'new' | 'existing'
param acrName = ''
param existingAcrIds = []
param acrSku = 'Premium'

// ---- Private mode networking (ignored when mode == automaticManaged) ----
param vnetName = 'vnet-${envName}'
param vnetAddressPrefixes = [ '10.240.0.0/16' ]
param aksSubnetName = 'snet-aks'
param aksSubnetPrefix = '10.240.0.0/22'
param createPrivateEndpointSubnet = true
param privateEndpointSubnetName = 'snet-pe'
param privateEndpointSubnetPrefix = '10.240.4.0/24'
param aksNsgName = ''
param byoVnetSubnetId = ''
param byoPodSubnetId = ''
param privateDnsZoneName = ''                // default: privatelink.<region>.azmk8s.io
param byoPrivateDnsZoneId = ''
param privateDnsVnetLinkName = 'vnet-link'

// ---- Cluster knobs (override anything you want) ----
param kubernetesVersion = ''
param supportPlan = 'KubernetesOfficial'
param nodeResourceGroupRestrictionLevel = 'ReadOnly'
param fqdnSubdomain = ''
param disablePrivateClusterPublicFqdn = true
param apiServerAuthorizedIpRanges = []

param disableLocalAccounts = true
param enableAzureRbac = true
param tenantId = ''
param clusterAdminGroupObjectIds = []        // [ '00000000-0000-0000-0000-000000000000' ]

param enableWorkloadIdentity = true
param enableOidcIssuer = true
param enableImageCleaner = true
param imageCleanerIntervalHours = 168
param enableKeyvaultSecretsProvider = true
param disableRunCommand = false
param enableDefender = false
param enableAzurePolicy = true
param diskEncryptionSetId = ''
param enableCostAnalysis = true

param enableAppRouting = true
param appRoutingDnsZoneIds = []
param appRoutingNginxDefault = 'AnnotationControlled'
param enableIstio = false
param istioRevisions = []
param enableAiToolchainOperator = false

param enableKeda = true
param enableVpa = true
param enableDiskCsi = true
param enableFileCsi = true
param enableBlobCsi = false
param enableSnapshotController = true

param networkPlugin = 'azure'
param networkPluginMode = 'overlay'
param networkDataplane = 'cilium'
param networkPolicy = 'cilium'
param podCidr = '10.244.0.0/16'
param serviceCidr = '10.0.0.0/16'
param dnsServiceIp = '10.0.0.10'
param outboundType = 'managedNATGateway'
param loadBalancerSku = 'standard'
param httpProxyConfig = {}

param systemPoolVmSize = 'Standard_D4ds_v5'
param systemPoolNodeCount = 3
param systemPoolOsSku = 'AzureLinux'
// AKS Automatic SKU requires AvailabilityZones on the system pool. Default to all
// three zones; override per-region if AKS supports a subset (e.g. westus3 = ['2','3']).
// Used only when enableHostedSystem=false (private mode).
param systemPoolZones = ['1', '2', '3']

param autoUpgradeChannel = 'stable'
param nodeOsUpgradeChannel = 'NodeImage'

// Maintenance window examples (uncomment to enable):
// param autoUpgradeMaintenanceWindow = {
//   maintenanceWindow: {
//     schedule: { weekly: { intervalWeeks: 1, dayOfWeek: 'Sunday' } }
//     durationHours: 4
//     utcOffset: '+00:00'
//     startTime: '02:00'
//   }
// }
param autoUpgradeMaintenanceWindow = {}
param nodeOsMaintenanceWindow = {}

// ---- Hub connectivity (private mode only) ----
// Set HUB_CONNECTIVITY_MODE env var to one of: none | peering | privateEndpoint | both
// Note: for AKS Automatic private mode, the API server uses VNet integration;
// management private endpoint is skipped by template guard logic.
param hubConnectivityMode = readEnvironmentVariable('HUB_CONNECTIVITY_MODE', 'none')
// BYO hub VNet resource ID (empty = create new hub VNet in this RG)
param byoHubVnetId = readEnvironmentVariable('HUB_VNET_ID', '')
param hubVnetName = ''
param hubAddressPrefixes = [ '10.250.0.0/16' ]
param hubBastionSubnetPrefix = '10.250.1.0/26'
param hubJumpboxSubnetName = 'snet-jumpbox'
param hubJumpboxSubnetPrefix = '10.250.2.0/27'
param byoHubBastionSubnetId = ''
param byoHubJumpboxSubnetId = ''
param byoHubPeSubnetId = ''

// Bastion / Jumpbox
param deployBastion = bool(readEnvironmentVariable('DEPLOY_BASTION', 'false'))
param bastionSku = readEnvironmentVariable('BASTION_SKU', 'Standard')
param bastionName = ''
param deployJumpbox = bool(readEnvironmentVariable('DEPLOY_JUMPBOX', 'false'))
param jumpboxVmName = ''
param jumpboxVmSize = 'Standard_B2s'
param jumpboxAdminUsername = 'azureuser'
param jumpboxSshPublicKey = readEnvironmentVariable('JUMPBOX_SSH_PUBLIC_KEY', '')
