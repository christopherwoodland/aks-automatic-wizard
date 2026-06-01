// One-direction VNet peering. Deploy twice (hub->spoke and spoke->hub).
targetScope = 'resourceGroup'

@description('Local VNet name (peering is created under this VNet).')
param localVnetName string

@description('Remote VNet resource ID.')
param remoteVnetId string

@description('Peering name.')
param peeringName string

@description('Allow forwarded traffic.')
param allowForwardedTraffic bool = true

@description('Allow gateway transit (set true on the hub side if hub has a gateway).')
param allowGatewayTransit bool = false

@description('Use remote gateways (set true on the spoke side if the hub has a gateway).')
param useRemoteGateways bool = false

resource local 'Microsoft.Network/virtualNetworks@2024-01-01' existing = {
  name: localVnetName
}

resource peering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-01-01' = {
  parent: local
  name: peeringName
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: allowForwardedTraffic
    allowGatewayTransit: allowGatewayTransit
    useRemoteGateways: useRemoteGateways
    remoteVirtualNetwork: { id: remoteVnetId }
  }
}
