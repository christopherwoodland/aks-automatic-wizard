// VNet + AKS subnet (+ optional private-endpoint subnet) + NSG.
// Only used in the 'automaticPrivate' deployment mode (custom VNet path).
targetScope = 'resourceGroup'

@description('Azure region.')
param location string

@description('VNet name.')
param vnetName string

@description('VNet address space (CIDRs).')
param vnetAddressPrefixes array = [ '10.240.0.0/16' ]

@description('AKS node subnet name.')
param aksSubnetName string

@description('AKS node subnet CIDR.')
param aksSubnetPrefix string = '10.240.0.0/22'

@description('Create a dedicated private-endpoint subnet.')
param createPrivateEndpointSubnet bool = true

@description('Private-endpoint subnet name.')
param privateEndpointSubnetName string = 'snet-pe'

@description('Private-endpoint subnet CIDR.')
param privateEndpointSubnetPrefix string = '10.240.4.0/24'

@description('API server VNet integration subnet name (delegated to Microsoft.ContainerService/managedClusters).')
param apiServerSubnetName string = 'snet-apiserver'

@description('API server subnet CIDR. Must be at least /28.')
param apiServerSubnetPrefix string = '10.240.5.0/28'

@description('NSG name attached to the AKS subnet.')
param aksNsgName string

@description('Resource tags.')
param tags object = {}

resource aksNsg 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: aksNsgName
  location: location
  tags: tags
  properties: {
    securityRules: []
  }
}

var aksSubnet = {
  name: aksSubnetName
  properties: {
    addressPrefix: aksSubnetPrefix
    networkSecurityGroup: { id: aksNsg.id }
    privateEndpointNetworkPolicies: 'Disabled'
  }
}

var peSubnet = {
  name: privateEndpointSubnetName
  properties: {
    addressPrefix: privateEndpointSubnetPrefix
    privateEndpointNetworkPolicies: 'Disabled'
  }
}

var apiServerSubnet = {
  name: apiServerSubnetName
  properties: {
    addressPrefix: apiServerSubnetPrefix
    delegations: [
      {
        name: 'aks-delegation'
        properties: { serviceName: 'Microsoft.ContainerService/managedClusters' }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: vnetAddressPrefixes }
    subnets: createPrivateEndpointSubnet ? [ aksSubnet, peSubnet, apiServerSubnet ] : [ aksSubnet, apiServerSubnet ]
  }
}

output vnetId string = vnet.id
output vnetName string = vnet.name
output aksSubnetId string = '${vnet.id}/subnets/${aksSubnetName}'
output privateEndpointSubnetId string = createPrivateEndpointSubnet ? '${vnet.id}/subnets/${privateEndpointSubnetName}' : ''
output apiServerSubnetId string = '${vnet.id}/subnets/${apiServerSubnetName}'
