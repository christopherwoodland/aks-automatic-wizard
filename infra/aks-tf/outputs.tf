# ============================================================================
#  AKS Automatic – Terraform outputs
# ============================================================================

output "resource_group_name" {
  description = "Resource group containing the AKS cluster and supporting resources."
  value       = azurerm_resource_group.main.name
}

output "cluster_name" {
  description = "AKS cluster name."
  value       = module.aks.cluster_name
}

output "cluster_id" {
  description = "AKS cluster resource ID."
  value       = module.aks.cluster_id
}

output "cluster_fqdn" {
  description = "Public FQDN of the AKS API server (empty for private-only clusters)."
  value       = module.aks.cluster_fqdn
}

output "private_fqdn" {
  description = "Private FQDN of the AKS API server (private mode only)."
  value       = module.aks.private_fqdn
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL for workload identity federation."
  value       = module.aks.oidc_issuer_url
}

output "node_resource_group" {
  description = "AKS node resource group name."
  value       = module.aks.node_resource_group
}

output "kube_config_command" {
  description = "Azure CLI command to merge AKS credentials."
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${module.aks.cluster_name}"
}

output "control_plane_identity_id" {
  description = "Control-plane managed identity resource ID."
  value       = module.identity.control_plane_identity_id
}

output "kubelet_identity_id" {
  description = "Kubelet managed identity resource ID."
  value       = module.identity.kubelet_identity_id
}

output "acr_login_server" {
  description = "ACR login server (empty when acr_mode = none or existing)."
  value       = var.acr_mode == "new" ? module.acr[0].acr_login_server : ""
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace resource ID."
  value       = length(module.log_analytics) > 0 ? module.log_analytics[0].workspace_id : ""
}

output "bastion_name" {
  description = "Azure Bastion name (empty if not deployed)."
  value       = (local.is_private && var.deploy_bastion) ? module.bastion[0].bastion_name : ""
}

output "jumpbox_private_ip" {
  description = "Jumpbox VM private IP (empty if not deployed)."
  value       = (local.is_private && var.deploy_jumpbox) ? module.jumpbox[0].vm_private_ip : ""
}
