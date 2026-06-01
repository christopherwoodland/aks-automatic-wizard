variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "dns_prefix" {
  type = string
}

variable "node_resource_group" {
  type = string
}

variable "node_resource_group_restriction_level" {
  type    = string
  default = "ReadOnly"
}

variable "tags" {
  type    = map(string)
  default = {}
}

# Identity
variable "control_plane_identity_id" {
  type = string
}

variable "kubelet_identity_id" {
  type = string
}

variable "kubelet_identity_client_id" {
  type = string
}

variable "kubelet_identity_object_id" {
  type = string
}

# Mode
variable "enable_hosted_system" {
  type    = bool
  default = true
}

variable "enable_private_cluster" {
  type    = bool
  default = false
}

variable "private_dns_zone_id" {
  type    = string
  default = ""
}

variable "disable_private_cluster_public_fqdn" {
  type    = bool
  default = true
}

variable "api_server_authorized_ip_ranges" {
  type    = list(string)
  default = []
}

variable "fqdn_subdomain" {
  type    = string
  default = ""
}

# Custom VNet
variable "vnet_subnet_id" {
  type    = string
  default = ""
}

variable "pod_subnet_id" {
  type    = string
  default = ""
}

variable "api_server_subnet_id" {
  type    = string
  default = ""
}

# System pool
variable "system_pool_vm_size" {
  type    = string
  default = "Standard_D4ds_v5"
}

variable "system_pool_node_count" {
  type    = number
  default = 3
}

variable "system_pool_os_sku" {
  type    = string
  default = "AzureLinux"
}

variable "system_pool_zones" {
  type    = list(string)
  default = ["1", "2", "3"]
}

# Kubernetes
variable "kubernetes_version" {
  type    = string
  default = ""
}

variable "support_plan" {
  type    = string
  default = "KubernetesOfficial"
}

# Auth
variable "tenant_id" {
  type    = string
  default = ""
}

variable "cluster_admin_group_object_ids" {
  type    = list(string)
  default = []
}

variable "disable_local_accounts" {
  type    = bool
  default = true
}

variable "enable_azure_rbac" {
  type    = bool
  default = true
}

# Add-ons
variable "enable_workload_identity" {
  type    = bool
  default = true
}

variable "enable_oidc_issuer" {
  type    = bool
  default = true
}

variable "enable_image_cleaner" {
  type    = bool
  default = true
}

variable "image_cleaner_interval_hours" {
  type    = number
  default = 168
}

variable "enable_keyvault_secrets_provider" {
  type    = bool
  default = true
}

variable "disable_run_command" {
  type    = bool
  default = false
}

variable "enable_defender" {
  type    = bool
  default = false
}

variable "enable_azure_policy" {
  type    = bool
  default = true
}

variable "disk_encryption_set_id" {
  type    = string
  default = ""
}

variable "enable_cost_analysis" {
  type    = bool
  default = true
}

variable "enable_app_routing" {
  type    = bool
  default = true
}

variable "app_routing_dns_zone_ids" {
  type    = list(string)
  default = []
}

variable "enable_istio" {
  type    = bool
  default = false
}

variable "istio_revisions" {
  type    = list(string)
  default = []
}

variable "enable_ai_toolchain_operator" {
  type    = bool
  default = false
}

variable "enable_keda" {
  type    = bool
  default = true
}

variable "enable_vpa" {
  type    = bool
  default = true
}

variable "enable_disk_csi" {
  type    = bool
  default = true
}

variable "enable_file_csi" {
  type    = bool
  default = true
}

variable "enable_blob_csi" {
  type    = bool
  default = false
}

variable "enable_snapshot_controller" {
  type    = bool
  default = true
}

# Networking
variable "network_plugin" {
  type    = string
  default = "azure"
}

variable "network_plugin_mode" {
  type    = string
  default = "overlay"
}

variable "network_dataplane" {
  type    = string
  default = "cilium"
}

variable "network_policy" {
  type    = string
  default = "cilium"
}

variable "pod_cidr" {
  type    = string
  default = "10.244.0.0/16"
}

variable "service_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "dns_service_ip" {
  type    = string
  default = "10.0.0.10"
}

