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
  description = "DNS zone root (e.g. estabilis.io). Must match the actual zone in Cloudflare or Azure DNS. Hostnames are derived as {app}.{cluster_name}.{domain}. Leave empty if workload has no DNS."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Ingress — ADR 0014 multi-exposure model
# ---------------------------------------------------------------------------

variable "traefik_enabled" {
  description = "Deploy Traefik ingress controller on the workload cluster (public — Azure LB with PIP). Required for any public exposure (hubble_ui_exposures, etc.) to work."
  type        = bool
  default     = false
}

variable "traefik_internal_enabled" {
  description = "Deploy a second Traefik ingress controller in internal mode (Azure Internal LoadBalancer, no PIP). Use when apps must be reached only via NVA/FortiGate DNAT or peered VNets. Parity with estabilis-platform. Can coexist with traefik_enabled (two ingress classes: 'traefik' + 'traefik-internal')."
  type        = bool
  default     = false
}

variable "traefik_internal_lb_ip" {
  description = <<-EOT
    Fixed private IP for the Traefik internal LoadBalancer (Azure ILB). The IP
    MUST belong to the AKS nodes subnet. Leave empty for Azure auto-assignment
    from the subnet (dynamic). Only meaningful when traefik_internal_enabled=true.

    Set this in the NVA/FortiGate topology (e.g. eastus2) where the FortiGate
    DNATs to a known ILB IP. Leave empty in the NAT-Gateway topology (e.g.
    brazilsouth) where a dynamic ILB IP is fine. Emitted as the bridge
    annotation estabilis.io/bridge.traefik-internal-lb-ip and consumed per-cluster
    by the workload-bootstrap traefik-internal ApplicationSet.
  EOT
  type        = string
  default     = ""

  validation {
    condition     = var.traefik_internal_lb_ip == "" || can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$", var.traefik_internal_lb_ip))
    error_message = "traefik_internal_lb_ip must be empty or a valid IPv4 address within the AKS nodes subnet."
  }
}

variable "ingress_allowed_ip_ranges" {
  description = "IP ranges allowed inbound on ports 80/443 (NSG L4 filtering). Empty means public. Per-app L7 filtering is in each exposure's allowed_cidrs."
  type        = list(string)
  default     = []
}

variable "hubble_ui_exposures" {
  description = "Hubble UI ingress exposures (ADR 0014). Requires traefik_enabled=true and network_dataplane=cilium-acns."
  type = map(object({
    enabled       = bool
    host          = optional(string, "")
    ingress_class = optional(string, "traefik")
    allowed_cidrs = optional(string, "")
    issuer        = optional(string, "letsencrypt-production")
    basic_auth    = optional(bool, false)
  }))
  default = {}
}


variable "dns_provider" {
  description = "DNS backend: azure (creates Azure DNS Zone + Workload Identity) or cloudflare (uses external Cloudflare zone + API token stored in workload Key Vault). Only applies when domain is set."
  type        = string
  default     = "azure"

  validation {
    condition     = contains(["azure", "cloudflare"], var.dns_provider)
    error_message = "dns_provider must be azure or cloudflare."
  }
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID. Required when dns_provider=cloudflare and domain is set."
  type        = string
  default     = ""

  validation {
    condition     = var.dns_provider != "cloudflare" || var.domain == "" || length(var.cloudflare_zone_id) > 0
    error_message = "cloudflare_zone_id is required when dns_provider=cloudflare and domain is set."
  }
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with Zone:Read + DNS:Edit permissions. Required when dns_provider=cloudflare and domain is set. Stored in the workload Key Vault, read by ExternalSecrets at runtime."
  type        = string
  default     = ""
  sensitive   = true

  validation {
    condition     = var.dns_provider != "cloudflare" || var.domain == "" || length(var.cloudflare_api_token) > 0
    error_message = "cloudflare_api_token is required when dns_provider=cloudflare and domain is set."
  }
}

