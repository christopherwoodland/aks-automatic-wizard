// User-assigned managed identities for the AKS control plane and kubelet.
targetScope = 'resourceGroup'

@description('Azure region.')
param location string

@description('Name of the control-plane user-assigned managed identity.')
param controlPlaneIdentityName string

@description('Name of the kubelet user-assigned managed identity.')
param kubeletIdentityName string

@description('Resource tags.')
param tags object = {}

resource controlPlaneMI 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: controlPlaneIdentityName
  location: location
  tags: tags
}

resource kubeletMI 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: kubeletIdentityName
  location: location
  tags: tags
}

output controlPlaneIdentityId string = controlPlaneMI.id
output controlPlaneIdentityPrincipalId string = controlPlaneMI.properties.principalId
output controlPlaneIdentityClientId string = controlPlaneMI.properties.clientId

output kubeletIdentityId string = kubeletMI.id
output kubeletIdentityPrincipalId string = kubeletMI.properties.principalId
output kubeletIdentityClientId string = kubeletMI.properties.clientId
