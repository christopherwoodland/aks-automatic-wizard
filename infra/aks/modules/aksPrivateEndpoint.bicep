// Private Endpoint to the AKS managed cluster (groupId='management').
// Creates an NIC in the hub VNet that resolves to the cluster's API server,
// with an automatic DNS zone group pointing at privatelink.<region>.azmk8s.io.
targetScope = 'resourceGroup'

@description('Azure region.')
param location string

@description('Private endpoint name.')
param peName string

@description('AKS cluster resource ID.')
param aksClusterId string

@description('Subnet resource ID in the hub VNet where the PE NIC will be placed.')
param subnetId string

@description('Private DNS zone resource ID for privatelink.<region>.azmk8s.io. Empty = skip DNS zone group (you wire DNS yourself).')
param privateDnsZoneId string = ''

@description('Resource tags.')
param tags object = {}

resource pe 'Microsoft.Network/privateEndpoints@2024-01-01' = {
  name: peName
  location: location
  tags: tags
  properties: {
    subnet: { id: subnetId }
    privateLinkServiceConnections: [
      {
        name: 'aks-mgmt'
        properties: {
          privateLinkServiceId: aksClusterId
          groupIds: [ 'management' ]
        }
      }
    ]
  }
}

resource dnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-01-01' = if (!empty(privateDnsZoneId)) {
  parent: pe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'aks'
        properties: { privateDnsZoneId: privateDnsZoneId }
      }
    ]
  }
}

output privateEndpointId string = pe.id
