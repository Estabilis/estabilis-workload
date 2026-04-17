# ---------------------------------------------------------------------------
# Bridge Secret — per-cluster values consumed by the workload-operator
# ---------------------------------------------------------------------------
# Workload Terraform emits Azure identifiers (tenant, keyvault URI, managed
# identity client IDs) into a Secret on the HUB. The WorkloadCluster CR
# (see operator-registration.tf) carries spec.bridgeSecretRef pointing at
# this Secret. The operator reads the Secret when reconciling the CR and
# stamps each data key as an `estabilis.io/bridge.<key>` annotation on the
# ArgoCD Cluster Secret it creates — atomically, no race.
#
# Previous implementation (kubernetes_annotations.cluster_secret_identity)
# was removed because it raced the operator: Terraform reached the annotate
# step while the Cluster Secret had not yet been created on the hub. See
# ADR 0010 §Hub side vs workload side for the pattern rationale.
# ---------------------------------------------------------------------------

resource "kubernetes_secret_v1" "bridge" {
  count    = var.hub_registration_enabled ? 1 : 0
  provider = kubernetes.hub

  metadata {
    name      = "bridge-${local.base_name}"
    namespace = "estabilis-system"
    labels = {
      # ADR 0003 §S4 (Terraform-emitted) — allowed identity labels
      "estabilis.io/managed-by"      = "platform"
      "estabilis.io/component"       = "workload-bridge"
      "estabilis.io/cluster-type"    = "workload"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  type = "Opaque"

  # Keys are kebab-case and become estabilis.io/bridge.<key> annotations on
  # the workload Cluster Secret. Registry lives in ADR 0010 §Registry.
  # Empty strings are filtered out by the operator so disabled features
  # (e.g., keyvault_enabled=false) do not produce misleading annotations.
  data = {
    "tenant-id"                  = var.tenant_id
    "subscription-id"            = var.subscription_id
    "resource-group"             = azurerm_resource_group.workload.name
    "keyvault-uri"               = var.keyvault_enabled ? azurerm_key_vault.workload[0].vault_uri : ""
    "external-secrets-client-id" = var.keyvault_enabled ? azurerm_user_assigned_identity.external_secrets[0].client_id : ""
    "cert-manager-client-id"     = var.domain != "" ? azurerm_user_assigned_identity.cert_manager[0].client_id : ""
    "external-dns-client-id"     = var.domain != "" && var.dns_provider == "azure" ? azurerm_user_assigned_identity.external_dns[0].client_id : ""
    "velero-client-id"           = var.velero_enabled ? azurerm_user_assigned_identity.velero[0].client_id : ""
    "dns-provider"               = var.domain != "" ? var.dns_provider : ""
    "domain"                     = var.domain
    "cloudflare-zone-id"         = var.domain != "" && var.dns_provider == "cloudflare" ? var.cloudflare_zone_id : ""
    "letsencrypt-email"          = var.letsencrypt_email
  }
}
