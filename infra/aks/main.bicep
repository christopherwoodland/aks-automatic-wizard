// ============================================================================
//  AKS Automatic - subscription-scope orchestrator
// ----------------------------------------------------------------------------
//  Two modes:
//    automaticManaged  -> AKS-managed VNet + managed system node pools
//    automaticPrivate  -> custom VNet, private API server, private DNS zone
//  Per Microsoft Learn, managed system node pools are NOT supported with a
//  custom VNet, so 'automaticPrivate' automatically disables hostedSystemProfile.
// ============================================================================
targetScope = 'subscription'

// ---------- Mode ----------
@description('Deployment mode.')
@allowed([ 'automaticManaged', 'automaticPrivate' ])
param mode string = 'automaticManaged'

// ---------- Resource group ----------
@description('Resource group name for AKS and supporting resources.')
param resourceGroupName string

@description('Azure region.')
param location string

@description('Tags applied to RG and all resources.')
param tags object = {}

// ---------- Names ----------
@description('AKS cluster name.')
param clusterName string

@description('Node resource group name.')
param nodeResourceGroupName string

@description('DNS prefix for the AKS API server.')
param dnsPrefix string

@description('Control-plane managed identity name.')
param controlPlaneIdentityName string

@description('Kubelet managed identity name.')
param kubeletIdentityName string

@description('Log Analytics workspace name (empty = skip Container Insights).')
param logAnalyticsWorkspaceName string = ''

@description('Azure Monitor (Prometheus) workspace name (empty = skip).')
param azureMonitorWorkspaceName string = ''

@description('Create Azure Managed Grafana.')
param enableManagedGrafana bool = false

@description('Managed Grafana name (when enabled).')
param managedGrafanaName string = ''

// ---------- ACR ----------
@description('ACR mode.')
@allowed([ 'none', 'new', 'existing' ])
param acrMode string = 'none'

@description('New ACR name (when acrMode == new).')
param acrName string = ''

@description('Existing ACR resource IDs to attach (AcrPull on kubelet identity).')
param existingAcrIds array = []

@description('SKU when creating a new ACR.')
@allowed([ 'Basic', 'Standard', 'Premium' ])
param acrSku string = 'Premium'

// ---------- Networking (private mode) ----------
@description('VNet name (private mode).')
param vnetName string = ''

@description('VNet address prefixes.')
param vnetAddressPrefixes array = [ '10.240.0.0/16' ]

@description('AKS subnet name.')
param aksSubnetName string = 'snet-aks'

@description('AKS subnet CIDR.')
param aksSubnetPrefix string = '10.240.0.0/22'

@description('Create a separate private endpoint subnet.')
param createPrivateEndpointSubnet bool = true

@description('Private endpoint subnet name.')
param privateEndpointSubnetName string = 'snet-pe'

@description('Private endpoint subnet CIDR.')
param privateEndpointSubnetPrefix string = '10.240.4.0/24'

@description('API server VNet integration subnet name. AKS Automatic implicitly enables apiserver VNet integration; a dedicated delegated subnet is required when using a custom VNet.')
param apiServerSubnetName string = 'snet-apiserver'

@description('API server subnet CIDR. Must be at least /28 and delegated to Microsoft.ContainerService/managedClusters.')
param apiServerSubnetPrefix string = '10.240.5.0/28'

@description('AKS subnet NSG name.')
param aksNsgName string = ''

@description('Bring-your-own VNet subnet resource ID (skip VNet module).')
param byoVnetSubnetId string = ''

@description('Bring-your-own pod subnet resource ID (optional).')
param byoPodSubnetId string = ''

@description('Private DNS zone name (default: privatelink.<region>.azmk8s.io).')
param privateDnsZoneName string = ''

@description('Bring-your-own private DNS zone resource ID. Empty = create new in this RG.')
param byoPrivateDnsZoneId string = ''

@description('VNet link name for the private DNS zone.')
param privateDnsVnetLinkName string = 'vnet-link'

// ---------- Hub connectivity (private mode only) ----------
@description('Hub-to-AKS connectivity model for the private API server. none = no hub. peering = hub VNet peered to the AKS VNet (cheapest). privateEndpoint = Private Endpoint in the hub VNet (works without peering, ~$7/mo). both = peering + private endpoint.')
@allowed([ 'none', 'peering', 'privateEndpoint', 'both' ])
param hubConnectivityMode string = 'none'

