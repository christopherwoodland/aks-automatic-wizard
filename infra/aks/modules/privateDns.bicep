// Private DNS zone for the AKS private API server + VNet link.
targetScope = 'resourceGroup'

@description('Private DNS zone name. Must be of the form privatelink.<region>.azmk8s.io')
param privateDnsZoneName string

@description('Resource ID of the VNet to link to the zone.')
param vnetId string

@description('Name of the VNet link.')
param vnetLinkName string

@description('Resource tags.')
param tags object = {}

resource zone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: privateDnsZoneName
  location: 'global'
  tags: tags
}

resource link 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: zone
  name: vnetLinkName
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: vnetId }
  }
}

output privateDnsZoneId string = zone.id
output privateDnsZoneName string = zone.name
