variable "name_prefix" {
  description = "Prefix used for all resource names. Override per client."
  type        = string
  default     = "estabilis"
}

variable "environment" {
  description = "Deployment environment identifier."
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "uat", "hml", "stg", "prd", "prod"], var.environment)
    error_message = "Environment must be one of: dev, uat, hml, stg, prd, prod."
  }
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "eastus2"
}

variable "domain" {
  description = "Domain name for the workload cluster. Leave empty if workload shares the platform domain."
  type        = string
  default     = ""
}

variable "tenant_id" {
  description = "Azure AD tenant ID."
  type        = string
  sensitive   = true
}

variable "subscription_id" {
  description = "Azure subscription ID."
  type        = string
  sensitive   = true
}

# ---------------------------------------------------------------------------
# AKS – Cluster
# ---------------------------------------------------------------------------

variable "kubernetes_version" {
  description = "Kubernetes version for the AKS cluster."
  type        = string
  default     = "1.34"
}

variable "auto_upgrade_channel" {
  description = "AKS auto-upgrade channel. Use 'patch' for production, 'none' for manual control."
  type        = string
  default     = "patch"
}

variable "sku_tier" {
  description = "AKS SKU tier. 'Standard' for production SLA (99.95%), 'Free' for dev/test."
  type        = string
  default     = "Free"
}

# ---------------------------------------------------------------------------
# AKS – System node pool
# ---------------------------------------------------------------------------

variable "system_vm_size" {
  description = "VM size for the system node pool. B2s (4GB) is sufficient when only_critical_addons_enabled = true."
  type        = string
  default     = "Standard_B2s"
}

variable "only_critical_addons_enabled" {
  description = "Taint system pool with CriticalAddonsOnly. Only AKS system components can run on it. Requires a workload pool for other pods."
  type        = bool
  default     = true
}

variable "system_node_count" {
  description = "Number of nodes in the system node pool."
  type        = number
  default     = 3
}

variable "system_auto_scaling_enabled" {
  description = "Enable cluster autoscaler on the system node pool."
  type        = bool
  default     = false
}

variable "system_min_count" {
  description = "Minimum nodes in the system pool when autoscaling is enabled."
  type        = number
  default     = 2
}

variable "system_max_count" {
  description = "Maximum nodes in the system pool when autoscaling is enabled."
  type        = number
  default     = 4
}

variable "system_os_disk_size_gb" {
  description = "OS disk size (GB) for system nodes. Must fit VM cache disk for ephemeral OS (B2s=30GB, D2s_v3=50GB)."
  type        = number
  default     = 30
}

# ---------------------------------------------------------------------------
# AKS – Workload node pools
# ---------------------------------------------------------------------------

variable "workload_regular_enabled" {
  description = "Enable the regular workload node pool. Required when only_critical_addons_enabled = true."
  type        = bool
  default     = false
}

variable "workload_spot_enabled" {
  description = "Enable the spot workload node pool."
  type        = bool
  default     = false
}

variable "workload_vm_size" {
  description = "VM size for the workload node pool."
  type        = string
  default     = "Standard_D2s_v3"
}

variable "workload_os_disk_size_gb" {
  description = "OS disk size (GB) for workload nodes. Align to Azure managed disk tiers to avoid overpaying: 32 (P4 ~$1.54/mo), 64 (P6 ~$2.85/mo), 128 (P10 ~$3.80/mo), 256 (P15 ~$7.26/mo)."
  type        = number
  default     = 64
}

variable "workload_spot_max_count" {
  description = "Maximum nodes in the Spot workload pool."
  type        = number
  default     = 3
}

variable "workload_regular_max_count" {
  description = "Maximum nodes in the Regular workload pool."
  type        = number
  default     = 2
}

# ---------------------------------------------------------------------------
# AKS – Network
# ---------------------------------------------------------------------------

variable "vnet_address_space" {
  description = "Address space for the virtual network."
  type        = string
  default     = "10.1.0.0/16"
}

variable "subnet_nodes_prefix" {
  description = "Address prefix for the AKS nodes subnet."
  type        = string
  default     = "10.1.0.0/22"
}

variable "subnet_pods_prefix" {
  description = "Address prefix for the AKS pods subnet."
  type        = string
  default     = "10.1.4.0/22"
}

variable "service_cidr" {
  description = "CIDR for Kubernetes services."
  type        = string
  default     = "172.17.0.0/16"
}

