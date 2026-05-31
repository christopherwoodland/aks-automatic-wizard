// AKS Automatic cluster - supports two modes:
//   automaticManaged: AKS-managed VNet + managed system node pools (hostedSystemProfile)
//   automaticPrivate: custom VNet + private API server (NO managed system node pools - not supported)
targetScope = 'resourceGroup'

// ---------- Core ----------
@description('Azure region.')
param location string

@description('AKS cluster name.')
param clusterName string

@description('DNS prefix.')
param dnsPrefix string

@description('Optional FQDN subdomain (private cluster).')
param fqdnSubdomain string = ''

@description('Node resource group name (the AKS-created RG holding cluster infra).')
param nodeResourceGroup string

@description('Node resource group restriction level. AKS Automatic enforces ReadOnly.')
@allowed([ 'Unrestricted', 'ReadOnly' ])
param nodeResourceGroupRestrictionLevel string = 'ReadOnly'

@description('Kubernetes version. Leave empty for AKS-default (Automatic auto-upgrades).')
param kubernetesVersion string = ''

@description('Support plan.')
@allowed([ 'KubernetesOfficial', 'AKSLongTermSupport' ])
param supportPlan string = 'KubernetesOfficial'

@description('Resource tags applied to the cluster.')
param tags object = {}

// ---------- Identity ----------
@description('Resource ID of the control-plane user-assigned managed identity.')
param controlPlaneIdentityId string

@description('Resource ID of the kubelet user-assigned managed identity.')
param kubeletIdentityId string

@description('Client ID of the kubelet identity.')
param kubeletIdentityClientId string

@description('Object/principal ID of the kubelet identity.')
param kubeletIdentityObjectId string

// ---------- Mode toggles ----------
@description('Enable managed system node pools (hostedSystemProfile). Only valid with managed VNet.')
param enableHostedSystem bool = true

@description('Enable a private API server. Requires custom VNet.')
param enablePrivateCluster bool = false

@description('Private DNS zone for the private API server. Use \'system\', \'none\', or a resource ID.')
param privateDnsZone string = 'system'

@description('Disable public FQDN for the private cluster API server.')
param disablePrivateClusterPublicFqdn bool = true

@description('Authorized IP ranges for the public API server (ignored when private).')
param apiServerAuthorizedIpRanges array = []

// ---------- Custom VNet ----------
@description('AKS node subnet resource ID. Empty for managed VNet.')
param vnetSubnetId string = ''

@description('Pod subnet resource ID (optional, for pod-subnet mode).')
param podSubnetId string = ''

// ---------- System pool ----------
@description('System pool VM size (ignored when hostedSystemProfile is enabled).')
param systemPoolVmSize string = 'Standard_D4pds_v5'

@description('System pool initial node count.')
param systemPoolNodeCount int = 3

@description('System pool OS SKU.')
@allowed([ 'AzureLinux', 'Ubuntu' ])
param systemPoolOsSku string = 'AzureLinux'

@description('Availability zones for the system pool.')
param systemPoolZones array = [ '1', '2', '3' ]

// ---------- Networking ----------
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
@allowed([ 'standard', 'basic' ])
param loadBalancerSku string = 'standard'

// ---------- HTTP proxy ----------
@description('HTTP proxy config. Leave empty to disable.')
param httpProxyConfig object = {}

// ---------- Identity / security ----------
@description('Disable Kubernetes local accounts.')
param disableLocalAccounts bool = true

@description('Enable Azure RBAC for Kubernetes authorization.')
param enableAzureRbac bool = true

@description('Entra tenant ID for AAD profile (empty = subscription tenant).')
param tenantId string = ''

@description('Entra group object IDs granted Kubernetes cluster-admin via Azure RBAC.')
param clusterAdminGroupObjectIds array = []

@description('Enable workload identity.')
param enableWorkloadIdentity bool = true

@description('Enable OIDC issuer.')
param enableOidcIssuer bool = true

@description('Enable image cleaner.')
param enableImageCleaner bool = true

@description('Image cleaner scanning interval in hours.')
param imageCleanerIntervalHours int = 168

@description('Enable Key Vault secrets provider (CSI driver).')
param enableKeyvaultSecretsProvider bool = true

@description('Disable run command on the cluster.')
param disableRunCommand bool = false

@description('Enable Microsoft Defender for Containers.')
param enableDefender bool = false

@description('Enable Azure Policy add-on.')
param enableAzurePolicy bool = true

