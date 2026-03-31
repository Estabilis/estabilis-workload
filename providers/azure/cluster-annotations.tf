# ---------------------------------------------------------------------------
# Cluster Secret annotations — per-cluster identity values
# ---------------------------------------------------------------------------
# The ArgoCD Cluster Secret for this workload cluster (created by the
# estabilis-workload-operator from the WorkloadCluster CR) carries
# annotations that the workload-bootstrap ApplicationSets read via the
# cluster generator's {{metadata.annotations.xxx}} syntax.
#
# This is the industry-standard ArgoCD pattern for per-cluster configuration
# — no hub intermediary needed. See:
# https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Cluster/
# ---------------------------------------------------------------------------

resource "kubernetes_annotations" "cluster_secret_identity" {
  count       = var.hub_registration_enabled ? 1 : 0
  provider    = kubernetes.hub
  api_version = "v1"
  kind        = "Secret"

  metadata {
    name      = "cluster-${local.base_name}"
    namespace = "argocd"
  }

  # Keys use DASHES (not dots) because ArgoCD's ApplicationSet cluster
  # generator uses dot notation for path traversal. Dots in annotation
  # keys (e.g., estabilis.io/xxx) conflict with the path separator and
  # prevent template substitution from resolving.
  annotations = {
    "estabilis-tenant-id"                  = var.tenant_id
    "estabilis-keyvault-uri"               = var.keyvault_enabled ? azurerm_key_vault.workload[0].vault_uri : ""
    "estabilis-external-secrets-client-id"  = var.keyvault_enabled ? azurerm_user_assigned_identity.external_secrets[0].client_id : ""
    "estabilis-cert-manager-client-id"      = var.domain != "" ? azurerm_user_assigned_identity.cert_manager[0].client_id : ""
    "estabilis-external-dns-client-id"      = var.domain != "" ? azurerm_user_assigned_identity.external_dns[0].client_id : ""
    "estabilis-velero-client-id"            = var.velero_enabled ? azurerm_user_assigned_identity.velero[0].client_id : ""
  }

  # The Cluster Secret is created by the workload-operator AFTER
  # processing the WorkloadCluster CR. The depends_on ensures Terraform
  # waits for the CR to be applied before attempting to annotate.
  depends_on = [kubernetes_manifest.workload_registration]
}
