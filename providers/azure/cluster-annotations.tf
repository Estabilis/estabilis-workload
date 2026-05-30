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
    "internal-domain"            = var.internal_domain
    "deployment-id"              = var.deployment_id
    # v3.0.0 platform-parity: when deployment_id is set, compose cluster-name
    # as ${name_prefix}-${deployment_id} (matches platform module convention).
    # When empty, fall back to the AKS resource name (legacy behavior).
    "cluster-name"       = var.deployment_id != "" ? "${var.name_prefix}-${var.deployment_id}" : azurerm_kubernetes_cluster.workload.name
    "hub-cluster-name"   = local.hub_cluster_name
    "cloudflare-zone-id" = var.domain != "" && var.dns_provider == "cloudflare" ? var.cloudflare_zone_id : ""
    "letsencrypt-email"  = var.letsencrypt_email
    # Observability endpoint domain for the workload's Alloy (loki/mimir
    # remote_write). The gitops alloy template builds the URL as
    # mimir.{hub-cluster-name}.{hub-telemetry-domain}/... so the routing
    # decision (private split-horizon vs public) is made HERE, in TF, and the
    # template stays logic-free. Internal requested but no internal_domain set
    # → fall back to the public domain (avoids an empty-domain "mimir.." URL).
    "hub-telemetry-domain" = var.telemetry_use_internal && var.internal_domain != "" ? var.internal_domain : var.domain
    # Internal external-dns (split-horizon) — the gitops external-dns-internal
    # ApplicationSet consumes these. Empty when disabled → operator drops the
    # annotations and the per-cluster gate label stays off. The PDZ may live in
    # a different RG/subscription (the hub's), so both are derived from the zone
    # ARM ID: /subscriptions/<sub>/resourceGroups/<rg>/providers/.../privateDnsZones/<zone>
    "external-dns-internal-enabled"   = tostring(local.external_dns_internal_enabled)
    "external-dns-internal-client-id" = local.external_dns_internal_enabled ? azurerm_user_assigned_identity.external_dns_internal[0].client_id : ""
    "internal-dns-resource-group"     = var.internal_dns_zone_id != "" ? element(split("/", var.internal_dns_zone_id), 4) : ""
    "internal-dns-subscription-id"    = var.internal_dns_zone_id != "" ? element(split("/", var.internal_dns_zone_id), 2) : ""
    # ADR 0014 — exposure JSON as bridge data (non-sensitive configuration).
    # Operator stamps as annotation; ApplicationSet goTemplate reads it.
    # base64-encoded because helm --set-string can't handle raw JSON
    # (curly braces and commas are metacharacters). Same encoding as the
    # CLI uses on the hub — the child chart decodes with b64dec.
    "traefik-enabled"          = tostring(var.traefik_enabled)
    "traefik-internal-enabled" = tostring(var.traefik_internal_enabled)
    # Fixed ILB IP for traefik-internal (NVA/FortiGate topology). Empty in the
    # NAT-Gateway topology → operator drops the annotation → ILB stays dynamic.
    "traefik-internal-lb-ip" = var.traefik_internal_lb_ip
    "hubble-ui-exposures"    = base64encode(jsonencode({ for k, v in local.hubble_ui_exposures_resolved : k => v if v.enabled }))
  }
}
