# ---------------------------------------------------------------------------
# Workload Identity — Managed Identities for platform components
# ---------------------------------------------------------------------------
# These identities are used by components that the platform's ArgoCD
# deploys into this workload cluster (External Secrets, Velero, cert-manager).
# ---------------------------------------------------------------------------

locals {
  aks_oidc_issuer_url = azurerm_kubernetes_cluster.workload.oidc_issuer_url
}

# ---------------------------------------------------------------------------
# External Secrets — reads secrets from Key Vault
# Requires: keyvault_enabled = true
# ---------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "external_secrets" {
  count               = var.keyvault_enabled ? 1 : 0
  name                = "mi-${local.base_name}-external-secrets"
  resource_group_name = azurerm_resource_group.workload.name
  location            = azurerm_resource_group.workload.location
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "external_secrets" {
  count                     = var.keyvault_enabled ? 1 : 0
  name                      = "fic-external-secrets"
  user_assigned_identity_id = azurerm_user_assigned_identity.external_secrets[0].id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = local.aks_oidc_issuer_url
  subject                   = "system:serviceaccount:external-secrets:external-secrets"
}

resource "azurerm_role_assignment" "external_secrets_kv_reader" {
  count                = var.keyvault_enabled ? 1 : 0
  scope                = azurerm_key_vault.workload[0].id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.external_secrets[0].principal_id
}

# ---------------------------------------------------------------------------
# Velero — backup storage access
# Requires: velero_enabled = true
# ---------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "velero" {
  count               = var.velero_enabled ? 1 : 0
  name                = "mi-${local.base_name}-velero"
  resource_group_name = azurerm_resource_group.workload.name
  location            = azurerm_resource_group.workload.location
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "velero" {
  count                     = var.velero_enabled ? 1 : 0
  name                      = "fic-velero"
  user_assigned_identity_id = azurerm_user_assigned_identity.velero[0].id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = local.aks_oidc_issuer_url
  subject                   = "system:serviceaccount:velero:velero-server"
}

resource "azurerm_role_assignment" "velero_storage_contributor" {
  count                = var.velero_enabled ? 1 : 0
  scope                = azurerm_storage_account.velero_backup[0].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.velero[0].principal_id
}

resource "azurerm_role_assignment" "velero_rg_reader" {
  count                = var.velero_enabled ? 1 : 0
  scope                = azurerm_resource_group.workload.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.velero[0].principal_id
}

resource "azurerm_role_assignment" "velero_disk_snapshot" {
  count                = var.velero_enabled ? 1 : 0
  scope                = azurerm_resource_group.workload.id
  role_definition_name = "Disk Snapshot Contributor"
  principal_id         = azurerm_user_assigned_identity.velero[0].principal_id
}

# ---------------------------------------------------------------------------
# External DNS — manages DNS records (optional, requires domain)
# ---------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "external_dns" {
  count               = var.domain != "" && var.dns_provider == "azure" ? 1 : 0
  name                = "mi-${local.base_name}-external-dns"
  resource_group_name = azurerm_resource_group.workload.name
  location            = azurerm_resource_group.workload.location
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "external_dns" {
  count                     = var.domain != "" && var.dns_provider == "azure" ? 1 : 0
  name                      = "fic-external-dns"
  user_assigned_identity_id = azurerm_user_assigned_identity.external_dns[0].id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = local.aks_oidc_issuer_url
  subject                   = "system:serviceaccount:external-dns:external-dns"
}

resource "azurerm_role_assignment" "external_dns_dns_contributor" {
  count                = var.domain != "" && var.dns_provider == "azure" ? 1 : 0
  scope                = azurerm_dns_zone.workload[0].id
  role_definition_name = "DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.external_dns[0].principal_id
}

# ---------------------------------------------------------------------------
# cert-manager — DNS validation for TLS certificates (optional)
# Only needed if workload has its own domain with DNS zone.
# ---------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "cert_manager" {
  count               = var.domain != "" ? 1 : 0
  name                = "mi-${local.base_name}-cert-manager"
  resource_group_name = azurerm_resource_group.workload.name
  location            = azurerm_resource_group.workload.location
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "cert_manager" {
  count                     = var.domain != "" ? 1 : 0
  name                      = "fic-cert-manager"
  user_assigned_identity_id = azurerm_user_assigned_identity.cert_manager[0].id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = local.aks_oidc_issuer_url
  subject                   = "system:serviceaccount:cert-manager:cert-manager"
}

# DNS zone is optional — only created when domain is set AND dns_provider=azure.
# When dns_provider=cloudflare the zone lives in Cloudflare (external); no
# Azure DNS resources are created. Cert-manager and external-dns authenticate
# via Cloudflare API token stored in the workload Key Vault.
resource "azurerm_dns_zone" "workload" {
  count               = var.domain != "" && var.dns_provider == "azure" ? 1 : 0
  name                = var.domain
  resource_group_name = azurerm_resource_group.workload.name
  tags                = local.tags
}

resource "azurerm_role_assignment" "cert_manager_dns_contributor" {
  count                = var.domain != "" && var.dns_provider == "azure" ? 1 : 0
  scope                = azurerm_dns_zone.workload[0].id
  role_definition_name = "DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.cert_manager[0].principal_id
}
