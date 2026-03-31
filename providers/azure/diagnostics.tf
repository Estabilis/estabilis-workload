# ---------------------------------------------------------------------------
# Log Analytics Workspace + AKS Diagnostic Settings
# Toggle via: diagnostics_enabled = false
# ---------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "workload" {
  count               = var.diagnostics_enabled ? 1 : 0
  name                = "law-${local.base_name}"
  location            = azurerm_resource_group.workload.location
  resource_group_name = azurerm_resource_group.workload.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  tags                = local.tags
}

resource "azurerm_monitor_diagnostic_setting" "aks" {
  count                      = var.diagnostics_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-aks"
  target_resource_id         = azurerm_kubernetes_cluster.workload.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.workload[0].id

  enabled_log {
    category = "kube-audit-admin"
  }

  enabled_log {
    category = "kube-controller-manager"
  }

  enabled_log {
    category = "kube-scheduler"
  }

  enabled_log {
    category = "cluster-autoscaler"
  }

  enabled_log {
    category = "guard"
  }

}
