// Cross-subscription / cross-RG safe role assignment on an existing subnet.
// Deploy this module with: scope: resourceGroup(<subId>, <vnetRgName>)
targetScope = 'resourceGroup'

param vnetName string
param subnetName string
param principalId string
param roleDefinitionId string

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' existing = {
  name: '${vnetName}/${subnetName}'
}

resource ra 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subnet.id, principalId, roleDefinitionId)
  scope: subnet
  properties: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
  }
}
