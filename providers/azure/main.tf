# ---------------------------------------------------------------------------
# Provider configuration
# ---------------------------------------------------------------------------

provider "azurerm" {
  features {}

  resource_provider_registrations = "none"
  storage_use_azuread             = true
  subscription_id                 = var.subscription_id
  tenant_id                       = var.tenant_id
}

provider "azuread" {
  tenant_id = var.tenant_id
}

# ---------------------------------------------------------------------------
# Resource Group
# ---------------------------------------------------------------------------

resource "azurerm_resource_group" "workload" {
  name     = "rg-${local.base_name}"
  location = var.location
  tags     = local.tags
}

# ---------------------------------------------------------------------------
# CAF Naming Convention
# Pattern: {resource-type}-{workload}-{environment}-{region}-{instance}
# Reference: https://github.com/Estabilis/estabilis-platform/issues/44
# ---------------------------------------------------------------------------

locals {
  env_code = {
    dev  = "dev"
    uat  = "uat"
    hml  = "hml"
    stg  = "stg"
    prd  = "prd"
    prod = "prd"
  }[var.environment]

  # Full base name for standard resources: estabilis-{workload_domain}-{env}-{region}
  # Default workload_domain="workload" preserves backward compat (v2.x).
  base_name = "${var.name_prefix}-${var.workload_domain}-${local.env_code}-${var.location}"

  # CAF tags — automatic + optional (empty values filtered out)
  caf_tags = {
    for k, v in {
      # Functional
      app        = coalesce(var.tag_app, var.name_prefix)
      env        = local.env_code
      region     = var.location
      tier       = var.tag_tier
      managed-by = "terraform"
      # Classification
      criticality     = var.tag_criticality
      confidentiality = var.tag_confidentiality
      sla             = var.tag_sla
      # Accounting
      costcenter = var.tag_costcenter
      department = var.tag_department
      budget     = var.tag_budget
      # Purpose
      businessprocess = var.tag_businessprocess
      businessimpact  = var.tag_businessimpact
      revenueimpact   = var.tag_revenueimpact
      # Ownership
      opsteam      = var.tag_opsteam
      businessunit = var.tag_businessunit
    } : k => v if v != ""
  }

  tags = merge(local.caf_tags, var.extra_tags)

  # --- Host derivation: {app}.{cluster_name}.{domain} (or {internal_domain} for "internal" profile) ---
  # v3.0.0 platform-parity: split-horizon DNS via var.internal_domain. When set,
  # exposures keyed "internal" derive hosts under internal_domain; all other
  # keys keep domain. Explicit host always wins over auto-derivation.
  _use_internal_domain = var.internal_domain != ""

  _app_host = {
    for app in ["hubble"] : app =>
    "${app}.${azurerm_kubernetes_cluster.workload.name}.${var.domain}"
  }
  _app_host_internal = {
    for app in ["hubble"] : app =>
    "${app}.${azurerm_kubernetes_cluster.workload.name}.${var.internal_domain}"
  }

  hubble_ui_exposures_resolved = {
    for k, v in var.hubble_ui_exposures : k => merge(v, {
      host = length(v.host) > 0 ? v.host : (
        local._use_internal_domain && k == "internal"
        ? lookup(local._app_host_internal, "hubble", "")
        : lookup(local._app_host, "hubble", "")
      )
    })
  }
}

# ---------------------------------------------------------------------------
# Operator IP — auto-detected for AKS API + Key Vault firewall access
# ---------------------------------------------------------------------------

data "http" "operator_ip" {
  url = "https://api.ipify.org" # IPv4 only
}

locals {
  operator_ip = "${chomp(data.http.operator_ip.response_body)}/32"

  # --- v3.0.0 — Network/subnet refs (internal OR external) ---
  vnet_id      = var.network_existing_enabled ? var.existing_vnet_id : (length(azurerm_virtual_network.workload) > 0 ? azurerm_virtual_network.workload[0].id : "")
  vnet_name    = var.network_existing_enabled ? var.existing_vnet_name : (length(azurerm_virtual_network.workload) > 0 ? azurerm_virtual_network.workload[0].name : "")
  vnet_rg_name = var.network_existing_enabled ? var.existing_vnet_resource_group_name : azurerm_resource_group.workload.name

  subnet_nodes_id = var.network_existing_enabled ? var.existing_subnet_nodes_id : (length(azurerm_subnet.aks_nodes) > 0 ? azurerm_subnet.aks_nodes[0].id : "")
  subnet_pods_id  = var.network_existing_enabled ? var.existing_subnet_pods_id : (length(azurerm_subnet.aks_pods) > 0 ? azurerm_subnet.aks_pods[0].id : "")

  # PE extra subnet — aks_pods exists only in legacy (auto-VNet) mode
  pe_extra_subnet_ids = var.network_existing_enabled ? [] : (length(azurerm_subnet.aks_pods) > 0 ? [azurerm_subnet.aks_pods[0].id] : [])

  # --- v3.0.0 — NAT Gateway egress IPs (internal OR external) ---
  nat_gateway_egress_ips = var.network_existing_enabled ? var.external_nat_gateway_egress_ips : (
    var.nat_gateway_enabled && length(azurerm_public_ip.nat_gateway) > 0 ? [azurerm_public_ip.nat_gateway[0].ip_address] : []
  )
  nat_gateway_egress_ips_cidr = [for ip in local.nat_gateway_egress_ips : "${ip}/32"]

  # --- v3.0.0 — AKS identity mode (UAMI when external PDZ) ---
  use_uami          = var.enable_private_cluster && !contains(["System", "None", ""], var.private_dns_zone_id)
  aks_identity_type = local.use_uami ? "UserAssigned" : "SystemAssigned"

  authorized_ips = distinct(concat(var.authorized_ip_ranges, [local.operator_ip], local.nat_gateway_egress_ips_cidr))

  # Centralized firewall rules — auto-detected + global + per-resource
  firewall_base_ips = distinct(concat(
    [local.operator_ip],
    local.nat_gateway_egress_ips_cidr,
    var.firewall_allowed_ips,
  ))

  firewall_base_subnet_ids = distinct(concat(
    [local.subnet_nodes_id],
    var.firewall_allowed_subnet_ids,
  ))

  # Storage accounts require IPs without /32 (max /30 or bare IP)
  firewall_base_ips_bare = [for ip in local.firewall_base_ips : replace(ip, "/32", "")]

  # Per-resource firewall IPs (base + extras)
  firewall_keyvault_ips = distinct(concat(local.firewall_base_ips, var.keyvault_extra_allowed_ips))
  firewall_tfstate_ips  = distinct(concat(local.firewall_base_ips_bare, [for ip in var.storage_tfstate_extra_allowed_ips : replace(ip, "/32", "")]))
  firewall_velero_ips   = distinct(concat(local.firewall_base_ips_bare, [for ip in var.storage_velero_extra_allowed_ips : replace(ip, "/32", "")]))
  firewall_acr_ips      = distinct(concat(local.firewall_base_ips, var.acr_extra_allowed_ips))
}

# ---------------------------------------------------------------------------
# Random suffix for globally-unique storage account names
# ---------------------------------------------------------------------------

resource "random_string" "storage_suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}