@description('Bring-your-own hub VNet resource ID. Empty = create a new hub VNet in this RG when hubConnectivityMode != none.')
param byoHubVnetId string = ''

@description('Hub VNet name (only used when creating a new hub).')
param hubVnetName string = ''

@description('Hub VNet address prefixes (only used when creating a new hub).')
param hubAddressPrefixes array = [ '10.250.0.0/16' ]

@description('AzureBastionSubnet CIDR (only used when creating a new hub). Must be >= /26.')
param hubBastionSubnetPrefix string = '10.250.1.0/26'

@description('Jumpbox subnet name (only used when creating a new hub).')
param hubJumpboxSubnetName string = 'snet-jumpbox'

@description('Jumpbox subnet CIDR (only used when creating a new hub).')
param hubJumpboxSubnetPrefix string = '10.250.2.0/27'

@description('BYO hub bastion subnet resource ID (full /subscriptions/.../subnets/AzureBastionSubnet). Empty = use bastionSubnetId from new hub.')
param byoHubBastionSubnetId string = ''

@description('BYO hub jumpbox subnet resource ID. Empty = use jumpboxSubnetId from new hub.')
param byoHubJumpboxSubnetId string = ''

@description('BYO hub PE subnet resource ID (used for Private Endpoint when hubConnectivityMode in [privateEndpoint, both]). Empty = use the jumpbox subnet.')
param byoHubPeSubnetId string = ''

@description('Deploy Azure Bastion in the hub.')
param deployBastion bool = false

@description('Azure Bastion SKU.')
@allowed([ 'Basic', 'Standard', 'Developer' ])
param bastionSku string = 'Standard'

@description('Bastion host name.')
param bastionName string = ''

@description('Deploy a Linux jumpbox VM in the hub jumpbox subnet.')
param deployJumpbox bool = false

@description('Jumpbox VM name.')
param jumpboxVmName string = ''

@description('Jumpbox VM size.')
param jumpboxVmSize string = 'Standard_B2s'

@description('Jumpbox admin username.')
param jumpboxAdminUsername string = 'azureuser'

@description('Jumpbox SSH public key (OpenSSH format). Required when deployJumpbox=true.')
@secure()
param jumpboxSshPublicKey string = ''

// ---------- AKS knobs ----------
@description('Kubernetes version.')
param kubernetesVersion string = ''

@description('Support plan.')
@allowed([ 'KubernetesOfficial', 'AKSLongTermSupport' ])
param supportPlan string = 'KubernetesOfficial'

@description('Node RG restriction level.')
@allowed([ 'Unrestricted', 'ReadOnly' ])
param nodeResourceGroupRestrictionLevel string = 'ReadOnly'

@description('FQDN subdomain (optional, private cluster).')
param fqdnSubdomain string = ''

@description('Disable public FQDN for private cluster.')
param disablePrivateClusterPublicFqdn bool = true

@description('Authorized IP ranges (public mode).')
param apiServerAuthorizedIpRanges array = []

@description('Disable local Kubernetes accounts.')
param disableLocalAccounts bool = true

@description('Enable Azure RBAC for K8s authorization.')
param enableAzureRbac bool = true

@description('Tenant ID (empty = subscription tenant).')
param tenantId string = ''

@description('Entra group object IDs granted K8s cluster-admin.')
param clusterAdminGroupObjectIds array = []

@description('Enable workload identity.')
param enableWorkloadIdentity bool = true

@description('Enable OIDC issuer.')
param enableOidcIssuer bool = true

@description('Enable image cleaner.')
param enableImageCleaner bool = true

@description('Image cleaner interval (hours).')
param imageCleanerIntervalHours int = 168

@description('Enable Key Vault secrets provider.')
param enableKeyvaultSecretsProvider bool = true

@description('Disable run command.')
param disableRunCommand bool = false

@description('Enable Defender for Containers.')
param enableDefender bool = false

@description('Enable Azure Policy add-on.')
param enableAzurePolicy bool = true

@description('Disk encryption set ID (BYOK).')
param diskEncryptionSetId string = ''

@description('Enable cost analysis.')
param enableCostAnalysis bool = true

@description('Enable application routing (managed NGINX).')
param enableAppRouting bool = true

@description('Public DNS zone IDs attached to app routing.')
param appRoutingDnsZoneIds array = []

