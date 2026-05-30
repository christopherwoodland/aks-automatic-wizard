// Optional planned maintenance configurations: 'aksManagedAutoUpgradeSchedule' and 'aksManagedNodeOSUpgradeSchedule'.
targetScope = 'resourceGroup'

@description('Name of the existing AKS cluster.')
param aksClusterName string

@description('Auto-upgrade maintenance window (empty = skip).')
param autoUpgradeWindow object = {}

@description('Node OS maintenance window (empty = skip).')
param nodeOsWindow object = {}

resource aks 'Microsoft.ContainerService/managedClusters@2024-09-01' existing = {
  name: aksClusterName
}

resource autoUpgrade 'Microsoft.ContainerService/managedClusters/maintenanceConfigurations@2024-09-01' = if (!empty(autoUpgradeWindow)) {
  parent: aks
  name: 'aksManagedAutoUpgradeSchedule'
  properties: autoUpgradeWindow
}

resource nodeOs 'Microsoft.ContainerService/managedClusters/maintenanceConfigurations@2024-09-01' = if (!empty(nodeOsWindow)) {
  parent: aks
  name: 'aksManagedNodeOSUpgradeSchedule'
  properties: nodeOsWindow
}
