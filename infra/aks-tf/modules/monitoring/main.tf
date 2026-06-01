variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "azure_monitor_workspace_name" {
  type = string
}

variable "enable_managed_grafana" {
  type    = bool
  default = false
}

variable "managed_grafana_name" {
  type    = string
  default = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "azurerm_monitor_workspace" "main" {
  name                = var.azure_monitor_workspace_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_dashboard_grafana" "main" {
  count                 = var.enable_managed_grafana ? 1 : 0
  name                  = var.managed_grafana_name
  resource_group_name   = var.resource_group_name
  location              = var.location
  grafana_major_version = 12
  sku                   = "Standard"
  tags                  = var.tags

  identity {
    type = "SystemAssigned"
  }
}

output "azure_monitor_workspace_id" { value = azurerm_monitor_workspace.main.id }
output "grafana_id" { value = length(azurerm_dashboard_grafana.main) > 0 ? azurerm_dashboard_grafana.main[0].id : "" }
