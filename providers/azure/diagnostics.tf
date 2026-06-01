# ---------------------------------------------------------------------------
# Log Analytics Workspace + Diagnostic Settings
# Toggle via: diagnostics_enabled = false
# External LAW: set external_log_analytics_workspace_id to fan-out to a
# central observability workspace ALONGSIDE the local LAW (additive, not
# replacement). Each *_external resource gates ONLY on external_law_enabled
# so it works even when diagnostics_enabled = false (external-only mode).
#
# Categories are operator-customizable via *_diagnostic_log_categories /
# *_diagnostic_metric_categories variables (see variables.tf). Defaults
# reproduce the previously-hardcoded category lists — zero diff in plan
# for existing consumers.
# ---------------------------------------------------------------------------

locals {
  external_law_enabled = var.external_log_analytics_workspace_id != ""
}

resource "azurerm_log_analytics_workspace" "workload" {
  count               = var.diagnostics_enabled ? 1 : 0
  name                = "law-${local.base_name}"
  location            = azurerm_resource_group.workload.location
  resource_group_name = azurerm_resource_group.workload.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  tags                = local.tags
}

# ---------------------------------------------------------------------------
# AKS
# ---------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "aks" {
  count                      = var.diagnostics_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-aks"
  target_resource_id         = azurerm_kubernetes_cluster.workload.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.workload[0].id

  dynamic "enabled_log" {
    for_each = toset(var.aks_diagnostic_log_categories)
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = toset(var.aks_diagnostic_metric_categories_local)
    content {
      category = enabled_metric.value
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "aks_external" {
  count                      = local.external_law_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-aks-external"
  target_resource_id         = azurerm_kubernetes_cluster.workload.id
  log_analytics_workspace_id = var.external_log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = toset(concat(var.aks_diagnostic_log_categories, var.aks_diagnostic_log_categories_external_extra))
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = toset(var.aks_diagnostic_metric_categories)
    content {
      category = enabled_metric.value
    }
  }
}

# ---------------------------------------------------------------------------
# Key Vault — Workload (toggle: keyvault_enabled)
# ---------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "keyvault_local" {
  count                      = var.diagnostics_enabled && var.keyvault_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-kv"
  target_resource_id         = azurerm_key_vault.workload[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.workload[0].id

  dynamic "enabled_log" {
    for_each = toset(var.keyvault_diagnostic_log_categories)
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = toset(var.keyvault_diagnostic_metric_categories)
    content {
      category = enabled_metric.value
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "keyvault_external" {
  count                      = local.external_law_enabled && var.keyvault_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-kv-external"
  target_resource_id         = azurerm_key_vault.workload[0].id
  log_analytics_workspace_id = var.external_log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = toset(var.keyvault_diagnostic_log_categories)
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = toset(var.keyvault_diagnostic_metric_categories)
    content {
      category = enabled_metric.value
    }
  }
}

# ---------------------------------------------------------------------------
# Storage Account — TFState (blob service, always created)
# ---------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "sa_tfstate_local" {
  count                      = var.tfstate_enabled && var.diagnostics_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-tfstate-blob"
  target_resource_id         = "${azurerm_storage_account.tfstate[0].id}/blobServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.workload[0].id

  dynamic "enabled_log" {
    for_each = toset(var.storage_diagnostic_log_categories)
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = toset(var.storage_diagnostic_metric_categories)
    content {
      category = enabled_metric.value
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "sa_tfstate_external" {
  count                      = var.tfstate_enabled && local.external_law_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-tfstate-blob-external"
  target_resource_id         = "${azurerm_storage_account.tfstate[0].id}/blobServices/default"
  log_analytics_workspace_id = var.external_log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = toset(var.storage_diagnostic_log_categories)
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = toset(var.storage_diagnostic_metric_categories)
    content {
      category = enabled_metric.value
    }
  }
}

# ---------------------------------------------------------------------------
# Storage Account — Velero Backup (toggle: velero_enabled)
# ---------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "sa_velero_local" {
  count                      = var.diagnostics_enabled && var.velero_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-velero-blob"
  target_resource_id         = "${azurerm_storage_account.velero_backup[0].id}/blobServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.workload[0].id

  dynamic "enabled_log" {
    for_each = toset(var.storage_diagnostic_log_categories)
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = toset(var.storage_diagnostic_metric_categories)
    content {
      category = enabled_metric.value
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "sa_velero_external" {
  count                      = local.external_law_enabled && var.velero_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-velero-blob-external"
  target_resource_id         = "${azurerm_storage_account.velero_backup[0].id}/blobServices/default"
  log_analytics_workspace_id = var.external_log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = toset(var.storage_diagnostic_log_categories)
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = toset(var.storage_diagnostic_metric_categories)
    content {
      category = enabled_metric.value
    }
  }
}

# ---------------------------------------------------------------------------
# Storage Account — Cost Exports (toggle: cost_export_enabled)
# ---------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "sa_cost_local" {
  count                      = var.diagnostics_enabled && var.cost_export_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-costs-blob"
  target_resource_id         = "${azurerm_storage_account.cost_exports[0].id}/blobServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.workload[0].id

  dynamic "enabled_log" {
    for_each = toset(var.storage_diagnostic_log_categories)
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = toset(var.storage_diagnostic_metric_categories)
    content {
      category = enabled_metric.value
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "sa_cost_external" {
  count                      = local.external_law_enabled && var.cost_export_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-costs-blob-external"
  target_resource_id         = "${azurerm_storage_account.cost_exports[0].id}/blobServices/default"
  log_analytics_workspace_id = var.external_log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = toset(var.storage_diagnostic_log_categories)
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = toset(var.storage_diagnostic_metric_categories)
    content {
      category = enabled_metric.value
    }
  }
}

# ---------------------------------------------------------------------------
# ACR — Azure Container Registry (toggle: acr_enabled)
# ---------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "acr_local" {
  count                      = var.diagnostics_enabled && var.acr_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-acr"
  target_resource_id         = azurerm_container_registry.workload[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.workload[0].id

  dynamic "enabled_log" {
    for_each = toset(var.acr_diagnostic_log_categories)
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = toset(var.acr_diagnostic_metric_categories)
    content {
      category = enabled_metric.value
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "acr_external" {
  count                      = local.external_law_enabled && var.acr_enabled ? 1 : 0
  name                       = "diag-${local.base_name}-acr-external"
  target_resource_id         = azurerm_container_registry.workload[0].id
  log_analytics_workspace_id = var.external_log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = toset(var.acr_diagnostic_log_categories)
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = toset(var.acr_diagnostic_metric_categories)
    content {
      category = enabled_metric.value
    }
  }
}
