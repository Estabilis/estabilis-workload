# ---------------------------------------------------------------------------
# Terraform State Backend — Bootstrap resources
# Created first with local state, then state is migrated here.
#
# Gated by var.tfstate_enabled (default true). Set false when the backend
# lives in an external, pre-provisioned storage account (e.g. a central
# bootstrap layer) — then NO resource group / storage account / container is
# created here, avoiding an orphaned tfstate storage account per workload.
# ---------------------------------------------------------------------------

resource "azurerm_resource_group" "tfstate" {
  count    = var.tfstate_enabled ? 1 : 0
  name     = "rg-${local.base_name}-tfstate"
  location = var.location
  tags     = local.tags
}

resource "azurerm_storage_account" "tfstate" {
  count                           = var.tfstate_enabled ? 1 : 0
  name                            = "st${var.name_prefix}${local.env_code}tfst${random_string.storage_suffix.result}"
  resource_group_name             = azurerm_resource_group.tfstate[0].name
  location                        = azurerm_resource_group.tfstate[0].location
  account_tier                    = "Standard"
  account_replication_type        = coalesce(var.storage_replication_type_tfstate, var.storage_replication_type)
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false

  # PE mode disables public access; legacy mode keeps it on with firewall.
  public_network_access_enabled = !var.tfstate_private_endpoint_enabled

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
    for_each = !var.tfstate_private_endpoint_enabled && var.firewall_enabled ? [1] : []
    content {
      default_action             = "Deny"
      bypass                     = ["AzureServices"]
      ip_rules                   = local.firewall_tfstate_ips
      virtual_network_subnet_ids = local.firewall_base_subnet_ids
    }
  }

  tags = local.tags
}

resource "azurerm_storage_container" "tfstate" {
  count                 = var.tfstate_enabled ? 1 : 0
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.tfstate[0].id
  container_access_type = "private"
}

# ---------------------------------------------------------------------------
# RBAC — grant the deployer (current identity) access to the tfstate blob
# ---------------------------------------------------------------------------

resource "azurerm_role_assignment" "tfstate_deployer" {
  count                = var.tfstate_enabled ? 1 : 0
  scope                = azurerm_storage_container.tfstate[0].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ---------------------------------------------------------------------------
# v3.0.0 — Private Endpoint for tfstate Storage (canonical PDZ from hub)
# Toggle: tfstate_private_endpoint_enabled = true (requires tfstate_enabled)
# Requires: external_pdz_blob_id
# ---------------------------------------------------------------------------

resource "azurerm_private_endpoint" "tfstate" {
  count               = var.tfstate_enabled && var.tfstate_private_endpoint_enabled ? 1 : 0
  name                = "pe-${local.base_name}-tfstate"
  location            = azurerm_resource_group.tfstate[0].location
  resource_group_name = azurerm_resource_group.tfstate[0].name
  subnet_id           = local.subnet_nodes_id
  tags                = local.tags

  private_service_connection {
    name                           = "psc-${local.base_name}-tfstate"
    private_connection_resource_id = azurerm_storage_account.tfstate[0].id
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
      error_message = "tfstate_private_endpoint_enabled=true requires external_pdz_blob_id (canonical PDZ privatelink.blob.core.windows.net from hub network repo)."
    }
  }
}
