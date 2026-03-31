# ---------------------------------------------------------------------------
# Cost Management Export – Azure billing data consumed by platform OpenCost
# Toggle via: cost_export_enabled = false
# Disable if workload is in the same subscription as the platform (platform
# cost export already covers it).
# ---------------------------------------------------------------------------

# The Cost Management Export API requires Microsoft.CostManagementExports
# to be registered. This is handled by `estabilis register-providers`
# (run once per subscription) and verified by `estabilis apply`.

resource "azurerm_storage_account" "cost_exports" {
  count                           = var.cost_export_enabled ? 1 : 0
  name                            = "st${var.name_prefix}${local.env_code}cst${random_string.storage_suffix.result}"
  resource_group_name             = azurerm_resource_group.workload.name
  location                        = azurerm_resource_group.workload.location
  account_tier                    = "Standard"
  account_replication_type        = coalesce(var.storage_replication_type_cost_exports, var.storage_replication_type)
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = true # required by OpenCost cloud-integration
  allow_nested_items_to_be_public = false

  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices"]
  }

  dynamic "blob_properties" {
    for_each = var.storage_soft_delete_enabled ? [1] : []
    content {
      delete_retention_policy {
        days = var.storage_soft_delete_retention_days
      }
      container_delete_retention_policy {
        days = var.storage_soft_delete_retention_days
      }
    }
  }

  lifecycle {
    ignore_changes = [network_rules]
  }

  tags = local.tags
}

resource "azurerm_storage_account_network_rules" "cost_exports" {
  count              = var.cost_export_enabled ? 1 : 0
  storage_account_id = azurerm_storage_account.cost_exports[0].id
  default_action     = "Deny"
  bypass             = ["AzureServices"]

  depends_on = [azurerm_subscription_cost_management_export.daily]
}

resource "azurerm_storage_container" "cost_exports" {
  count                 = var.cost_export_enabled ? 1 : 0
  name                  = "cost-exports"
  storage_account_id    = azurerm_storage_account.cost_exports[0].id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "terraform_cost_exports_owner" {
  count                = var.cost_export_enabled ? 1 : 0
  scope                = azurerm_storage_account.cost_exports[0].id
  role_definition_name = "Owner"
  principal_id         = data.azurerm_client_config.current.object_id
}

data "azurerm_subscription" "current" {}

resource "azurerm_subscription_cost_management_export" "daily" {
  count                        = var.cost_export_enabled ? 1 : 0
  name                         = "opencost-daily-${local.base_name}"
  subscription_id              = data.azurerm_subscription.current.id
  recurrence_type              = "Daily"
  recurrence_period_start_date = "${formatdate("YYYY-MM-DD", plantimestamp())}T00:00:00Z"
  recurrence_period_end_date   = "${formatdate("YYYY", plantimestamp()) + 10}-${formatdate("MM-DD", plantimestamp())}T00:00:00Z"

  export_data_storage_location {
    container_id     = azurerm_storage_container.cost_exports[0].id
    root_folder_path = "/cost-exports"
  }

  export_data_options {
    type       = "ActualCost"
    time_frame = "MonthToDate"
  }

  lifecycle {
    ignore_changes = [recurrence_period_start_date, recurrence_period_end_date]
  }

  depends_on = [
    azurerm_role_assignment.terraform_cost_exports_owner,
  ]
}