variable "letsencrypt_email" {
  description = "Email for Let's Encrypt certificate registration. Required when domain is set."
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
  description = "Kubernetes version for the AKS cluster. v3.0.0: default bumped from 1.34 → 1.35 (aligns with platform recommended). Consumers pinning explicitly are unaffected."
  type        = string
  default     = "1.35"
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
  description = "Network dataplane for AKS. Options: default (Azure), cilium (managed, no Hubble), cilium-acns (managed + Hubble/FQDN, ~$70/mo), byo-cni (self-managed Cilium + Hubble, DESTROYS AND RECREATES CLUSTER). v3.0.0 BREAKING: default changed from 'default' to 'cilium-acns'. Set explicitly to 'default' to preserve legacy behavior."
  type        = string
  default     = "cilium-acns"

  validation {
    condition     = contains(["default", "cilium", "cilium-acns", "byo-cni"], var.network_dataplane)
    error_message = "Network dataplane must be one of: default, cilium, cilium-acns, byo-cni."
  }
}

variable "network_plugin_mode" {
  description = "Azure CNI plugin mode. Options: 'overlay' (default — pods from pod_cidr, single nodes subnet), 'pod-subnet' (Azure CNI Pod Subnet — pods from dedicated pod_subnet_id, GA flat networking per Microsoft Learn 2026-05-13), null (BYO CNI — automatic when network_dataplane='byo-cni'). v3.0.0: default 'overlay' preserves backward compat."
  type        = string
  default     = "overlay"

  validation {
    condition     = var.network_plugin_mode == null || contains(["overlay", "pod-subnet"], var.network_plugin_mode)
    error_message = "network_plugin_mode must be 'overlay', 'pod-subnet', or null."
  }
}

variable "acns_observability_enabled" {
  description = "Enable Advanced Container Networking Services (ACNS) observability (Hubble flow logs + metrics). Only applies when network_dataplane=cilium-acns. Disabling reduces visibility but saves ~30% of ACNS cost."
  type        = bool
  default     = true
}

