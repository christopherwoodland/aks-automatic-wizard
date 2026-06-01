# ============================================================================
#  AKS Automatic – Terraform deployment
#  Variables mirror infra/aks/main.bicepparam for parity with the Bicep path.
# ============================================================================

# ---------- Subscription ----------
variable "subscription_id" {
  description = "Azure subscription ID."
  type        = string
}

# ---------- Mode ----------
variable "mode" {
  description = "Deployment mode: automaticManaged or automaticPrivate."
  type        = string
  default     = "automaticManaged"
  validation {
    condition     = contains(["automaticManaged", "automaticPrivate"], var.mode)
    error_message = "mode must be automaticManaged or automaticPrivate."
  }
}

# ---------- Core ----------
variable "location" {
  description = "Azure region."
  type        = string
  default     = "swedencentral"
}

variable "env_name" {
  description = "Short environment name used to derive resource name defaults."
  type        = string
  default     = "aks-dev"
}

variable "resource_group_name" {
  description = "Resource group name. Defaults to rg-<env_name>."
  type        = string
  default     = ""
}

variable "cluster_name" {
  description = "AKS cluster name. Defaults to aks-<env_name>."
  type        = string
  default     = ""
}

variable "node_resource_group_name" {
  description = "AKS node resource group. Defaults to rg-<env_name>-nodes."
  type        = string
  default     = ""
}

variable "dns_prefix" {
  description = "DNS prefix. Defaults to aks-<env_name>."
  type        = string
  default     = ""
}

variable "control_plane_identity_name" {
  description = "Control-plane managed identity name."
  type        = string
  default     = ""
}

variable "kubelet_identity_name" {
  description = "Kubelet managed identity name."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default = {
    workload = "aks"
    owner    = "platform"
  }
}

# ---------- Observability ----------
variable "log_analytics_workspace_name" {
  description = "Log Analytics workspace name. Empty = skip Container Insights."
  type        = string
  default     = ""
}

variable "azure_monitor_workspace_name" {
  description = "Azure Monitor workspace name (Prometheus). Empty = skip."
  type        = string
  default     = ""
}

variable "enable_managed_grafana" {
  description = "Create Azure Managed Grafana."
  type        = bool
  default     = false
}

variable "managed_grafana_name" {
  description = "Managed Grafana name."
  type        = string
  default     = ""
}

# ---------- ACR ----------
variable "acr_mode" {
  description = "ACR mode: none | new | existing."
  type        = string
  default     = "none"
  validation {
    condition     = contains(["none", "new", "existing"], var.acr_mode)
    error_message = "acr_mode must be none, new, or existing."
  }
}

variable "acr_name" {
  description = "New ACR name (when acr_mode = new)."
  type        = string
  default     = ""
}

variable "existing_acr_ids" {
  description = "Existing ACR resource IDs (when acr_mode = existing)."
  type        = list(string)
  default     = []
}

variable "acr_sku" {
  description = "SKU for a new ACR."
  type        = string
  default     = "Premium"
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.acr_sku)
    error_message = "acr_sku must be Basic, Standard, or Premium."
  }
}

# ---------- Networking (private mode) ----------
variable "vnet_name" {
  description = "VNet name (private mode, auto-created)."
  type        = string
  default     = ""
}

variable "vnet_address_prefixes" {
  description = "VNet address space."
  type        = list(string)
  default     = ["10.240.0.0/16"]
}

variable "aks_subnet_name" {
  description = "AKS node subnet name."
  type        = string
  default     = "snet-aks"
}

variable "aks_subnet_prefix" {
  description = "AKS node subnet CIDR."
  type        = string
  default     = "10.240.0.0/22"
}

variable "create_private_endpoint_subnet" {
  description = "Create a dedicated private-endpoint subnet."
  type        = bool
  default     = true
}

variable "private_endpoint_subnet_name" {
  description = "Private endpoint subnet name."
  type        = string
  default     = "snet-pe"
}

variable "private_endpoint_subnet_prefix" {
  description = "Private endpoint subnet CIDR."
  type        = string
  default     = "10.240.4.0/24"
}

variable "api_server_subnet_name" {
  description = "API server VNet integration subnet name."
  type        = string
  default     = "snet-apiserver"
}

variable "api_server_subnet_prefix" {
  description = "API server subnet CIDR (must be >= /28)."
  type        = string
  default     = "10.240.5.0/28"
}

variable "aks_nsg_name" {
  description = "NSG name for the AKS subnet. Empty = nsg-<aks_subnet_name>."
  type        = string
  default     = ""
}

variable "byo_vnet_subnet_id" {
  description = "BYO VNet subnet ID (skip VNet module)."
  type        = string
  default     = ""
}