@description('Default NGINX ingress controller scope.')
@allowed([ 'AnnotationControlled', 'External', 'Internal', 'None' ])
param appRoutingNginxDefault string = 'AnnotationControlled'

@description('Enable Istio service mesh.')
param enableIstio bool = false

@description('Istio revisions.')
param istioRevisions array = []

@description('Enable AI Toolchain Operator (KAITO).')
param enableAiToolchainOperator bool = false

@description('Enable KEDA.')
param enableKeda bool = true

@description('Enable VPA.')
param enableVpa bool = true

@description('Enable Disk CSI driver.')
param enableDiskCsi bool = true

@description('Enable File CSI driver.')
param enableFileCsi bool = true

@description('Enable Blob CSI driver.')
param enableBlobCsi bool = false

@description('Enable snapshot controller.')
param enableSnapshotController bool = true

@description('Network plugin.')
@allowed([ 'azure', 'kubenet', 'none' ])
param networkPlugin string = 'azure'

@description('Network plugin mode.')
@allowed([ 'overlay', '' ])
param networkPluginMode string = 'overlay'

@description('Network dataplane.')
@allowed([ 'azure', 'cilium' ])
param networkDataplane string = 'cilium'

@description('Network policy.')
@allowed([ 'azure', 'calico', 'cilium', 'none' ])
param networkPolicy string = 'cilium'

@description('Pod CIDR (overlay).')
param podCidr string = '10.244.0.0/16'

@description('Service CIDR.')
param serviceCidr string = '10.0.0.0/16'

@description('DNS service IP.')
param dnsServiceIp string = '10.0.0.10'

@description('Outbound type.')
@allowed([ 'loadBalancer', 'managedNATGateway', 'userAssignedNATGateway', 'userDefinedRouting' ])
param outboundType string = 'managedNATGateway'

@description('LoadBalancer SKU.')
param loadBalancerSku string = 'standard'

@description('HTTP proxy config (empty = none).')
param httpProxyConfig object = {}

@description('System pool VM size.')
param systemPoolVmSize string = 'Standard_D4pds_v5'

@description('System pool node count.')
param systemPoolNodeCount int = 3

@description('System pool OS SKU.')
@allowed([ 'AzureLinux', 'Ubuntu' ])
param systemPoolOsSku string = 'AzureLinux'

@description('System pool availability zones.')
param systemPoolZones array = [ '1', '2', '3' ]

@description('Cluster auto-upgrade channel.')
@allowed([ 'none', 'patch', 'stable', 'rapid', 'node-image' ])
param autoUpgradeChannel string = 'stable'

@description('Node OS upgrade channel.')
@allowed([ 'None', 'Unmanaged', 'SecurityPatch', 'NodeImage' ])
param nodeOsUpgradeChannel string = 'NodeImage'

@description('Cluster auto-upgrade maintenance window (empty = skip).')
param autoUpgradeMaintenanceWindow object = {}

@description('Node OS maintenance window (empty = skip).')
param nodeOsMaintenanceWindow object = {}

// ============================================================================
//  Derived values
// ============================================================================
var isPrivate = mode == 'automaticPrivate'
var enableHostedSystem = !isPrivate // managed system node pools require managed VNet
var effectivePrivateDnsZoneName = empty(privateDnsZoneName) ? 'privatelink.${location}.azmk8s.io' : privateDnsZoneName
var effectiveNsgName = empty(aksNsgName) ? 'nsg-${aksSubnetName}' : aksNsgName

// ============================================================================
//  Resource group
// ============================================================================
resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// ============================================================================
//  Identities
// ============================================================================
module identityMod 'modules/identity.bicep' = {
  name: 'identity'
  scope: rg
  params: {
    location: location
    controlPlaneIdentityName: controlPlaneIdentityName
    kubeletIdentityName: kubeletIdentityName
    tags: tags
  }
}

// ============================================================================
//  Log Analytics + Azure Monitor (Prometheus) + Grafana (optional)
// ============================================================================
module lawMod 'modules/logAnalytics.bicep' = if (!empty(logAnalyticsWorkspaceName)) {
  name: 'logAnalytics'
  scope: rg
  params: {
    location: location
    workspaceName: logAnalyticsWorkspaceName
    tags: tags
  }
}

