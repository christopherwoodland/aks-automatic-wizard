// Grants Azure RBAC cluster-admin + cluster-user on the AKS resource to a list of principals.
targetScope = 'resourceGroup'

@description('Name of the existing AKS cluster.')
param aksClusterName string

@description('Object IDs of Entra users/groups/SPs to grant cluster-admin to.')
param adminPrincipalIds array = []

@description('Principal type (User, Group, ServicePrincipal).')
param principalType string = 'Group'

var rbacClusterAdminId = 'b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b' // Azure Kubernetes Service RBAC Cluster Admin
var clusterUserId      = '4abbcc35-e782-43d8-92c5-2d3f1bd2253f' // Azure Kubernetes Service Cluster User Role

resource aks 'Microsoft.ContainerService/managedClusters@2024-09-01' existing = {
  name: aksClusterName
}

resource raAdmin 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for pid in adminPrincipalIds: {
  name: guid(aks.id, pid, rbacClusterAdminId)
  scope: aks
  properties: {
    principalId: pid
    principalType: principalType
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', rbacClusterAdminId)
  }
}]

resource raUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for pid in adminPrincipalIds: {
  name: guid(aks.id, pid, clusterUserId)
  scope: aks
  properties: {
    principalId: pid
    principalType: principalType
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', clusterUserId)
  }
}]
