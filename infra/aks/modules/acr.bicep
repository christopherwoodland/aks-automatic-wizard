// Azure Container Registry (new) - optional.
targetScope = 'resourceGroup'

@description('Azure region.')
param location string

@description('ACR name (5-50 alphanumeric, globally unique).')
param acrName string

@description('SKU.')
@allowed([ 'Basic', 'Standard', 'Premium' ])
param sku string = 'Premium'

@description('Disable public network access (Premium only).')
param disablePublicNetworkAccess bool = false

@description('Resource tags.')
param tags object = {}

resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: acrName
  location: location
  tags: tags
  sku: { name: sku }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: disablePublicNetworkAccess && sku == 'Premium' ? 'Disabled' : 'Enabled'
    zoneRedundancy: sku == 'Premium' ? 'Enabled' : 'Disabled'
  }
}

output acrId string = acr.id
output acrName string = acr.name
output acrLoginServer string = acr.properties.loginServer