variable "acns_security_enabled" {
  description = "Enable Advanced Container Networking Services (ACNS) security (FQDN filtering via Cilium NetworkPolicies). Only applies when network_dataplane=cilium-acns. Disabling removes FQDN-based egress control."
  type        = bool
  default     = true
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

variable "hub_cluster_name" {
  description = "Name of the platform hub AKS cluster (e.g. aks-<prefix>-platform-<env>-<region>). Used to derive observability push URLs (Alloy → Loki/Mimir: {app}.{hub_cluster_name}.{telemetry_domain}). When empty and KV integration is on, it is read from the hub Key Vault secret 'hub-cluster-name' (published by estabilis-platform shared.tf); set this only to override. Manual fetch: terraform output -raw aks_cluster_name (estabilis-platform)."
  type        = string
  default     = ""
}

variable "telemetry_use_internal" {
  description = "When true (default), the workload's Alloy pushes logs/metrics to the hub over the INTERNAL split-horizon domain (internal_domain, e.g. mimir.<hub>.azure.<domain> via Private DNS + VNet peering) — traffic stays on the private network. When false, it uses the public domain (mimir.<hub>.<domain>). Choose per environment/architecture. The resolved endpoint domain is emitted to the cluster bridge as 'hub-telemetry-domain' so the gitops alloy template stays logic-free. Internal requested but internal_domain empty → falls back to the public domain."
  type        = bool
  default     = true
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
  description = "Static outbound IP of the platform hub egress (NAT Gateway). Only used when the effective WorkloadCluster apiServerAccess mode is 'allowlist' (public API server). Get from: terraform output -raw nat_gateway_public_ip (estabilis-platform), or the hub Key Vault 'hub-egress-ip' secret. Leave empty for private/peered clusters."
  type        = string
  default     = ""
}

variable "hub_registration_api_server_access_mode" {
  description = <<-EOT
    Overrides the apiServerAccess.mode emitted on this cluster's WorkloadCluster
    CR (operator contract, estabilis-workload-operator >= v0.8.0).

      ""         (default) — auto: derived from enable_private_cluster
                  (private cluster => "private", public => "allowlist").
      "private"  — operator skips API-server allowlisting (private/peered).
      "allowlist"— operator allowlists hub_egress_ip on the public API server
                  (requires a non-empty resolved hub egress IP).
      "none"     — allowlisting managed outside the operator; it only registers.
  EOT
  type        = string
  default     = ""

  validation {
    condition     = contains(["", "private", "allowlist", "none"], var.hub_registration_api_server_access_mode)
    error_message = "hub_registration_api_server_access_mode must be one of \"\" (auto), private, allowlist, none."
  }
}

# ===========================================================================
# v3.0.0 — BYO Network (consume external VNet/subnet/NAT GW from another repo)
# ===========================================================================

variable "network_existing_enabled" {
  description = "When true, consume external VNet/subnet/NAT GW (no auto-create). Requires existing_vnet_id and existing_subnet_nodes_id."
  type        = bool
  default     = false
}

variable "existing_vnet_id" {
  description = "ARM ID of external VNet (when network_existing_enabled=true)."
  type        = string
  default     = ""
}

variable "existing_vnet_name" {
  description = "Name of external VNet (when network_existing_enabled=true)."
  type        = string
  default     = ""
}

variable "existing_vnet_resource_group_name" {
  description = "Resource group of external VNet (when network_existing_enabled=true)."
  type        = string
  default     = ""
}

variable "existing_subnet_nodes_id" {
  description = "ARM ID of external subnet for AKS nodes (when network_existing_enabled=true)."
  type        = string
  default     = ""
}

variable "existing_subnet_pods_id" {
  description = "ARM ID of external subnet for AKS pods (overlay mode → leave empty)."
  type        = string
  default     = ""
}

variable "external_nat_gateway_egress_ips" {
  description = "List of NAT Gateway public IPs (from external network repo, no /32 suffix). Added to firewall_base_ips and api_server authorized_ip_ranges when network_existing_enabled=true."
  type        = list(string)
  default     = []
}

variable "outbound_type" {
  description = "AKS outbound type. Options: userAssignedNATGateway (default — works with internal or external NAT GW), userDefinedRouting (requires UDR with 0.0.0.0/0 in subnet — only valid when network_existing_enabled=true), loadBalancer."
  type        = string
  default     = "userAssignedNATGateway"

  validation {
    condition     = contains(["userAssignedNATGateway", "userDefinedRouting", "loadBalancer"], var.outbound_type)
    error_message = "outbound_type must be one of: userAssignedNATGateway, userDefinedRouting, loadBalancer."
  }
}

# ===========================================================================
# v3.0.0 — Naming (workload_domain replaces hardcoded "workload" in base_name)
# ===========================================================================

variable "workload_domain" {
  description = "Replaces 'workload' in resource naming pattern. Default 'workload' preserves backward compat. Override to e.g. 'crypto', 'payments' for multi-cluster-per-region setups."
  type        = string
  default     = "workload"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.workload_domain))
    error_message = "workload_domain must be lowercase alphanumeric with hyphens, starting with a letter."
  }
}

# ===========================================================================
# v3.0.0 — Private cluster + UAMI + external PDZ (parity with estabilis-platform)
# ===========================================================================

variable "enable_private_cluster" {
  description = "When true, AKS API server is private (PE-only access via PDZ). Requires private_dns_zone_id."
  type        = bool
  default     = false
}

variable "private_dns_zone_id" {
  description = "ARM ID of Private DNS Zone for AKS API server (e.g. privatelink.<region>.azmk8s.io). Required when enable_private_cluster=true. Use 'System' to let AKS manage the PDZ inside MC_ RG."
  type        = string
  default     = ""
}

variable "private_cluster_public_fqdn_enabled" {
  description = "When false, AKS does not expose public FQDN for the private cluster. Keep false for full lockdown."
  type        = bool
  default     = false
}

# ===========================================================================
# v3.0.0 — PE-only PaaS (granular: 4 vars, one per resource)
# ===========================================================================

variable "keyvault_private_endpoint_enabled" {
  description = "Enable Private Endpoint for the workload Key Vault. Disables public network access. Requires external_pdz_vaultcore_id."
  type        = bool
  default     = false
}

