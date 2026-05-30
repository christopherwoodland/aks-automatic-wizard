// All RBAC needed for AKS to function.
// Designed to be invoked at the RG scope where the AKS-managed resources live.
// Each role assignment is conditional & idempotent (deterministic GUID).
//
// NOTE: BYO subnet and BYO private DNS zone role assignments are handled in
// main.bicep via roleAssignmentSubnet.bicep / roleAssignmentPrivateDns.bicep,
// which are scoped to the target resource's own subscription/RG to support
// cross-subscription BYO networking.
targetScope = 'resourceGroup'

@description('Principal ID of the AKS control-plane managed identity.')
param controlPlaneIdentityPrincipalId string = ''

@description('Principal ID of the AKS kubelet managed identity.')
param kubeletIdentityPrincipalId string = ''

@description('Resource ID of the kubelet identity (so control plane can Managed Identity Operator it).')
param kubeletIdentityResourceId string = ''

@description('ACR resource IDs to grant AcrPull to the kubelet identity.')
param acrIdsForKubeletPull array = []

@description('App-routing DNS zone resource IDs.')
param appRoutingDnsZoneIds array = []

// Built-in role definition IDs (constants).
var roleIds = {
  managedIdentityOperator:   'f1a07417-d97a-45cb-824c-7a7467783830'
  acrPull:                   '7f951dda-4ed3-4680-a7ca-43fe172d538d'
  dnsZoneContributor:        'befefa01-2a29-4197-83a8-272ff33ce314'
}

// --- Kubelet identity: Managed Identity Operator on control-plane MI ---------
resource kubeletMIExisting 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = if (!empty(kubeletIdentityResourceId)) {
  name: last(split(kubeletIdentityResourceId, '/'))
}

resource raKubeletMIO 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(kubeletIdentityResourceId) && !empty(controlPlaneIdentityPrincipalId)) {
  name: guid(kubeletIdentityResourceId, controlPlaneIdentityPrincipalId, roleIds.managedIdentityOperator)
  scope: kubeletMIExisting
  properties: {
    principalId: controlPlaneIdentityPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.managedIdentityOperator)
  }
}

// --- ACR: AcrPull on kubelet MI (per-ACR sub-deployment, cross-sub safe) ----
module acrPullAssignments 'roleAssignmentAcr.bicep' = [for (acrId, i) in acrIdsForKubeletPull: if (!empty(kubeletIdentityPrincipalId)) {
  name: 'acrPull-${i}'
  scope: resourceGroup(split(acrId, '/')[2], split(acrId, '/')[4])
  params: {
    acrName: last(split(acrId, '/'))
    principalId: kubeletIdentityPrincipalId
    roleDefinitionId: roleIds.acrPull
  }
}]

// --- App-routing public DNS zones: DNS Zone Contributor on control-plane MI -
module appRoutingDnsAssignments 'roleAssignmentDnsZone.bicep' = [for (zoneId, i) in appRoutingDnsZoneIds: if (!empty(controlPlaneIdentityPrincipalId)) {
  name: 'appRoutingDns-${i}'
  scope: resourceGroup(split(zoneId, '/')[2], split(zoneId, '/')[4])
  params: {
    dnsZoneName: last(split(zoneId, '/'))
    principalId: controlPlaneIdentityPrincipalId
    roleDefinitionId: roleIds.dnsZoneContributor
  }
}]
