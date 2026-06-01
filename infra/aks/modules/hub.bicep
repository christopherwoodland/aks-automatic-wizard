// Hub VNet for private AKS access (Bastion + jumpbox subnet).
// Only deployed when deployHub=true AND no BYO hub VNet ID is supplied.
targetScope = 'resourceGroup'

@description('Azure region.')
param location string

@description('Hub VNet name.')
param hubVnetName string

@description('Hub VNet address prefixes (CIDRs).')
param hubAddressPrefixes array = [ '10.250.0.0/16' ]

@description('AzureBastionSubnet CIDR (must be >= /26 and named EXACTLY "AzureBastionSubnet").')
param bastionSubnetPrefix string = '10.250.1.0/26'

@description('Jumpbox subnet name.')
param jumpboxSubnetName string = 'snet-jumpbox'

@description('Jumpbox subnet CIDR.')
param jumpboxSubnetPrefix string = '10.250.2.0/27'

@description('Resource tags.')
param tags object = {}

resource hub 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: hubVnetName
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: hubAddressPrefixes }
    subnets: [
      {
        name: 'AzureBastionSubnet'
        properties: { addressPrefix: bastionSubnetPrefix }
      }
      {
        name: jumpboxSubnetName
        properties: { addressPrefix: jumpboxSubnetPrefix }
      }
    ]
  }
}

output hubVnetId string = hub.id
output hubVnetName string = hub.name
output bastionSubnetId string = '${hub.id}/subnets/AzureBastionSubnet'
output jumpboxSubnetId string = '${hub.id}/subnets/${jumpboxSubnetName}'
