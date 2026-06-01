// Adds an additional VNet link to an existing Private DNS zone.
// Used to link the hub VNet to the AKS privatelink.<region>.azmk8s.io zone
// (the spoke link is created by privateDns.bicep).
targetScope = 'resourceGroup'

@description('Existing private DNS zone name.')
param privateDnsZoneName string

@description('Resource ID of the VNet to link.')
param vnetId string

@description('Link name (unique within the zone).')
param linkName string

@description('Resource tags.')
param tags object = {}

// Force a fresh GET (mirrors privateDns.bicep) to avoid cross-RP races.
var segs = split(vnetId, '/')
var vnetRg = segs[4]
var vnetName = segs[8]

resource existingVnet 'Microsoft.Network/virtualNetworks@2024-01-01' existing = {
  name: vnetName
  scope: resourceGroup(vnetRg)
}

resource zone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: privateDnsZoneName
}

resource link 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: zone
  name: linkName
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: existingVnet.id }
  }
}
