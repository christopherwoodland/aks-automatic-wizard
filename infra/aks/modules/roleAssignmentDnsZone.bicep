targetScope = 'resourceGroup'

param dnsZoneName string
param principalId string
param roleDefinitionId string

resource zone 'Microsoft.Network/dnsZones@2023-07-01-preview' existing = {
  name: dnsZoneName
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
