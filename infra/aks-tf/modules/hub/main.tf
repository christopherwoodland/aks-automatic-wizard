variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "hub_vnet_name" {
  type = string
}

variable "hub_address_prefixes" {
  type    = list(string)
  default = ["10.250.0.0/16"]
}

variable "bastion_subnet_prefix" {
  type    = string
  default = "10.250.1.0/26"
}

variable "jumpbox_subnet_name" {
  type    = string
  default = "snet-jumpbox"
}

variable "jumpbox_subnet_prefix" {
  type    = string
  default = "10.250.2.0/27"
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "azurerm_virtual_network" "hub" {
  name                = var.hub_vnet_name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.hub_address_prefixes
  tags                = var.tags
}

# AzureBastionSubnet must be named exactly "AzureBastionSubnet"
resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.bastion_subnet_prefix]
}

resource "azurerm_subnet" "jumpbox" {
  name                 = var.jumpbox_subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.jumpbox_subnet_prefix]
}

output "hub_vnet_id" { value = azurerm_virtual_network.hub.id }
output "hub_vnet_name" { value = azurerm_virtual_network.hub.name }
output "bastion_subnet_id" { value = azurerm_subnet.bastion.id }
output "jumpbox_subnet_id" { value = azurerm_subnet.jumpbox.id }