variable "dns_service_ip" {
  description = "IP address for Kubernetes DNS service."
  type        = string
  default     = "172.17.0.10"
}

variable "pod_cidr" {
  description = "CIDR for Kubernetes pods (overlay)."
  type        = string
  default     = "10.245.0.0/16"
}

variable "system_os_disk_type" {
  description = "OS disk type for system node pool. Ephemeral uses VM local SSD (faster, no cost, limited by cache size)."
  type        = string
  default     = "Ephemeral"
}

variable "system_availability_zones" {
  description = "Availability zones for the system node pool."
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "system_max_surge" {
  description = "Max surge for system node pool upgrades (percentage or absolute number)."
  type        = string
  default     = "10%"
}

variable "workload_os_disk_type" {
  description = "OS disk type for workload node pools. Managed allows larger disks (128GB default). Ephemeral is limited by VM cache."
  type        = string
  default     = "Managed"
}

variable "workload_availability_zones" {
  description = "Availability zones for workload node pools."
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "workload_max_surge" {
  description = "Max surge for workload regular node pool upgrades (percentage or absolute number)."
  type        = string
  default     = "10%"
}

variable "workload_drain_timeout_in_minutes" {
  description = "Timeout for draining workload nodes during upgrades. 0 = no timeout."
  type        = number
  default     = 0
}

variable "workload_node_soak_duration_in_minutes" {
  description = "Duration to wait after draining a workload node before upgrading the next. 0 = no wait."
  type        = number
  default     = 0
}

variable "aad_managed_enabled" {
  description = "Enable Azure AD managed integration for AKS authentication."
  type        = bool
  default     = true
}

variable "azure_rbac_enabled" {
  description = "Enable Azure RBAC for Kubernetes authorization. Requires aad_managed_enabled."
  type        = bool
  default     = true
}

variable "local_account_disabled" {
  description = "Disable local accounts (certificate-based access). Requires aad_managed_enabled and aad_admin_group_ids configured."
  type        = bool
  default     = false
}

variable "aad_admin_group_ids" {
  description = "List of Azure AD group object IDs that receive cluster-admin role. Required when local_account_disabled = true."
  type        = list(string)
  default     = []

  validation {
    condition     = !var.local_account_disabled || length(var.aad_admin_group_ids) > 0
    error_message = "Cannot disable local accounts without configuring aad_admin_group_ids. Add at least one AAD group before setting local_account_disabled = true."
  }
}

variable "aks_role_assignments" {
  description = "List of Azure RBAC role assignments on the AKS cluster. Each entry needs principal_id and role name."
  type = list(object({
    principal_id = string
    role         = string
  }))
  default = []
}

variable "network_dataplane" {
  description = "Network dataplane for AKS. Options: default (Azure), cilium (managed, no Hubble), cilium-acns (managed + Hubble/FQDN, ~$70/mo), byo-cni (self-managed Cilium + Hubble, DESTROYS AND RECREATES CLUSTER)."
  type        = string
  default     = "default"

  validation {
    condition     = contains(["default", "cilium", "cilium-acns", "byo-cni"], var.network_dataplane)
    error_message = "Network dataplane must be one of: default, cilium, cilium-acns, byo-cni."
  }
}

variable "byo_cni_i_understand_this_destroys_the_cluster" {
  description = "Safety flag: byo-cni can only be used on initial cluster creation. Switching an existing cluster to byo-cni DESTROYS and RECREATES it. Set to true only if creating a new cluster or you accept full cluster destruction."
  type        = bool
  default     = false

  validation {
    condition     = var.network_dataplane != "byo-cni" || var.byo_cni_i_understand_this_destroys_the_cluster
    error_message = "byo-cni DESTROYS and RECREATES the cluster. This should only be used on initial creation. If you understand the risk, set byo_cni_i_understand_this_destroys_the_cluster = true."
  }
}

variable "cilium_version" {
  description = "Cilium Helm chart version for byo-cni mode. Ignored for managed dataplanes."
  type        = string
  default     = "1.19.2"
}

variable "run_command_enabled" {
  description = "Enable Azure run command on AKS. Disable to reduce attack surface."
  type        = bool
  default     = false
}

variable "image_cleaner_enabled" {
  description = "Enable automatic image cleaner on AKS nodes to remove unused images."
  type        = bool
  default     = true
}

variable "image_cleaner_interval_hours" {
  description = "Interval in hours for the image cleaner scan."
  type        = number
  default     = 48
}

variable "spot_max_price" {
  description = "Max price per hour for Spot node pool. -1 = market price (no limit)."
  type        = number
  default     = -1
}

variable "maintenance_window_day" {
  description = "Day of week for AKS planned maintenance window."
  type        = string
  default     = "Saturday"
}

variable "maintenance_window_start_hour" {
  description = "Start hour (UTC) for AKS planned maintenance window."
  type        = number
  default     = 2
}

variable "maintenance_window_duration" {
  description = "Duration in hours for AKS planned maintenance window."
  type        = number
  default     = 4
}

variable "azure_monitor_enabled" {
  description = "Enable Azure Monitor Agent on AKS nodes."
  type        = bool
  default     = false
}

variable "nat_gateway_enabled" {
  description = "Enable NAT Gateway for controlled outbound traffic with static IP."
  type        = bool
  default     = true
}

variable "nsg_enabled" {
  description = "Enable Network Security Group on AKS node subnet."
  type        = bool
  default     = true
}

variable "nat_gateway_idle_timeout" {
  description = "Idle timeout in minutes for NAT Gateway. Increase for long-lived connections (WebSocket, streaming). Max 120."
  type        = number
  default     = 4
}

variable "authorized_ip_ranges" {
  description = "List of authorized IP ranges for AKS API server access."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Resource Firewall (centralized network access control)
# ---------------------------------------------------------------------------

variable "firewall_enabled" {
  description = "Enable network firewall on all resources (Key Vault, Storage, ACR). When false, all resources are publicly accessible (authenticated only)."
  type        = bool
  default     = true
}

variable "firewall_allowed_ips" {
  description = "IP ranges allowed on ALL firewalled resources (VPN, CI/CD, office IPs). Operator IP and NAT Gateway IP are always included automatically."
  type        = list(string)
  default     = []
}

variable "firewall_allowed_subnet_ids" {
  description = "Subnet IDs allowed on ALL firewalled resources. AKS node subnet is always included automatically."
  type        = list(string)
  default     = []
}

variable "keyvault_extra_allowed_ips" {
  description = "Additional IP ranges allowed on Key Vault only (on top of global firewall rules)."
  type        = list(string)
  default     = []
}

variable "storage_tfstate_extra_allowed_ips" {
  description = "Additional IP ranges allowed on tfstate storage only (on top of global firewall rules)."
  type        = list(string)
  default     = []
}

variable "storage_velero_extra_allowed_ips" {
  description = "Additional IP ranges allowed on Velero storage only (on top of global firewall rules)."
  type        = list(string)
  default     = []
}

variable "acr_extra_allowed_ips" {
  description = "Additional IP ranges allowed on ACR only (on top of global firewall rules). Requires Premium SKU."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Key Vault
# ---------------------------------------------------------------------------

variable "keyvault_enabled" {
  description = "Enable Key Vault for workload secrets. Disable if workload has no secrets."
  type        = bool
  default     = true
}

variable "keyvault_soft_delete_days" {
  description = "Retention days for Key Vault soft delete."
  type        = number
  default     = 7
}

variable "keyvault_purge_protection" {
  description = "Enable purge protection on Key Vault. Disable for dev/test."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Storage
# ---------------------------------------------------------------------------

variable "storage_replication_type" {
  description = "Default replication type for storage accounts."
  type        = string
  default     = "ZRS"
}

variable "storage_replication_type_tfstate" {
  description = "Replication type for Terraform state storage. Empty uses default."
  type        = string
  default     = ""
}

variable "storage_replication_type_velero" {
  description = "Replication type for Velero backup storage. Empty uses default."
  type        = string
  default     = ""
}

variable "storage_replication_type_cost_exports" {
  description = "Replication type for cost exports storage. Empty uses default."
  type        = string
  default     = ""
}

variable "storage_soft_delete_enabled" {
  description = "Enable blob and container soft delete on all storage accounts."
  type        = bool
  default     = true
}

variable "storage_soft_delete_retention_days" {
  description = "Retention days for blob and container soft delete."
  type        = number
  default     = 14
}

variable "storage_protect_critical" {
  description = "Apply Azure resource locks on critical storage accounts."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# ACR (Azure Container Registry)
# ---------------------------------------------------------------------------

variable "acr_enabled" {
  description = "Enable Azure Container Registry for private images and/or proxy cache."
  type        = bool
  default     = false
}

variable "acr_sku" {
  description = "ACR SKU. Basic (~$5/mo), Standard (~$10/mo), Premium (~$50/mo, supports private endpoint + geo-replication)."
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.acr_sku)
    error_message = "ACR SKU must be one of: Basic, Standard, Premium."
  }
}

variable "acr_aks_attach_enabled" {
  description = "Attach ACR to AKS with AcrPull role. Disable if using external ACR or CI-only registry."
  type        = bool
  default     = true
}

variable "acr_cache_enabled" {
  description = "Enable cache rules for public registries (Docker Hub, GHCR, Quay, etc.). Requires acr_enabled."
  type        = bool
  default     = true
}

variable "acr_cache_dockerhub_enabled" {
  description = "Enable Docker Hub cache rule. Requires acr_dockerhub_username and acr_dockerhub_token."
  type        = bool
  default     = false
}

variable "acr_dockerhub_username" {
  description = "Docker Hub username for authenticated cache pulls. Required when acr_cache_dockerhub_enabled = true."
  type        = string
  default     = ""
  sensitive   = true
}

variable "acr_dockerhub_token" {
  description = "Docker Hub Personal Access Token for authenticated cache pulls. Required when acr_cache_dockerhub_enabled = true."
  type        = string
  default     = ""
  sensitive   = true
}

variable "acr_firewall_enabled" {
  description = "Enable network firewall on ACR (Deny all + allow operator IP and AKS). Requires Premium SKU."
  type        = bool
  default     = true
}

variable "acr_content_trust_enabled" {
  description = "Enable content trust (image signing verification). Requires Premium SKU."
  type        = bool
  default     = false
}

variable "acr_retention_days" {
  description = "Days to retain untagged manifests. 0 = disabled. Requires Premium SKU."
  type        = number
  default     = 30
}

variable "acr_private_endpoint_enabled" {
  description = "Enable private endpoint for ACR (no public access). Requires Premium SKU."
  type        = bool
  default     = false
}

# NOTE: acr_domain_name_label_scope — exists in Azure API but not yet supported
# by the azurerm Terraform provider. Add when provider v5.x implements it.

variable "acr_georeplications" {
  description = "List of Azure regions for geo-replication. Requires Premium SKU."
  type        = list(string)
  default     = []
}

variable "acr_push_principal_ids" {
  description = "List of Azure AD principal IDs (users, groups, service principals) to grant AcrPush."
  type        = list(string)
  default     = []
}

variable "acr_ci_identity_enabled" {
  description = "Create a dedicated managed identity for CI/CD push to ACR. Outputs client_id for federated credential setup."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Velero
# ---------------------------------------------------------------------------

variable "velero_enabled" {
  description = "Enable Velero backup storage and managed identity."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Cost Export
# ---------------------------------------------------------------------------

variable "cost_export_enabled" {
  description = "Enable Azure Cost Management export. Disable if workload is in the same subscription as the platform."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Diagnostics
# ---------------------------------------------------------------------------

variable "diagnostics_enabled" {
  description = "Enable AKS diagnostic settings (Log Analytics + audit logs)."
  type        = bool
  default     = true
}

variable "log_analytics_retention_days" {
  description = "Retention days for Log Analytics Workspace."
  type        = number
  default     = 30
}

# ---------------------------------------------------------------------------
# Tags (Azure CAF recommended)
# ---------------------------------------------------------------------------

# --- Functional ---

variable "tag_app" {
  description = "CAF Functional: application name. Defaults to name_prefix if empty."
  type        = string
  default     = ""
}

variable "tag_tier" {
  description = "CAF Functional: application tier (infrastructure, platform, application)."
  type        = string
  default     = "infrastructure"

  validation {
    condition     = var.tag_tier == "" || contains(["infrastructure", "platform", "application", "database", "web", "api"], var.tag_tier)
    error_message = "Tier must be one of: infrastructure, platform, application, database, web, api (or empty to omit)."
  }
}

# --- Classification ---

variable "tag_criticality" {
  description = "CAF Classification: criticality level."
  type        = string
  default     = ""

  validation {
    condition     = var.tag_criticality == "" || contains(["mission-critical", "high", "medium", "low"], var.tag_criticality)
    error_message = "Criticality must be one of: mission-critical, high, medium, low (or empty to omit)."
  }
}

variable "tag_confidentiality" {
  description = "CAF Classification: data confidentiality level."
  type        = string
  default     = ""

  validation {
    condition     = var.tag_confidentiality == "" || contains(["public", "internal", "confidential", "restricted"], var.tag_confidentiality)
    error_message = "Confidentiality must be one of: public, internal, confidential, restricted (or empty to omit)."
  }
}

variable "tag_sla" {
  description = "CAF Classification: expected SLA (e.g., 99.9, 99.95, 99.99)."
  type        = string
  default     = ""
}

# --- Accounting ---

variable "tag_costcenter" {
  description = "CAF Accounting: cost center for billing attribution."
  type        = string
  default     = ""
}

variable "tag_department" {
  description = "CAF Accounting: department responsible for the cost."
  type        = string
  default     = ""
}

variable "tag_budget" {
  description = "CAF Accounting: budget associated with the workload."
  type        = string
  default     = ""
}

# --- Purpose ---

variable "tag_businessprocess" {
  description = "CAF Purpose: business process this workload supports."
  type        = string
  default     = ""
}

variable "tag_businessimpact" {
  description = "CAF Purpose: impact if this workload is unavailable."
  type        = string
  default     = ""

  validation {
    condition     = var.tag_businessimpact == "" || contains(["critical", "high", "moderate", "low", "none"], var.tag_businessimpact)
    error_message = "Business impact must be one of: critical, high, moderate, low, none (or empty to omit)."
  }
}

variable "tag_revenueimpact" {
  description = "CAF Purpose: revenue impact if this workload is unavailable."
  type        = string
  default     = ""

  validation {
    condition     = var.tag_revenueimpact == "" || contains(["high", "moderate", "low", "none"], var.tag_revenueimpact)
    error_message = "Revenue impact must be one of: high, moderate, low, none (or empty to omit)."
  }
}

# --- Ownership ---

variable "tag_opsteam" {
  description = "CAF Ownership: operations team responsible for this workload."
  type        = string
  default     = ""
}

variable "tag_businessunit" {
  description = "CAF Ownership: business unit that owns this workload."
  type        = string
  default     = ""
}

# --- Extra ---

variable "extra_tags" {
  description = "Additional tags to merge with the CAF set."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Hub Key Vault (cross-deployment secret sharing)
# ---------------------------------------------------------------------------
# When set, the workload module reads hub connection values (API server URL,
# CA certificate, registrar token, egress IP) from a shared Key Vault created
# by the platform Terraform (see estabilis-platform shared.tf). This eliminates
# the need to manually copy values from terraform output + kubectl into tfvars.
#
# Convention:
#   hub_key_vault_name = "kv-{prefix}-hub-{env}-{suffix}"
#   hub_key_vault_rg   = "rg-{prefix}-platform-hub-{region}"

variable "hub_key_vault_name" {
  description = "Name of the Key Vault in the shared RG containing hub connection values. When set, hub_api_server_url/hub_ca_certificate/hub_registrar_token/hub_egress_ip are read from the KV and the manual variables become fallbacks."
  type        = string
  default     = ""
}

variable "hub_key_vault_rg" {
  description = "Resource group containing the hub Key Vault. Convention: rg-{prefix}-platform-hub-{region}."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Hub registration — Workload Operator
# ---------------------------------------------------------------------------

variable "hub_registration_enabled" {
  description = "Enable automatic registration of this workload cluster in the platform hub via WorkloadCluster CRD. When true, requires hub_api_server_url, hub_registrar_token and hub_egress_ip."
  type        = bool
  default     = false
}

variable "hub_api_server_url" {
  description = "API server URL of the platform hub AKS cluster. Get from: terraform output -raw hub_api_server_url (estabilis-platform)."
  type        = string
  default     = ""
}

variable "hub_registrar_token" {
  description = "Bearer token of the workload-registrar ServiceAccount on the hub. Get from: kubectl get secret workload-registrar-token -n estabilis-system -o jsonpath='{.data.token}' | base64 -d"
  type        = string
  default     = ""
  sensitive   = true
}

variable "hub_ca_certificate" {
  description = "Base64-encoded CA certificate of the platform hub AKS cluster. Required when hub_registration_enabled = true so the kubernetes.hub provider can verify TLS. Get from: kubectl --context <hub> config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}'"
  type        = string
  default     = ""
}

variable "hub_egress_ip" {
  description = "Static outbound IP of the platform hub NAT Gateway. Get from: terraform output -raw nat_gateway_public_ip (estabilis-platform). When hub_registration_enabled = true, this IP is automatically added to authorized_ip_ranges of this AKS API server — remove it from authorized_ip_ranges/firewall_allowed_ips to avoid duplication."
  type        = string
  default     = ""
}
