variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "acr_name" {
  type = string
}

variable "sku" {
  type    = string
  default = "Premium"
}

variable "disable_public_network_access" {
  type    = bool
  default = false
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "azurerm_container_registry" "main" {
  name                          = var.acr_name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  sku                           = var.sku
  admin_enabled                 = false
  public_network_access_enabled = !var.disable_public_network_access
  tags                          = var.tags
}

output "acr_id" { value = azurerm_container_registry.main.id }
output "acr_login_server" { value = azurerm_container_registry.main.login_server }
