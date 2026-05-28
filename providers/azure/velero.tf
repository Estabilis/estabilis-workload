# ---------------------------------------------------------------------------
# Velero Backup Storage — backup workload cluster resources
# Toggle via: velero_enabled = false
# ---------------------------------------------------------------------------

resource "azurerm_storage_account" "velero_backup" {
  count                           = var.velero_enabled ? 1 : 0
  name                            = "st${var.name_prefix}${local.env_code}vlr${random_string.storage_suffix.result}"
  resource_group_name             = azurerm_resource_group.workload.name
  location                        = azurerm_resource_group.workload.location
  account_tier                    = "Standard"
  account_replication_type        = coalesce(var.storage_replication_type_velero, var.storage_replication_type)
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false

  # PE mode disables public access; legacy mode keeps it on with firewall.
  public_network_access_enabled = !var.velero_private_endpoint_enabled

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

  dynamic "network_rules" {
    for_each = !var.velero_private_endpoint_enabled && var.firewall_enabled ? [1] : []
    content {
      default_action             = "Deny"
      bypass                     = ["AzureServices"]
      ip_rules                   = local.firewall_velero_ips
      virtual_network_subnet_ids = local.firewall_base_subnet_ids
    }
  }

  tags = local.tags
}

resource "azurerm_storage_container" "velero_backup" {
  count                 = var.velero_enabled ? 1 : 0
  name                  = "velero-backup"
  storage_account_id    = azurerm_storage_account.velero_backup[0].id
  container_access_type = "private"
}

# ---------------------------------------------------------------------------
# v3.0.0 — Private Endpoint for Velero Storage (canonical PDZ from hub)
# Toggle: velero_private_endpoint_enabled = true
# Requires: external_pdz_blob_id AND velero_enabled = true
# ---------------------------------------------------------------------------

resource "azurerm_private_endpoint" "velero" {
  count               = var.velero_enabled && var.velero_private_endpoint_enabled ? 1 : 0
  name                = "pe-${local.base_name}-velero"
  location            = azurerm_resource_group.workload.location
  resource_group_name = azurerm_resource_group.workload.name
  subnet_id           = local.subnet_nodes_id
  tags                = local.tags

  private_service_connection {
    name                           = "psc-${local.base_name}-velero"
    private_connection_resource_id = azurerm_storage_account.velero_backup[0].id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.external_pdz_blob_id]
  }

  lifecycle {
    precondition {
      condition     = var.external_pdz_blob_id != ""
      error_message = "velero_private_endpoint_enabled=true requires external_pdz_blob_id (canonical PDZ privatelink.blob.core.windows.net from hub network repo)."
    }
  }
}
