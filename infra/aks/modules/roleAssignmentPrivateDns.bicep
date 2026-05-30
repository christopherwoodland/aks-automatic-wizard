// Cross-subscription / cross-RG safe role assignment on an existing Private DNS zone.
// Deploy this module with: scope: resourceGroup(<subId>, <zoneRgName>)
targetScope = 'resourceGroup'

param zoneName string
param principalId string
param roleDefinitionId string

resource zone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: zoneName
}

resource ra 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(zone.id, principalId, roleDefinitionId)
  scope: zone
  properties: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
  }
}
