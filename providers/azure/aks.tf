# ---------------------------------------------------------------------------
# UAMI for AKS — required when private_dns_zone_id is an external ARM ID
# AKS with SystemAssigned cannot write A records to PDZs outside the MC_ RG,
# nor join an external VNet/subnet without Network Contributor on it.
# Parity with estabilis-platform/providers/azure/aks.tf.
# ---------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "aks" {
  count               = local.use_uami ? 1 : 0
  name                = "mi-${local.base_name}-aks"
  location            = azurerm_resource_group.workload.location
  resource_group_name = azurerm_resource_group.workload.name
  tags                = local.tags
}

resource "azurerm_role_assignment" "aks_pdz_contributor" {
  count                = local.use_uami ? 1 : 0
  scope                = var.private_dns_zone_id
  role_definition_name = "Private DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.aks[0].principal_id
}

# When in BYO Network mode, UAMI needs Network Contributor on the external nodes
# subnet (least-privilege; ADR-0001 §2.7 already grants subnets/join/action via
# a custom role on the VNet for the operator that runs Terraform).
resource "azurerm_role_assignment" "aks_uami_subnet_contributor" {
  count                = local.use_uami && var.network_existing_enabled ? 1 : 0
  scope                = local.subnet_nodes_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks[0].principal_id
}

# ---------------------------------------------------------------------------
# AKS Cluster
# ---------------------------------------------------------------------------