module monitorMod 'modules/monitoring.bicep' = if (!empty(azureMonitorWorkspaceName) || enableManagedGrafana) {
  name: 'monitoring'
  scope: rg
  params: {
    location: location
    azureMonitorWorkspaceName: empty(azureMonitorWorkspaceName) ? 'amw-${uniqueString(rg.id)}' : azureMonitorWorkspaceName
    enableManagedGrafana: enableManagedGrafana
    managedGrafanaName: managedGrafanaName
    tags: tags
  }
}

// ============================================================================
//  ACR (new)
// ============================================================================
module acrMod 'modules/acr.bicep' = if (acrMode == 'new') {
  name: 'acr'
  scope: rg
  params: {
    location: location
    acrName: acrName
    sku: acrSku
    disablePublicNetworkAccess: isPrivate && acrSku == 'Premium'
    tags: tags
  }
}

// Guard: when acrMode == 'existing', existingAcrIds must be a non-empty list of full ACR resource IDs.
var _validateAcrExisting = (acrMode == 'existing' && length(existingAcrIds) == 0) ? fail('acrMode="existing" requires at least one entry in existingAcrIds (full /subscriptions/.../Microsoft.ContainerRegistry/registries/<name> resource ID).') : true
var acrIdsForKubelet = _validateAcrExisting && acrMode == 'existing' ? existingAcrIds : (acrMode == 'new' ? [ acrMod!.outputs.acrId ] : [])

// ============================================================================
//  Networking (private mode only, and only if BYO VNet not supplied)
// ============================================================================
module networkMod 'modules/network.bicep' = if (isPrivate && empty(byoVnetSubnetId)) {
  name: 'network'
  scope: rg
  params: {
    location: location
    vnetName: vnetName
    vnetAddressPrefixes: vnetAddressPrefixes
    aksSubnetName: aksSubnetName
    aksSubnetPrefix: aksSubnetPrefix
    createPrivateEndpointSubnet: createPrivateEndpointSubnet
    privateEndpointSubnetName: privateEndpointSubnetName
    privateEndpointSubnetPrefix: privateEndpointSubnetPrefix
    apiServerSubnetName: apiServerSubnetName
    apiServerSubnetPrefix: apiServerSubnetPrefix
    aksNsgName: effectiveNsgName
    tags: tags
  }
}

var effectiveVnetSubnetId = isPrivate ? (empty(byoVnetSubnetId) ? networkMod!.outputs.aksSubnetId : byoVnetSubnetId) : ''
var effectiveApiServerSubnetId = (isPrivate && empty(byoVnetSubnetId)) ? networkMod!.outputs.apiServerSubnetId : ''

// ============================================================================
//  Private DNS (private mode, unless BYO zone supplied)
// ============================================================================
module pdnsMod 'modules/privateDns.bicep' = if (isPrivate && empty(byoPrivateDnsZoneId)) {
  name: 'privateDns'
  scope: rg
  params: {
    privateDnsZoneName: effectivePrivateDnsZoneName
    vnetId: empty(byoVnetSubnetId) ? networkMod!.outputs.vnetId : substring(byoVnetSubnetId, 0, indexOf(byoVnetSubnetId, '/subnets/'))
    vnetLinkName: privateDnsVnetLinkName
    tags: tags
  }
  dependsOn: empty(byoVnetSubnetId) ? [ networkMod ] : []
}

var effectivePrivateDnsZoneId = isPrivate ? (empty(byoPrivateDnsZoneId) ? pdnsMod!.outputs.privateDnsZoneId : byoPrivateDnsZoneId) : ''

// ============================================================================
//  Cross-subscription / cross-RG safe RBAC for the AKS subnet + private DNS
//  zone. The VNet and the private DNS zone may live in entirely different
//  subscriptions from the AKS cluster — we parse sub+RG from the BYO resource
//  IDs when supplied, otherwise we fall back to the locally-created resources
//  in this subscription + resource group.
// ============================================================================
var byoVnet = isPrivate && !empty(byoVnetSubnetId)
var byoPdns = isPrivate && !empty(byoPrivateDnsZoneId)

var vnetSubId           = byoVnet ? split(byoVnetSubnetId, '/')[2]  : subscription().subscriptionId
var vnetRgName          = byoVnet ? split(byoVnetSubnetId, '/')[4]  : resourceGroupName
var vnetNameEffective   = byoVnet ? split(byoVnetSubnetId, '/')[8]  : vnetName
var subnetNameEffective = byoVnet ? split(byoVnetSubnetId, '/')[10] : aksSubnetName

