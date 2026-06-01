// Azure Bastion (Standard SKU) + dedicated public IP.
targetScope = 'resourceGroup'

@description('Azure region.')
param location string

@description('Bastion host name.')
param bastionName string

@description('AzureBastionSubnet resource ID (must already exist in the hub VNet).')
param bastionSubnetId string

@description('Bastion SKU.')
@allowed([ 'Basic', 'Standard', 'Developer' ])
param sku string = 'Standard'

@description('Public IP name.')
param publicIpName string = '${bastionName}-pip'

@description('Resource tags.')
param tags object = {}

resource pip 'Microsoft.Network/publicIPAddresses@2024-01-01' = if (sku != 'Developer') {
  name: publicIpName
  location: location
  tags: tags
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

resource bastion 'Microsoft.Network/bastionHosts@2024-01-01' = {
  name: bastionName
  location: location
  tags: tags
  sku: { name: sku }
  properties: sku == 'Developer' ? {
    // Developer SKU: no IP config, no scaleUnits
  } : {
    // Required for `az network bastion ssh` (native client / tunneling).
    enableTunneling: sku == 'Standard'
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: { id: bastionSubnetId }
          publicIPAddress: { id: pip.id }
        }
      }
    ]
  }
}

output bastionId string = bastion.id
output bastionName string = bastion.name
