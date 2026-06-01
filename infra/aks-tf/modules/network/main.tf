variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "vnet_name" {
  type = string
}

variable "vnet_address_prefixes" {
  type    = list(string)
  default = ["10.240.0.0/16"]
}

variable "aks_subnet_name" {
  type = string
}

variable "aks_subnet_prefix" {
  type    = string
  default = "10.240.0.0/22"
}

variable "create_private_endpoint_subnet" {
  type    = bool
  default = true
}

variable "private_endpoint_subnet_name" {
  type    = string
  default = "snet-pe"
}

variable "private_endpoint_subnet_prefix" {
  type    = string
  default = "10.240.4.0/24"
}

variable "api_server_subnet_name" {
  type    = string
  default = "snet-apiserver"
}

variable "api_server_subnet_prefix" {
  type    = string
  default = "10.240.5.0/28"
}

variable "nsg_name" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "azurerm_network_security_group" "aks" {
  name                = var.nsg_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_virtual_network" "aks" {
  name                = var.vnet_name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.vnet_address_prefixes
  tags                = var.tags
}

resource "azurerm_subnet" "aks" {
  name                              = var.aks_subnet_name
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.aks.name
  address_prefixes                  = [var.aks_subnet_prefix]
  private_endpoint_network_policies = "Disabled"
}

resource "azurerm_subnet_network_security_group_association" "aks" {
  subnet_id                 = azurerm_subnet.aks.id
  network_security_group_id = azurerm_network_security_group.aks.id
}

resource "azurerm_subnet" "private_endpoint" {
  count                             = var.create_private_endpoint_subnet ? 1 : 0
  name                              = var.private_endpoint_subnet_name
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.aks.name
  address_prefixes                  = [var.private_endpoint_subnet_prefix]
  private_endpoint_network_policies = "Disabled"
}

resource "azurerm_subnet" "api_server" {
  name                 = var.api_server_subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.aks.name
  address_prefixes     = [var.api_server_subnet_prefix]

  delegation {
    name = "aks-delegation"
    service_delegation {
      name    = "Microsoft.ContainerService/managedClusters"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

output "vnet_id" { value = azurerm_virtual_network.aks.id }
output "vnet_name" { value = azurerm_virtual_network.aks.name }
output "aks_subnet_id" { value = azurerm_subnet.aks.id }
output "api_server_subnet_id" { value = azurerm_subnet.api_server.id }
output "private_endpoint_subnet_id" {
  value = var.create_private_endpoint_subnet ? azurerm_subnet.private_endpoint[0].id : ""
}