var pdnsSubId            = byoPdns ? split(byoPrivateDnsZoneId, '/')[2] : subscription().subscriptionId
var pdnsRgName           = byoPdns ? split(byoPrivateDnsZoneId, '/')[4] : resourceGroupName
var pdnsZoneNameEffective = byoPdns ? last(split(byoPrivateDnsZoneId, '/')) : effectivePrivateDnsZoneName

// Network Contributor (4d97b98b-1d4f-4787-a291-c67834d212e7) on the AKS subnet
module raSubnet 'modules/roleAssignmentSubnet.bicep' = if (isPrivate) {
  name: 'raSubnet'
  scope: resourceGroup(vnetSubId, vnetRgName)
  // Only depend on networkMod when we created the VNet ourselves; BYO subnet already exists.
  dependsOn: empty(byoVnetSubnetId) ? [ networkMod ] : []
  params: {
    vnetName: vnetNameEffective
    subnetName: subnetNameEffective
    principalId: identityMod.outputs.controlPlaneIdentityPrincipalId
    roleDefinitionId: '4d97b98b-1d4f-4787-a291-c67834d212e7'
  }
}

// Network Contributor on the apiserver VNet integration subnet (only when we created it).
module raApiServerSubnet 'modules/roleAssignmentSubnet.bicep' = if (isPrivate && empty(byoVnetSubnetId)) {
  name: 'raApiServerSubnet'
  scope: rg
  dependsOn: [ networkMod ]
  params: {
    vnetName: vnetNameEffective
    subnetName: apiServerSubnetName
    principalId: identityMod.outputs.controlPlaneIdentityPrincipalId
    roleDefinitionId: '4d97b98b-1d4f-4787-a291-c67834d212e7'
  }
}

// Private DNS Zone Contributor (b12aa53e-6015-4669-85d0-8515ebb3ae7f) on the zone
module raPrivateDns 'modules/roleAssignmentPrivateDns.bicep' = if (isPrivate) {
  name: 'raPrivateDns'
  scope: resourceGroup(pdnsSubId, pdnsRgName)
  // Only depend on pdnsMod when we created the zone ourselves; BYO zone already exists.
  dependsOn: empty(byoPrivateDnsZoneId) ? [ pdnsMod ] : []
  params: {
    zoneName: pdnsZoneNameEffective
    principalId: identityMod.outputs.controlPlaneIdentityPrincipalId
    roleDefinitionId: 'b12aa53e-6015-4669-85d0-8515ebb3ae7f'
  }
}

// ============================================================================
//  Pre-AKS RBAC: kubelet MI (subnet + PDNS handled above for cross-sub safety)
// ============================================================================
module preAksRbac 'modules/roleAssignments.bicep' = {
  name: 'preAksRbac'
  scope: rg
  params: {
    controlPlaneIdentityPrincipalId: identityMod.outputs.controlPlaneIdentityPrincipalId
    kubeletIdentityPrincipalId: identityMod.outputs.kubeletIdentityPrincipalId
    kubeletIdentityResourceId: identityMod.outputs.kubeletIdentityId
    acrIdsForKubeletPull: [] // done post-AKS to keep dependencies clean
    appRoutingDnsZoneIds: []
  }
}