variable "byo_pod_subnet_id" {
  description = "BYO pod subnet ID (optional)."
  type        = string
  default     = ""
}

variable "private_dns_zone_name" {
  description = "Private DNS zone name. Empty = privatelink.<region>.azmk8s.io."
  type        = string
  default     = ""
}

variable "byo_private_dns_zone_id" {
  description = "BYO private DNS zone resource ID. Empty = create."
  type        = string
  default     = ""
}

variable "private_dns_vnet_link_name" {
  description = "VNet link name for the private DNS zone."
  type        = string
  default     = "vnet-link"
}

# ---------- Hub connectivity ----------
variable "hub_connectivity_mode" {
  description = "Hub model: none | peering | privateEndpoint | both."
  type        = string
  default     = "none"
  validation {
    condition     = contains(["none", "peering", "privateEndpoint", "both"], var.hub_connectivity_mode)
    error_message = "hub_connectivity_mode must be none, peering, privateEndpoint, or both."
  }
}

variable "byo_hub_vnet_id" {
  description = "BYO hub VNet ID. Empty = create hub VNet."
  type        = string
  default     = ""
}

variable "hub_vnet_name" {
  description = "New hub VNet name."
  type        = string
  default     = ""
}

variable "hub_address_prefixes" {
  description = "Hub VNet address prefixes."
  type        = list(string)
  default     = ["10.250.0.0/16"]
}

variable "hub_bastion_subnet_prefix" {
  description = "AzureBastionSubnet CIDR (>= /26)."
  type        = string
  default     = "10.250.1.0/26"
}

variable "hub_jumpbox_subnet_name" {
  description = "Jumpbox subnet name in the hub VNet."
  type        = string
  default     = "snet-jumpbox"
}

variable "hub_jumpbox_subnet_prefix" {
  description = "Jumpbox subnet CIDR."
  type        = string
  default     = "10.250.2.0/27"
}

variable "byo_hub_bastion_subnet_id" {
  description = "BYO hub Bastion subnet ID."
  type        = string
  default     = ""
}

variable "byo_hub_jumpbox_subnet_id" {
  description = "BYO hub jumpbox subnet ID."
  type        = string
  default     = ""
}

variable "byo_hub_pe_subnet_id" {
  description = "BYO hub PE subnet ID."
  type        = string
  default     = ""
}

variable "deploy_bastion" {
  description = "Deploy Azure Bastion in the hub."
  type        = bool
  default     = false
}

variable "bastion_sku" {
  description = "Azure Bastion SKU."
  type        = string
  default     = "Standard"
  validation {
    condition     = contains(["Basic", "Standard", "Developer"], var.bastion_sku)
    error_message = "bastion_sku must be Basic, Standard, or Developer."
  }
}

variable "bastion_name" {
  description = "Bastion host name. Empty = bas-<env_name>."
  type        = string
  default     = ""
}

variable "deploy_jumpbox" {
  description = "Deploy a Linux jumpbox VM."
  type        = bool
  default     = false
}

variable "jumpbox_vm_name" {
  description = "Jumpbox VM name. Empty = vm-<env_name>-jb."
  type        = string
  default     = ""
}

variable "jumpbox_vm_size" {
  description = "Jumpbox VM size."
  type        = string
  default     = "Standard_B2s"
}

variable "jumpbox_admin_username" {
  description = "Jumpbox admin username."
  type        = string
  default     = "azureuser"
}

variable "jumpbox_ssh_public_key" {
  description = "Jumpbox SSH public key (OpenSSH format). Required when deploy_jumpbox = true."
  type        = string
  default     = ""
  sensitive   = true
}

# ---------- AKS cluster knobs ----------
variable "kubernetes_version" {
  description = "Kubernetes version. Empty = AKS default."
  type        = string
  default     = ""
}

variable "support_plan" {
  description = "AKS support plan."
  type        = string
  default     = "KubernetesOfficial"
  validation {
    condition     = contains(["KubernetesOfficial", "AKSLongTermSupport"], var.support_plan)
    error_message = "support_plan must be KubernetesOfficial or AKSLongTermSupport."
  }
}

variable "node_resource_group_restriction_level" {
  description = "Node resource group restriction level."
  type        = string
  default     = "ReadOnly"
  validation {
    condition     = contains(["Unrestricted", "ReadOnly"], var.node_resource_group_restriction_level)
    error_message = "Must be Unrestricted or ReadOnly."
  }
}

variable "fqdn_subdomain" {
  description = "Optional FQDN subdomain for private cluster."
  type        = string
  default     = ""
}

variable "disable_private_cluster_public_fqdn" {
  description = "Disable public FQDN for private cluster."
  type        = bool
  default     = true
}

variable "api_server_authorized_ip_ranges" {
  description = "Authorized IP ranges for public API server."
  type        = list(string)
  default     = []
}