@description('Disk encryption set resource ID (BYOK at-rest).')
param diskEncryptionSetId string = ''

// ---------- Observability ----------
@description('Log Analytics workspace resource ID for Container Insights (empty = disabled).')
param logAnalyticsWorkspaceId string = ''

@description('Azure Monitor (Prometheus) workspace ID (empty = disabled).')
param azureMonitorWorkspaceId string = ''

@description('Enable AKS cost analysis (Standard tier required - Automatic qualifies).')
param enableCostAnalysis bool = true

// ---------- Add-ons / mesh ----------
@description('Enable the application routing (managed NGINX) add-on.')
param enableAppRouting bool = true

@description('Public Azure DNS zone resource IDs to attach to app routing.')
param appRoutingDnsZoneIds array = []

@description('NGINX default ingress controller scope.')
@allowed([ 'AnnotationControlled', 'External', 'Internal', 'None' ])
param appRoutingNginxDefault string = 'AnnotationControlled'

@description('Enable Istio-based service mesh add-on. Not supported with managed system node pools.')
param enableIstio bool = false

@description('Istio revisions (e.g. [\'asm-1-22\']).')
param istioRevisions array = []

@description('Enable AI Toolchain Operator (KAITO).')
param enableAiToolchainOperator bool = false

// ---------- Workload autoscaling ----------
@description('Enable KEDA add-on.')
param enableKeda bool = true

@description('Enable Vertical Pod Autoscaler.')
param enableVpa bool = true

// ---------- Storage CSI drivers ----------
@description('Enable Azure Disk CSI driver.')
param enableDiskCsi bool = true

@description('Enable Azure File CSI driver.')
param enableFileCsi bool = true

@description('Enable Blob CSI driver.')
param enableBlobCsi bool = false

@description('Enable snapshot controller.')
param enableSnapshotController bool = true

// ---------- Upgrades / maintenance ----------
@description('Cluster auto-upgrade channel.')
@allowed([ 'none', 'patch', 'stable', 'rapid', 'node-image' ])
param autoUpgradeChannel string = 'stable'

@description('Node OS upgrade channel.')
@allowed([ 'None', 'Unmanaged', 'SecurityPatch', 'NodeImage' ])
param nodeOsUpgradeChannel string = 'NodeImage'

// ---------- Build ----------
var aadProfile = enableAzureRbac ? {
  managed: true
  enableAzureRBAC: true
  tenantID: empty(tenantId) ? subscription().tenantId : tenantId
  adminGroupObjectIDs: clusterAdminGroupObjectIds
} : null

var apiServerAccessProfile = enablePrivateCluster ? {
  enablePrivateCluster: true
  privateDNSZone: privateDnsZone
  enablePrivateClusterPublicFQDN: !disablePrivateClusterPublicFqdn
  authorizedIPRanges: []
} : (empty(apiServerAuthorizedIpRanges) ? null : {
  enablePrivateCluster: false
  authorizedIPRanges: apiServerAuthorizedIpRanges
})

var systemPool = {
  name: 'systempool'
  mode: 'System'
  osType: 'Linux'
  osSKU: systemPoolOsSku
  count: systemPoolNodeCount
  vmSize: systemPoolVmSize
  type: 'VirtualMachineScaleSets'
  availabilityZones: systemPoolZones
  vnetSubnetID: empty(vnetSubnetId) ? null : vnetSubnetId
  podSubnetID: empty(podSubnetId) ? null : podSubnetId
}

var addonProfiles = union(
  enableKeyvaultSecretsProvider ? {
    azureKeyvaultSecretsProvider: {
      enabled: true
      config: { enableSecretRotation: 'true', rotationPollInterval: '2m' }
    }
  } : {},
  !empty(logAnalyticsWorkspaceId) ? {
    omsagent: {
      enabled: true
      config: {
        logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
        useAADAuth: 'true'
      }
    }
  } : {},
  enableAzurePolicy ? {
    azurepolicy: { enabled: true }
  } : {}
)

var webAppRouting = enableAppRouting ? {
  enabled: true
  dnsZoneResourceIds: appRoutingDnsZoneIds
  nginx: { defaultIngressControllerType: appRoutingNginxDefault }
} : null

var ingressProfile = enableAppRouting ? { webAppRouting: webAppRouting } : null

var serviceMeshProfile = enableIstio ? {
  mode: 'Istio'
  istio: {
    revisions: istioRevisions
    components: {
      ingressGateways: []
      egressGateways: []
    }
  }
} : null

