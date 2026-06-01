# ============================================================================
#  AKS Automatic – Terraform root module
#  Mirrors the Bicep deployment at infra/aks/main.bicep.
#  Two modes:
#    automaticManaged  – AKS-managed VNet + hosted system node pools
#    automaticPrivate  – custom VNet, private API server, private DNS zone
# ============================================================================

data "azurerm_subscription" "current" {}
data "azurerm_client_config" "current" {}

# ---------- Derived locals ----------
locals {
  is_private = var.mode == "automaticPrivate"

  rg_name               = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.env_name}"
  cluster_name          = var.cluster_name != "" ? var.cluster_name : "aks-${var.env_name}"
  node_rg_name          = var.node_resource_group_name != "" ? var.node_resource_group_name : "rg-${var.env_name}-nodes"
  dns_prefix            = var.dns_prefix != "" ? var.dns_prefix : "aks-${var.env_name}"
  cp_identity_name      = var.control_plane_identity_name != "" ? var.control_plane_identity_name : "id-${var.env_name}-cp"
  kubelet_identity_name = var.kubelet_identity_name != "" ? var.kubelet_identity_name : "id-${var.env_name}-kubelet"
  vnet_name             = var.vnet_name != "" ? var.vnet_name : "vnet-${var.env_name}"
  hub_vnet_name         = var.hub_vnet_name != "" ? var.hub_vnet_name : "vnet-${var.env_name}-hub"
  bastion_name          = var.bastion_name != "" ? var.bastion_name : "bas-${var.env_name}"
  jumpbox_vm_name       = var.jumpbox_vm_name != "" ? var.jumpbox_vm_name : "vm-${var.env_name}-jb"
  nsg_name              = var.aks_nsg_name != "" ? var.aks_nsg_name : "nsg-${var.aks_subnet_name}"
  private_dns_zone_name = var.private_dns_zone_name != "" ? var.private_dns_zone_name : "privatelink.${var.location}.azmk8s.io"
  tenant_id             = var.tenant_id != "" ? var.tenant_id : data.azurerm_client_config.current.tenant_id

  # For ACR - merge the new ACR id if mode==new
  acr_ids_for_kubelet = var.acr_mode == "new" ? [module.acr[0].acr_id] : (
    var.acr_mode == "existing" ? var.existing_acr_ids : []
  )

  # Effective subnet IDs (private mode)
  effective_vnet_subnet_id       = local.is_private ? (var.byo_vnet_subnet_id != "" ? var.byo_vnet_subnet_id : (length(module.network) > 0 ? module.network[0].aks_subnet_id : "")) : ""
  effective_api_server_subnet_id = (local.is_private && var.byo_vnet_subnet_id == "") ? (length(module.network) > 0 ? module.network[0].api_server_subnet_id : "") : ""
  effective_private_dns_zone_id  = local.is_private ? (var.byo_private_dns_zone_id != "" ? var.byo_private_dns_zone_id : (length(module.private_dns) > 0 ? module.private_dns[0].private_dns_zone_id : "")) : ""

  # Hub subnet IDs
  effective_bastion_subnet_id = var.byo_hub_bastion_subnet_id != "" ? var.byo_hub_bastion_subnet_id : (length(module.hub) > 0 ? module.hub[0].bastion_subnet_id : "")
  effective_jumpbox_subnet_id = var.byo_hub_jumpbox_subnet_id != "" ? var.byo_hub_jumpbox_subnet_id : (length(module.hub) > 0 ? module.hub[0].jumpbox_subnet_id : "")
  effective_hub_vnet_id       = var.byo_hub_vnet_id != "" ? var.byo_hub_vnet_id : (length(module.hub) > 0 ? module.hub[0].hub_vnet_id : "")
}

# ---------- Resource group ----------
resource "azurerm_resource_group" "main" {
  name     = local.rg_name
  location = var.location
  tags     = var.tags
}

# ---------- Identities ----------
module "identity" {
  source = "./modules/identity"

  location                    = azurerm_resource_group.main.location
  resource_group_name         = azurerm_resource_group.main.name
  control_plane_identity_name = local.cp_identity_name
  kubelet_identity_name       = local.kubelet_identity_name
  tags                        = var.tags
}

