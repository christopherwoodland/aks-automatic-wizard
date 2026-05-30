// Log Analytics workspace for Container Insights.
targetScope = 'resourceGroup'

@description('Azure region.')
param location string

@description('Workspace name.')
param workspaceName string

@description('Retention in days.')
@minValue(30)
@maxValue(730)
param retentionInDays int = 30

@description('SKU.')
param sku string = 'PerGB2018'

@description('Resource tags.')
param tags object = {}

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: { name: sku }
    retentionInDays: retentionInDays
    features: { enableLogAccessUsingOnlyResourcePermissions: true }
  }
}

output workspaceId string = law.id
output customerId string = law.properties.customerId
