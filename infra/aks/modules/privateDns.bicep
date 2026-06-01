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

// Force a fresh GET of the VNet at link-time. This avoids a known eventual-
// consistency race where Microsoft.Network reports the VNet PUT as Succeeded
// before Microsoft.Network/privateDnsZones can resolve it cross-RP, producing
// "Virtual network resource not found" on the VNet link create.
var vnetSegs = split(vnetId, '/')
var vnetRgName = vnetSegs[4]
var vnetName = vnetSegs[8]

resource existingVnet 'Microsoft.Network/virtualNetworks@2024-01-01' existing = {
  name: vnetName
  scope: resourceGroup(vnetRgName)
}

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
    virtualNetwork: { id: existingVnet.id }
  }
}

output privateDnsZoneId string = zone.id
output privateDnsZoneName string = zone.name
