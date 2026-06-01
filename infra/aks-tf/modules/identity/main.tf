variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "control_plane_identity_name" {
  type = string
}

variable "kubelet_identity_name" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "azurerm_user_assigned_identity" "control_plane" {
  name                = var.control_plane_identity_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_user_assigned_identity" "kubelet" {
  name                = var.kubelet_identity_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

output "control_plane_identity_id" { value = azurerm_user_assigned_identity.control_plane.id }
output "control_plane_identity_principal_id" { value = azurerm_user_assigned_identity.control_plane.principal_id }
output "control_plane_identity_client_id" { value = azurerm_user_assigned_identity.control_plane.client_id }

output "kubelet_identity_id" { value = azurerm_user_assigned_identity.kubelet.id }
output "kubelet_identity_principal_id" { value = azurerm_user_assigned_identity.kubelet.principal_id }
output "kubelet_identity_client_id" { value = azurerm_user_assigned_identity.kubelet.client_id }
output "kubelet_identity_object_id" { value = azurerm_user_assigned_identity.kubelet.principal_id }