variable "tenant_id" {
  description = "Tenant ID. Empty = current subscription tenant."
  type        = string
  default     = ""
}

variable "cluster_admin_group_object_ids" {
  description = "Entra group object IDs granted cluster-admin."
  type        = list(string)
  default     = []
}

variable "disable_local_accounts" {
  description = "Disable local Kubernetes accounts."
  type        = bool
  default     = true
}

variable "enable_azure_rbac" {
  description = "Enable Azure RBAC for Kubernetes authorization."
  type        = bool
  default     = true
}

variable "enable_workload_identity" {
  description = "Enable workload identity."
  type        = bool
  default     = true
}

variable "enable_oidc_issuer" {
  description = "Enable OIDC issuer."
  type        = bool
  default     = true
}

variable "enable_image_cleaner" {
  description = "Enable image cleaner."
  type        = bool
  default     = true
}

variable "image_cleaner_interval_hours" {
  description = "Image cleaner interval in hours."
  type        = number
  default     = 168
}

variable "enable_keyvault_secrets_provider" {
  description = "Enable Key Vault secrets provider."
  type        = bool
  default     = true
}

variable "disable_run_command" {
  description = "Disable run command."
  type        = bool
  default     = false
}

variable "enable_defender" {
  description = "Enable Defender for Containers."
  type        = bool
  default     = false
}

variable "enable_azure_policy" {
  description = "Enable Azure Policy add-on."
  type        = bool
  default     = true
}

variable "disk_encryption_set_id" {
  description = "Disk encryption set resource ID (BYOK). Empty = platform-managed."
  type        = string
  default     = ""
}

variable "enable_cost_analysis" {
  description = "Enable cost analysis."
  type        = bool
  default     = true
}

variable "enable_app_routing" {
  description = "Enable managed NGINX application routing."
  type        = bool
  default     = true
}

variable "app_routing_dns_zone_ids" {
  description = "Public DNS zone IDs for app routing."
  type        = list(string)
  default     = []
}

variable "enable_istio" {
  description = "Enable Istio service mesh."
  type        = bool
  default     = false
}

variable "istio_revisions" {
  description = "Istio control-plane revisions."
  type        = list(string)
  default     = []
}

variable "enable_ai_toolchain_operator" {
  description = "Enable AI Toolchain Operator (KAITO)."
  type        = bool
  default     = false
}

variable "enable_keda" {
  description = "Enable KEDA."
  type        = bool
  default     = true
}

variable "enable_vpa" {
  description = "Enable Vertical Pod Autoscaler."
  type        = bool
  default     = true
}

variable "enable_disk_csi" {
  description = "Enable Disk CSI driver."
  type        = bool
  default     = true
}

variable "enable_file_csi" {
  description = "Enable File CSI driver."
  type        = bool
  default     = true
}

variable "enable_blob_csi" {
  description = "Enable Blob CSI driver."
  type        = bool
  default     = false
}

variable "enable_snapshot_controller" {
  description = "Enable snapshot controller."
  type        = bool
  default     = true
}

variable "network_plugin" {
  description = "Network plugin."
  type        = string
  default     = "azure"
}

variable "network_plugin_mode" {
  description = "Network plugin mode."
  type        = string
  default     = "overlay"
}

variable "network_dataplane" {
  description = "Network dataplane."
  type        = string
  default     = "cilium"
}

variable "network_policy" {
  description = "Network policy."
  type        = string
  default     = "cilium"
}

variable "pod_cidr" {
  description = "Pod CIDR."
  type        = string
  default     = "10.244.0.0/16"
}

variable "service_cidr" {
  description = "Service CIDR."
  type        = string
  default     = "10.0.0.0/16"
}

variable "dns_service_ip" {
  description = "DNS service IP."
  type        = string
  default     = "10.0.0.10"
}

variable "outbound_type" {
  description = "Outbound type."
  type        = string
  default     = "managedNATGateway"
}

variable "load_balancer_sku" {
  description = "Load balancer SKU."
  type        = string
  default     = "standard"
}

variable "system_pool_vm_size" {
  description = "System pool VM size."
  type        = string
  default     = "Standard_D4ds_v5"
}

variable "system_pool_node_count" {
  description = "System pool initial node count."
  type        = number
  default     = 3
}

variable "system_pool_os_sku" {
  description = "System pool OS SKU."
  type        = string
  default     = "AzureLinux"
}

variable "system_pool_zones" {
  description = "System pool availability zones."
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "auto_upgrade_channel" {
  description = "Cluster auto-upgrade channel."
  type        = string
  default     = "stable"
}

variable "node_os_upgrade_channel" {
  description = "Node OS upgrade channel."
  type        = string
  default     = "NodeImage"
}
