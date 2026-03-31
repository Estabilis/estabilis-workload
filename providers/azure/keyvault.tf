# ---------------------------------------------------------------------------
# Key Vault — stores secrets for workload applications
# ---------------------------------------------------------------------------

resource "azurerm_key_vault" "workload" {
  count                      = var.keyvault_enabled ? 1 : 0
  name                       = "kv-${var.name_prefix}-${local.env_code}-${random_string.storage_suffix.result}"
  location                   = azurerm_resource_group.workload.location
  resource_group_name        = azurerm_resource_group.workload.name
  tenant_id                  = var.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  soft_delete_retention_days = var.keyvault_soft_delete_days
  purge_protection_enabled   = var.keyvault_purge_protection

  dynamic "network_acls" {
    for_each = var.firewall_enabled ? [1] : []
    content {
      default_action             = "Deny"
      bypass                     = "AzureServices"
      ip_rules                   = local.firewall_keyvault_ips
      virtual_network_subnet_ids = concat(local.firewall_base_subnet_ids, [azurerm_subnet.aks_pods.id])
    }
  }

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Terraform needs KV access to create secrets during apply.
# ---------------------------------------------------------------------------

data "azurerm_client_config" "current" {}

resource "azurerm_role_assignment" "terraform_kv_officer" {
  count                = var.keyvault_enabled ? 1 : 0
  scope                = azurerm_key_vault.workload[0].id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}