// ============================================================================
//  AKS cluster
// ============================================================================
module aksMod 'modules/aks.bicep' = {
  name: 'aks'
  scope: rg
  dependsOn: [ preAksRbac, raSubnet, raPrivateDns, raApiServerSubnet ]
  params: {
    location: location
    clusterName: clusterName
    dnsPrefix: dnsPrefix
    fqdnSubdomain: fqdnSubdomain
    nodeResourceGroup: nodeResourceGroupName
    nodeResourceGroupRestrictionLevel: nodeResourceGroupRestrictionLevel
    kubernetesVersion: kubernetesVersion
    supportPlan: supportPlan
    tags: tags
    controlPlaneIdentityId: identityMod.outputs.controlPlaneIdentityId
    kubeletIdentityId: identityMod.outputs.kubeletIdentityId
    kubeletIdentityClientId: identityMod.outputs.kubeletIdentityClientId
    kubeletIdentityObjectId: identityMod.outputs.kubeletIdentityPrincipalId
    enableHostedSystem: enableHostedSystem
    enablePrivateCluster: isPrivate
    privateDnsZone: isPrivate ? effectivePrivateDnsZoneId : 'none'
    disablePrivateClusterPublicFqdn: disablePrivateClusterPublicFqdn
    apiServerAuthorizedIpRanges: apiServerAuthorizedIpRanges
    vnetSubnetId: effectiveVnetSubnetId
    podSubnetId: byoPodSubnetId
    apiServerSubnetId: effectiveApiServerSubnetId
    systemPoolVmSize: systemPoolVmSize
    systemPoolNodeCount: systemPoolNodeCount
    systemPoolOsSku: systemPoolOsSku
    systemPoolZones: systemPoolZones
    networkPlugin: networkPlugin
    networkPluginMode: networkPluginMode
    networkDataplane: networkDataplane
    networkPolicy: networkPolicy
    podCidr: podCidr
    serviceCidr: serviceCidr
    dnsServiceIp: dnsServiceIp
    // managedNATGateway only works with AKS-managed VNet. BYO subnet requires loadBalancer (or UDR/user NAT).
    outboundType: isPrivate ? 'loadBalancer' : outboundType
    loadBalancerSku: loadBalancerSku
    httpProxyConfig: httpProxyConfig
    disableLocalAccounts: disableLocalAccounts
    enableAzureRbac: enableAzureRbac
    tenantId: tenantId
    clusterAdminGroupObjectIds: clusterAdminGroupObjectIds
    enableWorkloadIdentity: enableWorkloadIdentity
    enableOidcIssuer: enableOidcIssuer
    enableImageCleaner: enableImageCleaner
    imageCleanerIntervalHours: imageCleanerIntervalHours
    enableKeyvaultSecretsProvider: enableKeyvaultSecretsProvider
    disableRunCommand: disableRunCommand
    enableDefender: enableDefender
    enableAzurePolicy: enableAzurePolicy
    diskEncryptionSetId: diskEncryptionSetId
    logAnalyticsWorkspaceId: empty(logAnalyticsWorkspaceName) ? '' : lawMod!.outputs.workspaceId
    azureMonitorWorkspaceId: empty(azureMonitorWorkspaceName) ? '' : monitorMod!.outputs.azureMonitorWorkspaceId
    enableCostAnalysis: enableCostAnalysis
    enableAppRouting: enableAppRouting
    appRoutingDnsZoneIds: appRoutingDnsZoneIds
    appRoutingNginxDefault: appRoutingNginxDefault
    enableIstio: enableIstio && !enableHostedSystem
    istioRevisions: istioRevisions
    enableAiToolchainOperator: enableAiToolchainOperator
    enableKeda: enableKeda
    enableVpa: enableVpa
    enableDiskCsi: enableDiskCsi
    enableFileCsi: enableFileCsi
    enableBlobCsi: enableBlobCsi
    enableSnapshotController: enableSnapshotController
    autoUpgradeChannel: autoUpgradeChannel
    nodeOsUpgradeChannel: nodeOsUpgradeChannel
  }
}

// ============================================================================
//  Post-AKS RBAC: ACR pull + app-routing DNS + cluster-admin group
// ============================================================================
module postAksRbac 'modules/roleAssignments.bicep' = {
  name: 'postAksRbac'
  scope: rg
  dependsOn: [ aksMod ]
  params: {
    controlPlaneIdentityPrincipalId: identityMod.outputs.controlPlaneIdentityPrincipalId
    kubeletIdentityPrincipalId: identityMod.outputs.kubeletIdentityPrincipalId
    kubeletIdentityResourceId: ''
    acrIdsForKubeletPull: acrIdsForKubelet
    appRoutingDnsZoneIds: appRoutingDnsZoneIds
  }
}

module adminMod 'modules/clusterAdmin.bicep' = if (!empty(clusterAdminGroupObjectIds)) {
  name: 'clusterAdmin'
  scope: rg
  dependsOn: [ aksMod ]
  params: {
    aksClusterName: clusterName
    adminPrincipalIds: clusterAdminGroupObjectIds
    principalType: 'Group'
  }
}

// ============================================================================
//  Maintenance windows (optional)
// ============================================================================
module maintMod 'modules/maintenance.bicep' = if (!empty(autoUpgradeMaintenanceWindow) || !empty(nodeOsMaintenanceWindow)) {
  name: 'maintenance'
  scope: rg
  dependsOn: [ aksMod ]
  params: {
    aksClusterName: clusterName
    autoUpgradeWindow: autoUpgradeMaintenanceWindow
    nodeOsWindow: nodeOsMaintenanceWindow
  }
}