resource "azurerm_kubernetes_cluster" "workload" {
  name                         = "aks-${local.base_name}"
  location                     = azurerm_resource_group.workload.location
  resource_group_name          = azurerm_resource_group.workload.name
  node_resource_group          = var.node_resource_group != "" ? var.node_resource_group : null
  dns_prefix                   = "aks-${local.base_name}"
  kubernetes_version           = var.kubernetes_version
  sku_tier                     = var.sku_tier
  automatic_upgrade_channel    = var.auto_upgrade_channel
  run_command_enabled          = var.run_command_enabled
  image_cleaner_enabled        = var.image_cleaner_enabled
  image_cleaner_interval_hours = var.image_cleaner_interval_hours

  # --- Identity ----------------------------------------------------------
  identity {
    type         = local.aks_identity_type
    identity_ids = local.use_uami ? [azurerm_user_assigned_identity.aks[0].id] : null
  }

  workload_identity_enabled = true
  oidc_issuer_enabled       = true
  local_account_disabled    = var.local_account_disabled

  # --- Private Cluster (opt-in) -----------------------------------------
  # Quando `enable_private_cluster = true`, API server fica acessível APENAS
  # via Private Endpoint na VNet (resolução via PDZ). kubelet conecta via PE
  # privado (sem ir pela Internet), eliminando a necessidade de
  # `authorized_ip_ranges`.
  #
  # `private_dns_zone_id`:
  #   - "System": AKS gerencia uma PDZ `privatelink.<region>.azmk8s.io`
  #     dentro do MC_<rg> shadow resource group (mode SystemAssigned).
  #   - "/subscriptions/.../privateDnsZones/privatelink.<region>.azmk8s.io":
  #     usa PDZ canonical EXISTENTE (recomendado para hub-spoke). Caller
  #     deve ter criado vnet_link da VNet workload na PDZ antes do apply.
  #     Requer UAMI (`local.use_uami = true`).
  private_cluster_enabled             = var.enable_private_cluster
  private_dns_zone_id                 = var.enable_private_cluster ? var.private_dns_zone_id : null
  private_cluster_public_fqdn_enabled = var.enable_private_cluster ? var.private_cluster_public_fqdn_enabled : false

  # --- Azure AD integration -----------------------------------------------
  dynamic "azure_active_directory_role_based_access_control" {
    for_each = var.aad_managed_enabled ? [1] : []
    content {
      azure_rbac_enabled     = var.azure_rbac_enabled
      admin_group_object_ids = var.aad_admin_group_ids
    }
  }

  # --- Default (system) node pool ----------------------------------------
  default_node_pool {
    name                         = "system"
    node_count                   = var.system_auto_scaling_enabled ? null : var.system_node_count
    vm_size                      = var.system_vm_size
    vnet_subnet_id               = local.subnet_nodes_id
    pod_subnet_id                = var.network_plugin_mode == "pod-subnet" && local.subnet_pods_id != "" ? local.subnet_pods_id : null
    os_disk_size_gb              = var.system_os_disk_size_gb
    os_disk_type                 = var.system_os_disk_type
    zones                        = var.system_availability_zones
    auto_scaling_enabled         = var.system_auto_scaling_enabled
    min_count                    = var.system_auto_scaling_enabled ? var.system_min_count : null
    max_count                    = var.system_auto_scaling_enabled ? var.system_max_count : null
    only_critical_addons_enabled = var.only_critical_addons_enabled
    temporary_name_for_rotation  = "systemtmp"

    upgrade_settings {
      max_surge = var.system_max_surge
    }
  }

  # --- Network profile ---------------------------------------------------
  network_profile {
    network_plugin = var.network_dataplane == "byo-cni" ? "none" : "azure"
    # v3.0.0+: `network_plugin_mode` exposto via var enum-descritiva.
    # Tradução para o valor que o azurerm provider 4.x aceita:
    #   var == "overlay"    → "overlay"  (Azure CNI Overlay)
    #   var == "pod-subnet" → null       (Azure CNI Pod Subnet / flat networking)
    #   network_dataplane == "byo-cni" → null (force, BYO CNI ignora plugin mode)
    network_plugin_mode = var.network_dataplane == "byo-cni" ? null : (
      var.network_plugin_mode == "overlay" ? "overlay" : null
    )
    network_data_plane = var.network_dataplane == "cilium" || var.network_dataplane == "cilium-acns" ? "cilium" : var.network_dataplane == "byo-cni" ? null : "azure"
    network_policy     = var.network_dataplane == "cilium" || var.network_dataplane == "cilium-acns" ? "cilium" : null
    outbound_type      = var.outbound_type
    service_cidr       = var.service_cidr
    dns_service_ip     = var.dns_service_ip
    pod_cidr           = var.pod_cidr

    # ACNS — Advanced Container Networking Services (Hubble + FQDN filtering)
    # observability_enabled = Hubble flow logs + metrics; security_enabled = FQDN
    # filtering via Cilium NetworkPolicies. Both toggles default true (v3.0.0).
    dynamic "advanced_networking" {
      for_each = var.network_dataplane == "cilium-acns" ? [1] : []
      content {
        observability_enabled = var.acns_observability_enabled
        security_enabled      = var.acns_security_enabled
      }
    }
  }

  # `api_server_access_profile.authorized_ip_ranges` é EXCLUSIVO com
  # `private_cluster_enabled = true` (Azure API rejeita ambos no mesmo cluster).
  dynamic "api_server_access_profile" {
    for_each = var.enable_private_cluster ? [] : [1]
    content {
      authorized_ip_ranges = concat(
        local.authorized_ips,
        var.hub_registration_enabled && local.hub_egress != "" ? ["${local.hub_egress}/32"] : [],
      )
    }
  }

  dynamic "monitor_metrics" {
    for_each = var.azure_monitor_enabled ? [1] : []
    content {}
  }

  dynamic "oms_agent" {
    for_each = var.azure_monitor_enabled && var.diagnostics_enabled ? [1] : []
    content {
      log_analytics_workspace_id = azurerm_log_analytics_workspace.workload[0].id
    }
  }

  maintenance_window_auto_upgrade {
    frequency   = "Weekly"
    interval    = 1
    day_of_week = var.maintenance_window_day
    start_time  = format("%02d:00", var.maintenance_window_start_hour)
    duration    = var.maintenance_window_duration
    utc_offset  = "+00:00"
  }

  maintenance_window_node_os {
    frequency   = "Weekly"
    interval    = 1
    day_of_week = var.maintenance_window_day
    start_time  = format("%02d:00", var.maintenance_window_start_hour)
    duration    = var.maintenance_window_duration
    utc_offset  = "+00:00"
  }

  depends_on = [
    azurerm_subnet_nat_gateway_association.aks_nodes,
    azurerm_subnet_network_security_group_association.aks_nodes,
    azurerm_role_assignment.aks_pdz_contributor,
    azurerm_role_assignment.aks_uami_subnet_contributor,
  ]

  # BYO CNI: nodes stay NotReady until Cilium installs, but the provider polls
  # waiting for Ready. Reduce create timeout to avoid unnecessary waiting.
  timeouts {
    create = var.network_dataplane == "byo-cni" ? "15m" : "30m"
    update = "30m"
    delete = "30m"
  }

  tags = local.tags

  # --- v3.0.0 — Preconditions: catch invalid combos at plan time ----------
  lifecycle {
    precondition {
      condition     = !var.enable_private_cluster || var.private_dns_zone_id != ""
      error_message = "enable_private_cluster=true requires private_dns_zone_id (use 'System' for AKS-managed PDZ in MC_ RG, or an ARM ID of an external canonical PDZ)."
    }

    precondition {
      condition     = var.outbound_type != "userDefinedRouting" || var.network_existing_enabled
      error_message = "outbound_type=userDefinedRouting requires network_existing_enabled=true (the external network repo must own the route table with 0.0.0.0/0)."
    }

    precondition {
      condition     = var.outbound_type != "userAssignedNATGateway" || var.nat_gateway_enabled || var.network_existing_enabled
      error_message = "outbound_type=userAssignedNATGateway requires nat_gateway_enabled=true (internal NAT GW) OR network_existing_enabled=true (external NAT GW provided via external_nat_gateway_egress_ips)."
    }

    precondition {
      condition     = var.network_plugin_mode != "pod-subnet" || local.subnet_pods_id != ""
      error_message = "network_plugin_mode='pod-subnet' (Azure CNI Pod Subnet) requires a non-empty pods subnet: either set subnet_pods_prefix (auto-VNet mode) or existing_subnet_pods_id (BYO mode)."
    }
  }
}

