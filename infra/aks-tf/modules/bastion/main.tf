variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "bastion_name" {
  type = string
}

variable "bastion_sku" {
  type    = string
  default = "Standard"
}

variable "bastion_subnet_id" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "azurerm_public_ip" "bastion" {
  name                = "pip-${var.bastion_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_bastion_host" "main" {
  name                = var.bastion_name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.bastion_sku
  tags                = var.tags

  ip_configuration {
    name                 = "configuration"
    subnet_id            = var.bastion_subnet_id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }
}

output "bastion_id" { value = azurerm_bastion_host.main.id }
output "bastion_name" { value = azurerm_bastion_host.main.name }