// ============================================================================
//  Hub connectivity for the private API server (private mode only)
// ============================================================================
var wantHub = isPrivate && hubConnectivityMode != 'none'
var createHubVnet = wantHub && empty(byoHubVnetId)
var effectiveHubVnetName = empty(hubVnetName) ? 'vnet-${clusterName}-hub' : hubVnetName
var effectiveBastionName = empty(bastionName) ? 'bas-${clusterName}' : bastionName
var effectiveJumpboxName = empty(jumpboxVmName) ? 'vm-${clusterName}-jb' : jumpboxVmName

module hubMod 'modules/hub.bicep' = if (createHubVnet) {
  name: 'hub'
  scope: rg
  params: {
    location: location
    hubVnetName: effectiveHubVnetName
    hubAddressPrefixes: hubAddressPrefixes
    bastionSubnetPrefix: hubBastionSubnetPrefix
    jumpboxSubnetName: hubJumpboxSubnetName
    jumpboxSubnetPrefix: hubJumpboxSubnetPrefix
    tags: tags
  }
}

var effectiveHubVnetId = createHubVnet ? hubMod!.outputs.hubVnetId : byoHubVnetId
var byoHubSegs = split(byoHubVnetId, '/')
var hubSubId = wantHub ? (createHubVnet ? subscription().subscriptionId : byoHubSegs[2]) : ''
var hubRgName = wantHub ? (createHubVnet ? resourceGroupName : byoHubSegs[4]) : ''
var hubVnetNameEffective = wantHub ? (createHubVnet ? effectiveHubVnetName : byoHubSegs[8]) : ''
var effectiveBastionSubnetId = createHubVnet ? hubMod!.outputs.bastionSubnetId : byoHubBastionSubnetId
var effectiveJumpboxSubnetId = createHubVnet ? hubMod!.outputs.jumpboxSubnetId : byoHubJumpboxSubnetId
var effectivePeSubnetId = !empty(byoHubPeSubnetId) ? byoHubPeSubnetId : effectiveJumpboxSubnetId

// Peering both ways
var wantPeering = wantHub && (hubConnectivityMode == 'peering' || hubConnectivityMode == 'both')
module peerHubToSpoke 'modules/peering.bicep' = if (wantPeering) {
  name: 'peer-hub-to-spoke'
  scope: resourceGroup(hubSubId, hubRgName)
  dependsOn: createHubVnet ? [ hubMod ] : []
  params: {
    localVnetName: hubVnetNameEffective
    remoteVnetId: empty(byoVnetSubnetId) ? networkMod!.outputs.vnetId : substring(byoVnetSubnetId, 0, indexOf(byoVnetSubnetId, '/subnets/'))
    peeringName: 'to-${vnetNameEffective}'
  }
}
module peerSpokeToHub 'modules/peering.bicep' = if (wantPeering) {
  name: 'peer-spoke-to-hub'
  scope: resourceGroup(vnetSubId, vnetRgName)
  dependsOn: empty(byoVnetSubnetId) ? [ networkMod ] : []
  params: {
    localVnetName: vnetNameEffective
    remoteVnetId: effectiveHubVnetId
    peeringName: 'to-${hubVnetNameEffective}'
  }
}

// Extra DNS zone link so hub VNet resolves privatelink.<region>.azmk8s.io.
// Needed for BOTH peering and PE modes (PE also requires the hub VNet to be
// linked so VMs in the hub can resolve the cluster's privatelink record).
// Only when we created the zone ourselves (BYO zone: user wires their own links).
module hubPdnsLink 'modules/privateDnsLink.bicep' = if (wantHub && empty(byoPrivateDnsZoneId)) {
  name: 'hubPdnsLink'
  scope: rg
  dependsOn: createHubVnet ? [ pdnsMod, hubMod ] : [ pdnsMod ]
  params: {
    privateDnsZoneName: effectivePrivateDnsZoneName
    vnetId: effectiveHubVnetId
    linkName: 'hub-${uniqueString(effectiveHubVnetId)}'
    tags: tags
  }
}