# ---------- Log Analytics ----------
module "log_analytics" {
  source = "./modules/log_analytics"
  count  = var.log_analytics_workspace_name != "" ? 1 : 0

  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_name      = var.log_analytics_workspace_name
  tags                = var.tags
}

# ---------- Azure Monitor (Prometheus) + Grafana ----------
module "monitoring" {
  source = "./modules/monitoring"
  count  = (var.azure_monitor_workspace_name != "" || var.enable_managed_grafana) ? 1 : 0

  location                     = azurerm_resource_group.main.location
  resource_group_name          = azurerm_resource_group.main.name
  azure_monitor_workspace_name = var.azure_monitor_workspace_name != "" ? var.azure_monitor_workspace_name : "amw-${var.env_name}"
  enable_managed_grafana       = var.enable_managed_grafana
  managed_grafana_name         = var.managed_grafana_name != "" ? var.managed_grafana_name : "grafana-${var.env_name}"
  tags                         = var.tags
}

# ---------- ACR (new) ----------
module "acr" {
  source = "./modules/acr"
  count  = var.acr_mode == "new" ? 1 : 0

  location                      = azurerm_resource_group.main.location
  resource_group_name           = azurerm_resource_group.main.name
  acr_name                      = var.acr_name
  sku                           = var.acr_sku
  disable_public_network_access = local.is_private && var.acr_sku == "Premium"
  tags                          = var.tags
}

# ---------- Networking (private mode only, no BYO subnet) ----------
module "network" {
  source = "./modules/network"
  count  = local.is_private && var.byo_vnet_subnet_id == "" ? 1 : 0

  location                       = azurerm_resource_group.main.location
  resource_group_name            = azurerm_resource_group.main.name
  vnet_name                      = local.vnet_name
  vnet_address_prefixes          = var.vnet_address_prefixes
  aks_subnet_name                = var.aks_subnet_name
  aks_subnet_prefix              = var.aks_subnet_prefix
  create_private_endpoint_subnet = var.create_private_endpoint_subnet
  private_endpoint_subnet_name   = var.private_endpoint_subnet_name
  private_endpoint_subnet_prefix = var.private_endpoint_subnet_prefix
  api_server_subnet_name         = var.api_server_subnet_name
  api_server_subnet_prefix       = var.api_server_subnet_prefix
  nsg_name                       = local.nsg_name
  tags                           = var.tags
}

# ---------- Private DNS zone (private mode, no BYO zone) ----------
module "private_dns" {
  source = "./modules/private_dns"
  count  = local.is_private && var.byo_private_dns_zone_id == "" ? 1 : 0

  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = local.private_dns_zone_name
  vnet_id               = var.byo_vnet_subnet_id != "" ? join("/", slice(split("/", var.byo_vnet_subnet_id), 0, 9)) : module.network[0].vnet_id
  vnet_link_name        = var.private_dns_vnet_link_name
  tags                  = var.tags

  depends_on = [module.network]
}

# ---------- Hub VNet (when hub_connectivity_mode != none and no BYO hub) ----------
module "hub" {
  source = "./modules/hub"
  count  = (local.is_private && var.hub_connectivity_mode != "none" && var.byo_hub_vnet_id == "") ? 1 : 0

  location              = azurerm_resource_group.main.location
  resource_group_name   = azurerm_resource_group.main.name
  hub_vnet_name         = local.hub_vnet_name
  hub_address_prefixes  = var.hub_address_prefixes
  bastion_subnet_prefix = var.hub_bastion_subnet_prefix
  jumpbox_subnet_name   = var.hub_jumpbox_subnet_name
  jumpbox_subnet_prefix = var.hub_jumpbox_subnet_prefix
  tags                  = var.tags
}

# ---------- VNet peering (hub <-> AKS) ----------
module "peering" {
  source = "./modules/peering"
  count  = (local.is_private && contains(["peering", "both"], var.hub_connectivity_mode)) ? 1 : 0