var azureMonitorProfile = !empty(azureMonitorWorkspaceId) ? {
  metrics: {
    enabled: true
    kubeStateMetrics: {
      metricLabelsAllowlist: ''
      metricAnnotationsAllowList: ''
    }
  }
} : null

var workloadAutoScalerProfile = {
  keda: { enabled: enableKeda }
  verticalPodAutoscaler: { enabled: enableVpa }
}

var storageProfile = {
  diskCSIDriver: { enabled: enableDiskCsi }
  fileCSIDriver: { enabled: enableFileCsi }
  blobCSIDriver: { enabled: enableBlobCsi }
  snapshotController: { enabled: enableSnapshotController }
}

var securityProfile = union(
  {
    workloadIdentity: { enabled: enableWorkloadIdentity }
  },
  enableImageCleaner ? {
    imageCleaner: { enabled: true, intervalHours: imageCleanerIntervalHours }
  } : {},
  enableDefender ? {
    defender: {
      logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceId
      securityMonitoring: { enabled: true }
    }
  } : {}
)

var aiToolchainOperatorProfile = enableAiToolchainOperator ? {
  enabled: true
} : null

var metricsProfile = {
  costAnalysis: { enabled: enableCostAnalysis }
}

resource aks 'Microsoft.ContainerService/managedClusters@2025-03-02-preview' = {
  name: clusterName
  location: location
  tags: tags
  sku: {
    name: 'Automatic'
    tier: 'Standard'
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${controlPlaneIdentityId}': {}
    }
  }
  properties: {
    dnsPrefix: dnsPrefix
    fqdnSubdomain: empty(fqdnSubdomain) ? null : fqdnSubdomain
    kubernetesVersion: empty(kubernetesVersion) ? null : kubernetesVersion
    nodeResourceGroup: empty(nodeResourceGroup) ? null : nodeResourceGroup
    nodeResourceGroupProfile: {
      restrictionLevel: nodeResourceGroupRestrictionLevel
    }
    supportPlan: supportPlan
    enableRBAC: true
    disableLocalAccounts: disableLocalAccounts
    #disable-next-line BCP037
    disableRunCommand: disableRunCommand
    #disable-next-line BCP037
    hostedSystemProfile: enableHostedSystem ? { enabled: true } : null
    // When hostedSystemProfile.enabled=true AKS provisions/manages the system pool itself;
    // declaring our own system-mode pool would be rejected by the RP.
    agentPoolProfiles: enableHostedSystem ? [] : [ systemPool ]
    identityProfile: {
      kubeletidentity: {
        resourceId: kubeletIdentityId
        clientId: kubeletIdentityClientId
        objectId: kubeletIdentityObjectId
      }
    }
    networkProfile: {
      networkPlugin: networkPlugin
      networkPluginMode: empty(networkPluginMode) ? null : networkPluginMode
      networkDataplane: networkDataplane
      networkPolicy: networkPolicy
      podCidr: networkPluginMode == 'overlay' ? podCidr : null
      serviceCidr: serviceCidr
      dnsServiceIP: dnsServiceIp
      outboundType: outboundType
      loadBalancerSku: loadBalancerSku
    }
    aadProfile: aadProfile
    apiServerAccessProfile: apiServerAccessProfile
    oidcIssuerProfile: { enabled: enableOidcIssuer }
    securityProfile: securityProfile
    addonProfiles: addonProfiles
    ingressProfile: ingressProfile
    serviceMeshProfile: serviceMeshProfile
    azureMonitorProfile: azureMonitorProfile
    workloadAutoScalerProfile: workloadAutoScalerProfile
    storageProfile: storageProfile
    aiToolchainOperatorProfile: aiToolchainOperatorProfile
    metricsProfile: metricsProfile
    httpProxyConfig: empty(httpProxyConfig) ? null : httpProxyConfig
    diskEncryptionSetID: empty(diskEncryptionSetId) ? null : diskEncryptionSetId
    autoUpgradeProfile: {
      upgradeChannel: autoUpgradeChannel
      nodeOSUpgradeChannel: nodeOsUpgradeChannel
    }
  }
}

output clusterId string = aks.id
output clusterName string = aks.name
output clusterFqdn string = aks.properties.fqdn
output clusterPrivateFqdn string = enablePrivateCluster ? aks.properties.privateFQDN : ''
output oidcIssuerUrl string = enableOidcIssuer ? aks.properties.oidcIssuerProfile.issuerURL : ''
output nodeResourceGroup string = aks.properties.nodeResourceGroup
