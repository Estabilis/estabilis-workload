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

  # PE mode disables public access; legacy mode keeps it on with firewall.
  public_network_access_enabled = !var.keyvault_private_endpoint_enabled

  dynamic "network_acls" {
    for_each = !var.keyvault_private_endpoint_enabled && var.firewall_enabled ? [1] : []
    content {
      default_action             = "Deny"
      bypass                     = "AzureServices"
      ip_rules                   = local.firewall_keyvault_ips
      virtual_network_subnet_ids = concat(local.firewall_base_subnet_ids, local.pe_extra_subnet_ids)
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

# ---------------------------------------------------------------------------
# Cloudflare API token — stored in workload KV when dns_provider=cloudflare.
# Consumed by ExternalSecrets on the workload cluster (external-dns-config
# and cert-manager-config charts render ExternalSecret CRDs that read this
# KV entry). The token NEVER flows through bridge annotations — ADR 0010
# bridge is for identifiers only, not secrets.
# ---------------------------------------------------------------------------

resource "azurerm_key_vault_secret" "cloudflare_api_token" {
  count        = var.keyvault_enabled && var.domain != "" && var.dns_provider == "cloudflare" ? 1 : 0
  name         = "cloudflare-api-token"
  value        = var.cloudflare_api_token
  key_vault_id = azurerm_key_vault.workload[0].id

  depends_on = [azurerm_role_assignment.terraform_kv_officer]
}

# ---------------------------------------------------------------------------
# v3.0.0 — Private Endpoint for Key Vault (canonical PDZ from hub network repo)
# Toggle: keyvault_private_endpoint_enabled = true
# Requires: external_pdz_vaultcore_id
# ---------------------------------------------------------------------------

resource "azurerm_private_endpoint" "keyvault" {
  count               = var.keyvault_enabled && var.keyvault_private_endpoint_enabled ? 1 : 0
  name                = "pe-${local.base_name}-vault"
  location            = azurerm_resource_group.workload.location
  resource_group_name = azurerm_resource_group.workload.name
  subnet_id           = local.subnet_nodes_id
  tags                = local.tags

  private_service_connection {
    name                           = "psc-${local.base_name}-vault"
    private_connection_resource_id = azurerm_key_vault.workload[0].id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.external_pdz_vaultcore_id]
  }

  lifecycle {
    precondition {
      condition     = var.external_pdz_vaultcore_id != ""
      error_message = "keyvault_private_endpoint_enabled=true requires external_pdz_vaultcore_id (canonical PDZ privatelink.vaultcore.azure.net from hub network repo)."
    }
  }
}
