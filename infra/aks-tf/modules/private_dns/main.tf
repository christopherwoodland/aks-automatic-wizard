variable "resource_group_name" {
  type = string
}

variable "private_dns_zone_name" {
  type = string
}

variable "vnet_id" {
  type = string
}

variable "vnet_link_name" {
  type    = string
  default = "vnet-link"
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "azurerm_private_dns_zone" "aks" {
  name                = var.private_dns_zone_name
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "aks" {
  name                  = var.vnet_link_name
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.aks.name
  virtual_network_id    = var.vnet_id
  registration_enabled  = false
  tags                  = var.tags
}

output "private_dns_zone_id" { value = azurerm_private_dns_zone.aks.id }
output "private_dns_zone_name" { value = azurerm_private_dns_zone.aks.name }