# ---------------------------------------------------------------------------
# Azure RBAC — role assignments on the AKS cluster
# Available roles:
#   - Azure Kubernetes Service Cluster Admin Role (full access)
#   - Azure Kubernetes Service Cluster User Role (get credentials)
#   - Azure Kubernetes Service RBAC Admin (manage K8s RBAC)
#   - Azure Kubernetes Service RBAC Cluster Admin (cluster-admin via RBAC)
#   - Azure Kubernetes Service RBAC Reader (read-only K8s resources)
#   - Azure Kubernetes Service RBAC Writer (read + write K8s resources)
# ---------------------------------------------------------------------------

resource "azurerm_role_assignment" "aks_rbac" {
  count                = var.aad_managed_enabled && var.azure_rbac_enabled ? length(var.aks_role_assignments) : 0
  scope                = azurerm_kubernetes_cluster.workload.id
  role_definition_name = var.aks_role_assignments[count.index].role
  principal_id         = var.aks_role_assignments[count.index].principal_id
}

# ---------------------------------------------------------------------------
# Additional node pool – Spot (preferred for workloads, cost-efficient)
# ---------------------------------------------------------------------------

resource "azurerm_kubernetes_cluster_node_pool" "workload_spot" {
  count                       = var.workload_spot_enabled ? 1 : 0
  name                        = "workloadsp"
  kubernetes_cluster_id       = azurerm_kubernetes_cluster.workload.id
  vm_size                     = var.workload_vm_size
  vnet_subnet_id              = local.subnet_nodes_id
  pod_subnet_id               = var.network_plugin_mode == "pod-subnet" && local.subnet_pods_id != "" ? local.subnet_pods_id : null
  os_disk_size_gb             = var.workload_os_disk_size_gb
  os_disk_type                = var.workload_os_disk_type
  zones                       = var.workload_availability_zones
  temporary_name_for_rotation = "wkldspttmp"

  priority        = "Spot"
  eviction_policy = "Delete"
  spot_max_price  = var.spot_max_price

  auto_scaling_enabled = true
  min_count            = 0
  max_count            = var.workload_spot_max_count

  node_labels = {
    "estabilis.io/workload-type" = "application"
    "estabilis.io/pool-type"     = "spot"
  }
  node_taints = [
    "kubernetes.azure.com/scalesetpriority=spot:NoSchedule",
  ]
  tags = local.tags

  lifecycle {
    ignore_changes = [
      node_labels["kubernetes.azure.com/scalesetpriority"],
      upgrade_settings,
    ]
  }
}

# ---------------------------------------------------------------------------
# Additional node pool – Regular (guaranteed capacity)
# ---------------------------------------------------------------------------

resource "azurerm_kubernetes_cluster_node_pool" "workload_regular" {
  count                       = var.workload_regular_enabled ? 1 : 0
  name                        = "workloadrg"
  kubernetes_cluster_id       = azurerm_kubernetes_cluster.workload.id
  vm_size                     = var.workload_vm_size
  vnet_subnet_id              = local.subnet_nodes_id
  pod_subnet_id               = var.network_plugin_mode == "pod-subnet" && local.subnet_pods_id != "" ? local.subnet_pods_id : null
  os_disk_size_gb             = var.workload_os_disk_size_gb
  os_disk_type                = var.workload_os_disk_type
  zones                       = var.workload_availability_zones
  temporary_name_for_rotation = "wkldrgtmp"

  priority = "Regular"

  auto_scaling_enabled = true
  min_count            = var.workload_regular_min_count > 0 ? var.workload_regular_min_count : 1
  max_count            = var.workload_regular_max_count

  upgrade_settings {
    max_surge                     = var.workload_max_surge
    drain_timeout_in_minutes      = var.workload_drain_timeout_in_minutes
    node_soak_duration_in_minutes = var.workload_node_soak_duration_in_minutes
  }

  node_labels = {
    "estabilis.io/workload-type" = "application"
    "estabilis.io/pool-type"     = "regular"
  }
  tags = local.tags
}