variable "tfstate_enabled" {
  description = "Create the module-managed Terraform state backend (resource group + storage account + container + deployer role assignment). Default true preserves the self-bootstrap pattern. Set false when the backend lives in an external, pre-provisioned storage account (e.g. a central bootstrap layer) — avoids an orphaned tfstate storage account per workload."
  type        = bool
  default     = true
}

variable "tfstate_private_endpoint_enabled" {
  description = "Enable Private Endpoint for the tfstate Storage Account. Requires external_pdz_blob_id and tfstate_enabled=true."
  type        = bool
  default     = false
}

variable "velero_private_endpoint_enabled" {
  description = "Enable Private Endpoint for the Velero backup Storage Account. Requires external_pdz_blob_id and velero_enabled=true."
  type        = bool
  default     = false
}

variable "cost_exports_private_endpoint_enabled" {
  description = "Enable Private Endpoint for the cost exports Storage Account. Requires external_pdz_blob_id and cost_export_enabled=true."
  type        = bool
  default     = false
}

variable "external_pdz_blob_id" {
  description = "ARM ID of canonical Private DNS Zone privatelink.blob.core.windows.net (from hub network repo). Required when any *storage*_private_endpoint_enabled=true."
  type        = string
  default     = ""
}

variable "external_pdz_vaultcore_id" {
  description = "ARM ID of canonical Private DNS Zone privatelink.vaultcore.azure.net (from hub network repo). Required when keyvault_private_endpoint_enabled=true."
  type        = string
  default     = ""
}

variable "external_pdz_acr_id" {
  description = "ARM ID of canonical Private DNS Zone privatelink.azurecr.io (from hub network repo). Required when acr_private_endpoint_enabled=true under network_existing_enabled mode."
  type        = string
  default     = ""
}

# ===========================================================================
# v3.0.0 — Cross-region observability + misc
# ===========================================================================

variable "external_log_analytics_workspace_id" {
  description = "ARM ID of an additional Log Analytics Workspace (e.g. central observability LAW). When set, an additional azurerm_monitor_diagnostic_setting is created pointing AKS audit logs to this LAW (does NOT replace the local LAW)."
  type        = string
  default     = ""
}

variable "workload_regular_min_count" {
  description = "Minimum nodes in the regular workload pool (when workload_regular_enabled=true). Default 0 keeps backward compat (parity with platform module)."
  type        = number
  default     = 0
}

variable "shared_hub_secrets_prefix" {
  description = "Optional prefix for hub KV secret names (e.g. 'env-stg'). Reserved for future use."
  type        = string
  default     = ""
}

# ===========================================================================
# v3.0.0 — Diagnostic categories (customizable)
# One log-categories var + one metric-categories var per resource-type, shared
# between local and external pairs. AKS gets two extra vars to preserve the
# legacy divergence (kube-apiserver only on external; metrics only on external).
# Defaults reproduce the previously-hardcoded category lists — zero diff in
# plan for existing consumers.
# ===========================================================================

# --- AKS ---

variable "aks_diagnostic_log_categories" {
  description = "Log categories enabled on the AKS diagnostic setting (both local and external LAW). Default mirrors Microsoft Learn AKS reference categories."
  type        = list(string)
  default     = ["kube-audit-admin", "kube-controller-manager", "kube-scheduler", "cluster-autoscaler", "guard"]
}

variable "aks_diagnostic_log_categories_external_extra" {
  description = "Extra log categories enabled ONLY on the external AKS diagnostic setting. Default adds kube-apiserver (heavyweight; goes only to central LAW for compliance audit, not flooded into local LAW)."
  type        = list(string)
  default     = ["kube-apiserver"]
}

variable "aks_diagnostic_metric_categories" {
  description = "Metric categories enabled on the AKS external diagnostic setting. Local pair currently emits no metrics by default — pass [] to keep, [\"AllMetrics\"] to add."
  type        = list(string)
  default     = ["AllMetrics"]
}

variable "aks_diagnostic_metric_categories_local" {
  description = "Metric categories on AKS LOCAL diagnostic setting. Default empty (parity with prior behavior)."
  type        = list(string)
  default     = []
}

