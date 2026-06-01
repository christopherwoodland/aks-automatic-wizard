variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "workspace_name" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = var.workspace_name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

output "workspace_id" { value = azurerm_log_analytics_workspace.main.id }
output "workspace_resource_id" { value = azurerm_log_analytics_workspace.main.id }
