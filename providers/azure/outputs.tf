# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

# --- Cluster info ---

output "resource_group_name" {
  description = "Name of the workload resource group."
  value       = azurerm_resource_group.workload.name
}

output "aks_cluster_name" {
  description = "Name of the AKS cluster."
  value       = azurerm_kubernetes_cluster.workload.name
}

output "aks_oidc_issuer_url" {
  description = "OIDC issuer URL for workload identity federation."
  value       = azurerm_kubernetes_cluster.workload.oidc_issuer_url
}

# --- ArgoCD integration (used by `estabilis workload register`) ---

output "argocd_api_server_url" {
  description = "Kubernetes API server URL for ArgoCD cluster registration."
  value       = azurerm_kubernetes_cluster.workload.kube_config[0].host
  sensitive   = true
}

output "argocd_ca_certificate" {
  description = "Base64-encoded CA certificate for ArgoCD cluster registration."
  value       = azurerm_kubernetes_cluster.workload.kube_config[0].cluster_ca_certificate
  sensitive   = true
}

output "argocd_bearer_token" {
  description = "Bearer token for ArgoCD ServiceAccount on this workload cluster."
  value       = kubernetes_secret_v1.argocd_token.data["token"]
  sensitive   = true
}

# --- Key Vault ---

output "keyvault_name" {
  description = "Name of the Key Vault (empty if disabled)."
  value       = var.keyvault_enabled ? azurerm_key_vault.workload[0].name : ""
}

output "keyvault_uri" {
  description = "URI of the Key Vault (empty if disabled)."
  value       = var.keyvault_enabled ? azurerm_key_vault.workload[0].vault_uri : ""
}

# --- Storage ---

output "tfstate_storage_account_name" {
  description = "Storage account name for Terraform state backend."
  value       = azurerm_storage_account.tfstate.name
}

output "velero_backup_storage_account_name" {
  description = "Storage account name for Velero backups (empty if disabled)."
  value       = var.velero_enabled ? azurerm_storage_account.velero_backup[0].name : ""
}

output "velero_backup_container_name" {
  description = "Container name for Velero backups (empty if disabled)."
  value       = var.velero_enabled ? azurerm_storage_container.velero_backup[0].name : ""
}

# --- Workload Identity client IDs ---

output "external_secrets_client_id" {
  description = "Client ID of the external-secrets managed identity (empty if keyvault disabled)."
  value       = var.keyvault_enabled ? azurerm_user_assigned_identity.external_secrets[0].client_id : ""
}

output "velero_client_id" {
  description = "Client ID of the Velero managed identity (empty if velero disabled)."
  value       = var.velero_enabled ? azurerm_user_assigned_identity.velero[0].client_id : ""
}

output "external_dns_client_id" {
  description = "Client ID of the external-dns managed identity (empty if no domain or dns_provider=cloudflare)."
  value       = var.domain != "" && var.dns_provider == "azure" ? azurerm_user_assigned_identity.external_dns[0].client_id : ""
}

output "cert_manager_client_id" {
  description = "Client ID of the cert-manager managed identity (empty if no domain)."
  value       = var.domain != "" ? azurerm_user_assigned_identity.cert_manager[0].client_id : ""
}

# --- DNS ---

output "hubble_ui_exposures_json" {
  description = "Hubble UI exposures serialized as JSON (with auto-derived hosts applied)."
  value       = jsonencode({ for k, v in local.hubble_ui_exposures_resolved : k => v if v.enabled })
}

output "dns_zone_name" {
  description = "Name of the DNS zone (empty if no domain or dns_provider=cloudflare)."
  value       = var.domain != "" && var.dns_provider == "azure" ? azurerm_dns_zone.workload[0].name : ""
}

output "dns_zone_name_servers" {
  description = "Name servers for the DNS zone (empty if no domain or dns_provider=cloudflare)."
  value       = var.domain != "" && var.dns_provider == "azure" ? azurerm_dns_zone.workload[0].name_servers : []
}

# --- Cost export (for platform OpenCost) ---

output "cost_export_storage_account_name" {
  description = "Storage account name for cost exports (empty if disabled)."
  value       = var.cost_export_enabled ? azurerm_storage_account.cost_exports[0].name : ""
}

output "cost_export_container_name" {
  description = "Container name for cost exports (empty if disabled)."
  value       = var.cost_export_enabled ? azurerm_storage_container.cost_exports[0].name : ""
}

output "cost_export_storage_access_key" {
  description = "Access key for cost export storage (empty if disabled). Used by platform OpenCost."
  value       = var.cost_export_enabled ? azurerm_storage_account.cost_exports[0].primary_access_key : ""
  sensitive   = true
}

# --- Network (for VNet peering with platform) ---

output "vnet_id" {
  description = "Virtual Network ID (for VNet peering with platform cluster)."
  value       = azurerm_virtual_network.workload.id
}

output "vnet_name" {
  description = "Virtual Network name."
  value       = azurerm_virtual_network.workload.name
}

output "subnet_nodes_id" {
  description = "Subnet ID for AKS nodes (for private endpoints)."
  value       = azurerm_subnet.aks_nodes.id
}

# --- ACR ---

output "acr_login_server" {
  description = "ACR login server URL (empty if disabled)."
  value       = var.acr_enabled ? azurerm_container_registry.workload[0].login_server : ""
}

output "acr_name" {
  description = "ACR name (empty if disabled)."
  value       = var.acr_enabled ? azurerm_container_registry.workload[0].name : ""
}

output "acr_ci_client_id" {
  description = "Client ID of the CI/CD managed identity for ACR push. Use this to configure federated credentials in your CI/CD provider (empty if disabled)."
  value       = var.acr_enabled && var.acr_ci_identity_enabled ? azurerm_user_assigned_identity.acr_ci[0].client_id : ""
}

output "acr_ci_principal_id" {
  description = "Principal ID of the CI/CD managed identity (empty if disabled)."
  value       = var.acr_enabled && var.acr_ci_identity_enabled ? azurerm_user_assigned_identity.acr_ci[0].principal_id : ""
}

# --- NAT Gateway ---

output "nat_gateway_public_ip" {
  description = "Static outbound IP address (NAT Gateway)."
  value       = var.nat_gateway_enabled ? azurerm_public_ip.nat_gateway[0].ip_address : null
}

# --- Metadata (for platform registration) ---

output "subscription_id" {
  description = "Azure subscription ID of this workload."
  value       = var.subscription_id
  sensitive   = true
}

output "tenant_id" {
  description = "Azure tenant ID of this workload."
  value       = var.tenant_id
  sensitive   = true
}

output "location" {
  description = "Azure region where this workload is deployed."
  value       = var.location
}

output "name_prefix" {
  description = "Name prefix used for all resources."
  value       = var.name_prefix
}