// Private Endpoint to AKS (groupId='management') in the hub VNet.
// NOTE: PE on the 'management' groupId is for *legacy* private clusters only.
// AKS Automatic uses API Server VNet Integration (the API server already has a
// private NIC in snet-apiserver), which is mutually exclusive with PE — ARM
// returns a generic InternalServerError. Skip PE whenever VNet integration is
// active (i.e. whenever we provisioned an apiserver subnet — same predicate
// used to set apiServerSubnetId on the cluster).
var apiServerVnetIntegrationActive = isPrivate && empty(byoVnetSubnetId)
var wantPe = wantHub && (hubConnectivityMode == 'privateEndpoint' || hubConnectivityMode == 'both') && !apiServerVnetIntegrationActive
module aksPe 'modules/aksPrivateEndpoint.bicep' = if (wantPe) {
  name: 'aksPe'
  scope: resourceGroup(hubSubId, hubRgName)
  params: {
    location: location
    peName: 'pe-${clusterName}-mgmt'
    aksClusterId: aksMod.outputs.clusterId
    subnetId: effectivePeSubnetId
    privateDnsZoneId: empty(byoPrivateDnsZoneId) ? pdnsMod!.outputs.privateDnsZoneId : byoPrivateDnsZoneId
    tags: tags
  }
}

// Bastion
module bastionMod 'modules/bastion.bicep' = if (wantHub && deployBastion) {
  name: 'bastion'
  scope: resourceGroup(hubSubId, hubRgName)
  dependsOn: createHubVnet ? [ hubMod ] : []
  params: {
    location: location
    bastionName: effectiveBastionName
    bastionSubnetId: effectiveBastionSubnetId
    sku: bastionSku
    tags: tags
  }
}

// Jumpbox VM
module jumpboxMod 'modules/jumpbox.bicep' = if (wantHub && deployJumpbox) {
  name: 'jumpbox'
  scope: resourceGroup(hubSubId, hubRgName)
  dependsOn: createHubVnet ? [ hubMod ] : []
  params: {
    location: location
    vmName: effectiveJumpboxName
    subnetId: effectiveJumpboxSubnetId
    vmSize: jumpboxVmSize
    adminUsername: jumpboxAdminUsername
    sshPublicKey: jumpboxSshPublicKey
    aksClusterId: aksMod.outputs.clusterId
    tags: tags
  }
}

// Grant the jumpbox managed identity AKS RBAC Cluster User so it can pull kubeconfig
module jumpboxAksUser 'modules/roleAssignmentAks.bicep' = if (wantHub && deployJumpbox) {
  name: 'jumpboxAksUser'
  scope: rg
  dependsOn: [ aksMod ]
  params: {
    clusterName: clusterName
    principalId: jumpboxMod!.outputs.principalId
    roleDefinitionId: '4abbcc35-e782-43d8-92c5-2d3f1bd2253f'
  }
}


// ============================================================================
//  Outputs
// ============================================================================
output resourceGroupName string = rg.name
output clusterName string = aksMod.outputs.clusterName
output clusterId string = aksMod.outputs.clusterId
output clusterFqdn string = aksMod.outputs.clusterFqdn
output clusterPrivateFqdn string = aksMod.outputs.clusterPrivateFqdn
output oidcIssuerUrl string = aksMod.outputs.oidcIssuerUrl
output nodeResourceGroup string = aksMod.outputs.nodeResourceGroup
output controlPlaneIdentityId string = identityMod.outputs.controlPlaneIdentityId
output kubeletIdentityClientId string = identityMod.outputs.kubeletIdentityClientId
output acrLoginServer string = acrMode == 'new' ? acrMod!.outputs.acrLoginServer : ''
output getCredentialsCommand string = 'az aks get-credentials --resource-group ${rg.name} --name ${aksMod.outputs.clusterName} --overwrite-existing'

// Hub / Bastion / Jumpbox / PE
output hubVnetId string = wantHub ? effectiveHubVnetId : ''
output hubResourceGroup string = wantHub ? hubRgName : ''
output bastionName string = (wantHub && deployBastion) ? effectiveBastionName : ''
output jumpboxName string = (wantHub && deployJumpbox) ? effectiveJumpboxName : ''
output jumpboxPrincipalId string = (wantHub && deployJumpbox) ? jumpboxMod!.outputs.principalId : ''
output privateEndpointId string = wantPe ? aksPe!.outputs.privateEndpointId : ''
output bastionSshCommand string = (wantHub && deployBastion && deployJumpbox) ? 'az network bastion ssh --name ${effectiveBastionName} --resource-group ${hubRgName} --target-resource-id ${jumpboxMod!.outputs.vmId} --auth-type ssh-key --username ${jumpboxAdminUsername} --ssh-key .deploy/jumpbox_id_rsa' : ''