  resource_group_name = azurerm_resource_group.main.name
  aks_vnet_id         = var.byo_vnet_subnet_id != "" ? join("/", slice(split("/", var.byo_vnet_subnet_id), 0, 9)) : module.network[0].vnet_id
  aks_vnet_name       = var.byo_vnet_subnet_id != "" ? split("/", var.byo_vnet_subnet_id)[8] : module.network[0].vnet_name
  hub_vnet_id         = local.effective_hub_vnet_id
  hub_vnet_name       = var.byo_hub_vnet_id != "" ? split("/", var.byo_hub_vnet_id)[8] : module.hub[0].hub_vnet_name
  hub_resource_group  = var.byo_hub_vnet_id != "" ? split("/", var.byo_hub_vnet_id)[4] : azurerm_resource_group.main.name

  depends_on = [module.network, module.hub]
}

# ---------- Azure Bastion ----------
module "bastion" {
  source = "./modules/bastion"
  count  = (local.is_private && var.deploy_bastion) ? 1 : 0

  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  bastion_name        = local.bastion_name
  bastion_sku         = var.bastion_sku
  bastion_subnet_id   = local.effective_bastion_subnet_id
  tags                = var.tags

  depends_on = [module.hub]
}

# ---------- Jumpbox ----------
module "jumpbox" {
  source = "./modules/jumpbox"
  count  = (local.is_private && var.deploy_jumpbox) ? 1 : 0

  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  vm_name             = local.jumpbox_vm_name
  vm_size             = var.jumpbox_vm_size
  admin_username      = var.jumpbox_admin_username
  ssh_public_key      = var.jumpbox_ssh_public_key
  subnet_id           = local.effective_jumpbox_subnet_id
  tags                = var.tags

  depends_on = [module.hub]
}

# ============================================================================
#  RBAC: Network Contributor on AKS subnet for the control-plane identity
# ============================================================================
resource "azurerm_role_assignment" "cp_network_contributor_aks_subnet" {
  count = local.is_private ? 1 : 0

  scope                = local.effective_vnet_subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = module.identity.control_plane_identity_principal_id

  depends_on = [module.network, module.identity]
}

resource "azurerm_role_assignment" "cp_network_contributor_api_subnet" {
  count = (local.is_private && var.byo_vnet_subnet_id == "") ? 1 : 0

  scope                = local.effective_api_server_subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = module.identity.control_plane_identity_principal_id

  depends_on = [module.network, module.identity]
}

# ---------- Private DNS Zone Contributor ----------
resource "azurerm_role_assignment" "cp_private_dns_contributor" {
  count = local.is_private ? 1 : 0

  scope                = local.effective_private_dns_zone_id
  role_definition_name = "Private DNS Zone Contributor"
  principal_id         = module.identity.control_plane_identity_principal_id

  depends_on = [module.private_dns, module.identity]
}

# ---------- Managed Identity Operator (control plane over kubelet) ----------
resource "azurerm_role_assignment" "cp_mi_operator" {
  scope                = module.identity.kubelet_identity_id
  role_definition_name = "Managed Identity Operator"
  principal_id         = module.identity.control_plane_identity_principal_id

  depends_on = [module.identity]
}

# ---------- AcrPull for kubelet on all ACRs ----------
resource "azurerm_role_assignment" "kubelet_acr_pull" {
  for_each = toset(local.acr_ids_for_kubelet)

  scope                = each.value
  role_definition_name = "AcrPull"
  principal_id         = module.identity.kubelet_identity_principal_id

  depends_on = [module.identity, module.acr]
}

# ---------- AKS cluster ----------
module "aks" {
  source = "./modules/aks"

  location                              = azurerm_resource_group.main.location
  resource_group_name                   = azurerm_resource_group.main.name
  cluster_name                          = local.cluster_name
  dns_prefix                            = local.dns_prefix
  node_resource_group                   = local.node_rg_name
  node_resource_group_restriction_level = var.node_resource_group_restriction_level
  tags                                  = var.tags

  # Identity
  control_plane_identity_id  = module.identity.control_plane_identity_id
  kubelet_identity_id        = module.identity.kubelet_identity_id
  kubelet_identity_client_id = module.identity.kubelet_identity_client_id
  kubelet_identity_object_id = module.identity.kubelet_identity_object_id