variable "outbound_type" {
  type    = string
  default = "managedNATGateway"
}

variable "load_balancer_sku" {
  type    = string
  default = "standard"
}

# Upgrade
variable "auto_upgrade_channel" {
  type    = string
  default = "stable"
}

variable "node_os_upgrade_channel" {
  type    = string
  default = "NodeImage"
}

# Observability
variable "log_analytics_workspace_id" {
  type    = string
  default = ""
}

variable "azure_monitor_workspace_id" {
  type    = string
  default = ""
}

locals {
  # AKS Automatic SKU uses the 'Automatic' tier which enables managed system node pools.
  # When using a custom VNet (private mode), managed system node pools are not supported,
  # so we fall back to a user-managed system pool.
  sku_tier = "Standard" # 'Automatic' is set via the automatic_upgrade_channel; AKS Automatic == Standard tier + Automatic upgrade
}

resource "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.dns_prefix
  kubernetes_version  = var.kubernetes_version != "" ? var.kubernetes_version : null
  node_resource_group = var.node_resource_group
  sku_tier            = "Standard"
  support_plan        = var.support_plan
  tags                = var.tags

  # AKS Automatic: enable both flags that constitute the Automatic SKU
  automatic_upgrade_channel = var.auto_upgrade_channel
  node_os_upgrade_channel   = var.node_os_upgrade_channel

  local_account_disabled = var.disable_local_accounts

  dns_prefix_private_cluster = var.fqdn_subdomain != "" ? var.fqdn_subdomain : null

  # ---------- Identity ----------
  identity {
    type         = "UserAssigned"
    identity_ids = [var.control_plane_identity_id]
  }

  kubelet_identity {
    client_id                 = var.kubelet_identity_client_id
    object_id                 = var.kubelet_identity_object_id
    user_assigned_identity_id = var.kubelet_identity_id
  }

  # ---------- System node pool ----------
  # When enable_hosted_system = true (managed VNet), AKS creates and manages the system pool internally.
  # The azurerm provider still requires a default_node_pool block; set enable_auto_scaling = true with
  # node_count = null to let AKS manage it. When false (custom VNet), we define our own pool.
  default_node_pool {
    name                         = "system"
    vm_size                      = var.enable_hosted_system ? "Standard_D4ds_v5" : var.system_pool_vm_size
    node_count                   = var.enable_hosted_system ? null : var.system_pool_node_count
    auto_scaling_enabled         = var.enable_hosted_system ? true : false
    min_count                    = var.enable_hosted_system ? 2 : null
    max_count                    = var.enable_hosted_system ? 1000 : null
    os_sku                       = var.enable_hosted_system ? "AzureLinux" : var.system_pool_os_sku
    zones                        = var.enable_hosted_system ? ["1", "2", "3"] : var.system_pool_zones
    vnet_subnet_id               = var.vnet_subnet_id != "" ? var.vnet_subnet_id : null
    pod_subnet_id                = var.pod_subnet_id != "" ? var.pod_subnet_id : null
    only_critical_addons_enabled = true

    upgrade_settings {
      max_surge = "10%"
    }
  }

  # ---------- Private cluster ----------
  dynamic "api_server_access_profile" {
    for_each = var.enable_private_cluster || length(var.api_server_authorized_ip_ranges) > 0 || var.api_server_subnet_id != "" ? [1] : []
    content {
      authorized_ip_ranges                = !var.enable_private_cluster ? var.api_server_authorized_ip_ranges : []
      virtual_network_integration_enabled = var.api_server_subnet_id != ""
      subnet_id                           = var.api_server_subnet_id != "" ? var.api_server_subnet_id : null
    }
  }

  private_cluster_enabled             = var.enable_private_cluster
  private_dns_zone_id                 = var.enable_private_cluster ? var.private_dns_zone_id : null
  private_cluster_public_fqdn_enabled = var.enable_private_cluster ? !var.disable_private_cluster_public_fqdn : null

  # ---------- Auth ----------
  azure_active_directory_role_based_access_control {
    azure_rbac_enabled     = var.enable_azure_rbac
    tenant_id              = var.tenant_id != "" ? var.tenant_id : null
    admin_group_object_ids = var.cluster_admin_group_object_ids
  }

  # ---------- Network profile ----------
  network_profile {
    network_plugin      = var.network_plugin
    network_plugin_mode = var.network_plugin_mode != "" ? var.network_plugin_mode : null
    network_data_plane  = var.network_dataplane
    network_policy      = var.network_policy
    pod_cidr            = var.network_plugin_mode == "overlay" ? var.pod_cidr : null
    service_cidr        = var.service_cidr
    dns_service_ip      = var.dns_service_ip
    outbound_type       = var.outbound_type
    load_balancer_sku   = var.load_balancer_sku
  }

  # ---------- Add-ons ----------
  workload_identity_enabled = var.enable_workload_identity
  oidc_issuer_enabled       = var.enable_oidc_issuer
  run_command_enabled       = !var.disable_run_command

  image_cleaner_enabled        = var.enable_image_cleaner
  image_cleaner_interval_hours = var.image_cleaner_interval_hours

  dynamic "key_vault_secrets_provider" {
    for_each = var.enable_keyvault_secrets_provider ? [1] : []
    content {
      secret_rotation_enabled  = true
      secret_rotation_interval = "2m"
    }
  }

  dynamic "microsoft_defender" {
    for_each = var.enable_defender && var.log_analytics_workspace_id != "" ? [1] : []
    content {
      log_analytics_workspace_id = var.log_analytics_workspace_id
    }
  }

  dynamic "oms_agent" {
    for_each = var.log_analytics_workspace_id != "" ? [1] : []
    content {
      log_analytics_workspace_id      = var.log_analytics_workspace_id
      msi_auth_for_monitoring_enabled = true
    }
  }

  dynamic "monitor_metrics" {
    for_each = var.azure_monitor_workspace_id != "" ? [1] : []
    content {
      annotations_allowed = null
      labels_allowed      = null
    }
  }

  dynamic "web_app_routing" {
    for_each = var.enable_app_routing ? [1] : []
    content {
      dns_zone_ids = var.app_routing_dns_zone_ids
    }
  }

  dynamic "service_mesh_profile" {
    for_each = var.enable_istio ? [1] : []
    content {
      mode      = "Istio"
      revisions = var.istio_revisions
    }
  }

  dynamic "workload_autoscaler_profile" {
    for_each = (var.enable_keda || var.enable_vpa) ? [1] : []
    content {
      keda_enabled                    = var.enable_keda
      vertical_pod_autoscaler_enabled = var.enable_vpa
    }
  }

  dynamic "storage_profile" {
    for_each = (var.enable_disk_csi || var.enable_file_csi || var.enable_blob_csi || var.enable_snapshot_controller) ? [1] : []
    content {
      disk_driver_enabled         = var.enable_disk_csi
      file_driver_enabled         = var.enable_file_csi
      blob_driver_enabled         = var.enable_blob_csi
      snapshot_controller_enabled = var.enable_snapshot_controller
    }
  }

  ai_toolchain_operator_enabled = var.enable_ai_toolchain_operator

  azure_policy_enabled = var.enable_azure_policy

  cost_analysis_enabled  = var.enable_cost_analysis
  disk_encryption_set_id = var.disk_encryption_set_id != "" ? var.disk_encryption_set_id : null

  lifecycle {
    ignore_changes = [
      # AKS manages the kubernetes_version after initial deployment when auto-upgrade is enabled
      kubernetes_version,
      default_node_pool[0].node_count,
    ]
  }
}

output "cluster_id" { value = azurerm_kubernetes_cluster.main.id }
output "cluster_name" { value = azurerm_kubernetes_cluster.main.name }
output "cluster_fqdn" { value = azurerm_kubernetes_cluster.main.fqdn }
output "private_fqdn" { value = azurerm_kubernetes_cluster.main.private_fqdn }
output "oidc_issuer_url" { value = azurerm_kubernetes_cluster.main.oidc_issuer_url }
output "kube_config_raw" {
  value     = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive = true
}
output "node_resource_group" { value = azurerm_kubernetes_cluster.main.node_resource_group }