# --- Key Vault ---

variable "keyvault_diagnostic_log_categories" {
  description = "Log categories on Key Vault diagnostic settings (both pairs)."
  type        = list(string)
  default     = ["AuditEvent", "AzurePolicyEvaluationDetails"]
}

variable "keyvault_diagnostic_metric_categories" {
  description = "Metric categories on Key Vault diagnostic settings (both pairs)."
  type        = list(string)
  default     = ["AllMetrics"]
}

# --- Storage Accounts (shared by tfstate + velero + cost; schema is homogeneous) ---

variable "storage_diagnostic_log_categories" {
  description = "Log categories on all Storage Account blob diagnostic settings (tfstate, velero, cost). Applies to both local and external pairs."
  type        = list(string)
  default     = ["StorageRead", "StorageWrite", "StorageDelete"]
}

variable "storage_diagnostic_metric_categories" {
  description = "Metric categories on all Storage Account blob diagnostic settings."
  type        = list(string)
  default     = ["Transaction"]
}

# --- ACR ---

variable "acr_diagnostic_log_categories" {
  description = "Log categories on ACR diagnostic settings (both pairs)."
  type        = list(string)
  default     = ["ContainerRegistryRepositoryEvents", "ContainerRegistryLoginEvents"]
}

variable "acr_diagnostic_metric_categories" {
  description = "Metric categories on ACR diagnostic settings (both pairs)."
  type        = list(string)
  default     = ["AllMetrics"]
}

# ===========================================================================
# v3.0.0 — Platform parity: split-horizon DNS + deployment identification
# ===========================================================================

variable "internal_domain" {
  description = "DNS zone root for INTERNAL hostnames (e.g. azure.estabilis-transfero.dev). When set, exposures with profile key='internal' derive hosts as {app}.{cluster_name}.{internal_domain} instead of {app}.{cluster_name}.{domain}. Enables split-horizon DNS: external exposures keep public domain (TLS via cert-manager Let's Encrypt) while internal exposures use private subdomain (no public TLS log leakage). Empty disables split-horizon (all exposures use var.domain)."
  type        = string
  default     = ""
}

variable "deployment_id" {
  description = "Unique identifier of this workload deployment (e.g. crypto-azure-brazilsouth-stg). Maps to workloads/{deployment_id}/ in the client GitOps repo. When set, bridge.cluster-name is composed as $${name_prefix}-$${deployment_id} (parity with platform). When empty, falls back to AKS resource name (legacy behavior — current default)."
  type        = string
  default     = ""
}

variable "internal_dns_zone_id" {
  description = "ARM ID of the hub-owned Azure Private DNS zone for INTERNAL hostnames (e.g. .../privateDnsZones/azure.estabilis-transfero.dev). When set together with internal_domain, the workload runs a second external-dns instance (provider=azure-private-dns) that publishes A records for internal exposures into this zone, replacing static wildcard records hand-maintained in the network repo. The zone may live in a different resource group / subscription (the hub's). Empty disables the internal external-dns."
  type        = string
  default     = ""
}

variable "external_dns_internal_enabled" {
  description = "Run the internal external-dns instance (provider=azure-private-dns) bound to internal_dns_zone_id. Effective only when internal_dns_zone_id AND internal_domain are both set. Default true: enabled wherever the internal zone is provided. The instance reads the Service's actual LoadBalancer IP, so it works for both fixed (FortiGate VIP) and dynamic (NAT-Gateway) internal ILBs."
  type        = bool
  default     = true
}

variable "node_resource_group" {
  description = "Override for the auto-generated AKS node resource group name. Azure default is MC_<rg-name>_<cluster-name>_<region> which can exceed the 80-char limit when both rg-name and cluster-name include long region names like brazilsouth. Set to a shorter explicit name when default exceeds the limit. Empty (default) lets Azure compose the default name."
  type        = string
  default     = ""

  validation {
    condition     = length(var.node_resource_group) <= 80
    error_message = "node_resource_group must be at most 80 characters (Azure limit)."
  }
}