  # Mode
  enable_hosted_system                = !local.is_private
  enable_private_cluster              = local.is_private
  private_dns_zone_id                 = local.effective_private_dns_zone_id
  disable_private_cluster_public_fqdn = var.disable_private_cluster_public_fqdn
  api_server_authorized_ip_ranges     = var.api_server_authorized_ip_ranges
  fqdn_subdomain                      = var.fqdn_subdomain

  # Custom VNet
  vnet_subnet_id       = local.effective_vnet_subnet_id
  pod_subnet_id        = var.byo_pod_subnet_id
  api_server_subnet_id = local.effective_api_server_subnet_id

  # System pool
  system_pool_vm_size    = var.system_pool_vm_size
  system_pool_node_count = var.system_pool_node_count
  system_pool_os_sku     = var.system_pool_os_sku
  system_pool_zones      = var.system_pool_zones

  # Kubernetes version + support
  kubernetes_version = var.kubernetes_version
  support_plan       = var.support_plan

  # Auth
  tenant_id                      = local.tenant_id
  cluster_admin_group_object_ids = var.cluster_admin_group_object_ids
  disable_local_accounts         = var.disable_local_accounts
  enable_azure_rbac              = var.enable_azure_rbac

  # Add-ons
  enable_workload_identity         = var.enable_workload_identity
  enable_oidc_issuer               = var.enable_oidc_issuer
  enable_image_cleaner             = var.enable_image_cleaner
  image_cleaner_interval_hours     = var.image_cleaner_interval_hours
  enable_keyvault_secrets_provider = var.enable_keyvault_secrets_provider
  disable_run_command              = var.disable_run_command
  enable_defender                  = var.enable_defender
  enable_azure_policy              = var.enable_azure_policy
  disk_encryption_set_id           = var.disk_encryption_set_id
  enable_cost_analysis             = var.enable_cost_analysis
  enable_app_routing               = var.enable_app_routing
  app_routing_dns_zone_ids         = var.app_routing_dns_zone_ids
  enable_istio                     = var.enable_istio
  istio_revisions                  = var.istio_revisions
  enable_ai_toolchain_operator     = var.enable_ai_toolchain_operator
  enable_keda                      = var.enable_keda
  enable_vpa                       = var.enable_vpa
  enable_disk_csi                  = var.enable_disk_csi
  enable_file_csi                  = var.enable_file_csi
  enable_blob_csi                  = var.enable_blob_csi
  enable_snapshot_controller       = var.enable_snapshot_controller

  # Networking
  network_plugin      = var.network_plugin
  network_plugin_mode = var.network_plugin_mode
  network_dataplane   = var.network_dataplane
  network_policy      = var.network_policy
  pod_cidr            = var.pod_cidr
  service_cidr        = var.service_cidr
  dns_service_ip      = var.dns_service_ip
  outbound_type       = var.outbound_type
  load_balancer_sku   = var.load_balancer_sku

  # Upgrade
  auto_upgrade_channel    = var.auto_upgrade_channel
  node_os_upgrade_channel = var.node_os_upgrade_channel

  # Observability
  log_analytics_workspace_id = length(module.log_analytics) > 0 ? module.log_analytics[0].workspace_id : ""
  azure_monitor_workspace_id = length(module.monitoring) > 0 ? module.monitoring[0].azure_monitor_workspace_id : ""

  depends_on = [
    module.identity,
    module.network,
    module.private_dns,
    azurerm_role_assignment.cp_network_contributor_aks_subnet,
    azurerm_role_assignment.cp_private_dns_contributor,
    azurerm_role_assignment.cp_mi_operator,
  ]
}

# ---------- Cluster admin role for jumpbox VM identity (private mode) ----------
resource "azurerm_role_assignment" "jumpbox_aks_user" {
  count = (local.is_private && var.deploy_jumpbox) ? 1 : 0

  scope                = module.aks.cluster_id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = module.jumpbox[0].vm_principal_id

  depends_on = [module.aks, module.jumpbox]
}
