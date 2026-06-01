// Cluster-scope role assignment on an existing AKS managed cluster.
targetScope = 'resourceGroup'

@description('AKS cluster name.')
param clusterName string

@description('Principal ID receiving the role.')
param principalId string

@description('Role definition GUID (subscription-scoped).')
param roleDefinitionId string

@description('Principal type.')
param principalType string = 'ServicePrincipal'

resource aks 'Microsoft.ContainerService/managedClusters@2024-09-01' existing = {
  name: clusterName
}

resource ra 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aks.id, principalId, roleDefinitionId)
  scope: aks
  properties: {
    principalId: principalId
    principalType: principalType
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
  }
}
