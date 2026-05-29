# ---------------------------------------------------------------------------
# Hub Key Vault data sources
# ---------------------------------------------------------------------------
# Reads hub connection values from the shared Key Vault created by the
# platform Terraform (estabilis-platform/providers/azure/shared.tf).
#
# When hub_key_vault_name is set, these data sources are activated and
# their values take precedence over the manual hub_* variables in
# variables.tf. When hub_key_vault_name is empty, the data sources are
# skipped and the manual variables are used as fallback.
#
# This enables two workflows:
#   1. CI/CD: workload TF reads from KV via managed identity (zero manual input)
#   2. Operator: can still set hub_* vars manually in tfvars (legacy/debug)
#
# See: estabilis-platform-tools issue #68

locals {
  hub_kv_enabled = var.hub_key_vault_name != "" && var.hub_registration_enabled
}

data "azurerm_key_vault" "hub" {
  count               = local.hub_kv_enabled ? 1 : 0
  name                = var.hub_key_vault_name
  resource_group_name = var.hub_key_vault_rg
}

data "azurerm_key_vault_secret" "hub_api_server_url" {
  count        = local.hub_kv_enabled ? 1 : 0
  name         = "hub-api-server-url"
  key_vault_id = data.azurerm_key_vault.hub[0].id
}

data "azurerm_key_vault_secret" "hub_ca_certificate" {
  count        = local.hub_kv_enabled ? 1 : 0
  name         = "hub-ca-certificate"
  key_vault_id = data.azurerm_key_vault.hub[0].id
}

data "azurerm_key_vault_secret" "hub_registrar_token" {
  count        = local.hub_kv_enabled ? 1 : 0
  name         = "hub-registrar-token"
  key_vault_id = data.azurerm_key_vault.hub[0].id
}

# Only read when the effective apiServerAccess mode is "allowlist" — in the
# private/peered topology the platform no longer writes this secret at all
# (estabilis-platform shared.tf), so reading it unconditionally would fail.
data "azurerm_key_vault_secret" "hub_egress_ip" {
  count        = local.hub_kv_enabled && local.hub_registration_access_mode == "allowlist" ? 1 : 0
  name         = "hub-egress-ip"
  key_vault_id = data.azurerm_key_vault.hub[0].id
}

# ---------------------------------------------------------------------------
# Resolved hub values — KV preferred, manual tfvars as fallback
# ---------------------------------------------------------------------------

locals {
  hub_api_server = (
    local.hub_kv_enabled && length(data.azurerm_key_vault_secret.hub_api_server_url) > 0
    ? data.azurerm_key_vault_secret.hub_api_server_url[0].value
    : var.hub_api_server_url
  )
  hub_ca_cert = (
    local.hub_kv_enabled && length(data.azurerm_key_vault_secret.hub_ca_certificate) > 0
    ? data.azurerm_key_vault_secret.hub_ca_certificate[0].value
    : var.hub_ca_certificate
  )
  hub_token = (
    local.hub_kv_enabled && length(data.azurerm_key_vault_secret.hub_registrar_token) > 0
    ? data.azurerm_key_vault_secret.hub_registrar_token[0].value
    : var.hub_registrar_token
  )
  hub_egress = (
    local.hub_kv_enabled && length(data.azurerm_key_vault_secret.hub_egress_ip) > 0
    ? data.azurerm_key_vault_secret.hub_egress_ip[0].value
    : var.hub_egress_ip
  )
}
