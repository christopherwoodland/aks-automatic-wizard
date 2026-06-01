variable "resource_group_name" { type = string }
variable "aks_vnet_id" { type = string }
variable "aks_vnet_name" { type = string }
variable "hub_vnet_id" { type = string }
variable "hub_vnet_name" { type = string }
variable "hub_resource_group" { type = string }

# AKS VNet -> Hub
resource "azurerm_virtual_network_peering" "aks_to_hub" {
  name                      = "peer-aks-to-hub"
  resource_group_name       = var.resource_group_name
  virtual_network_name      = var.aks_vnet_name
  remote_virtual_network_id = var.hub_vnet_id
  allow_forwarded_traffic   = true
  allow_gateway_transit     = false
}

# Hub -> AKS VNet
resource "azurerm_virtual_network_peering" "hub_to_aks" {
  name                      = "peer-hub-to-aks"
  resource_group_name       = var.hub_resource_group
  virtual_network_name      = var.hub_vnet_name
  remote_virtual_network_id = var.aks_vnet_id
  allow_forwarded_traffic   = true
  allow_gateway_transit     = false
}
