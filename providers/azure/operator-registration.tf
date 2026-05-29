# ---------------------------------------------------------------------------
# Operator Registration — Workload Operator
#
# Creates a Service Principal with minimal scope on this AKS cluster for the
# Operator to call the Azure ARM API (add/remove authorized_ip_ranges).
# Then registers this cluster in the platform hub via WorkloadCluster CRD.
#
# Enable with: hub_registration_enabled = true
# Required variables: hub_api_server_url, hub_registrar_token
#   (hub_egress_ip is required ONLY when the effective apiServerAccess mode is
#    "allowlist" — i.e. a public-API-server workload cluster.)
#
# NETWORK PREREQUISITE (no code can substitute this): the `kubernetes.hub`
# provider must be able to reach the platform hub's API server during
# `terraform apply`. For a PRIVATE hub the apply host needs line-of-sight to
# the hub private endpoint — a jumpbox / VPN / self-hosted agent inside (or
# peered to) the hub VNet, plus DNS resolution of the hub
# privatelink.<region>.azmk8s.io FQDN. Running apply from an unpeered network
# will hang/fail on the kubernetes.hub resources.
# ---------------------------------------------------------------------------

locals {
  # Effective apiServerAccess.mode emitted on the WorkloadCluster CR. Auto
  # derives from the cluster topology (private cluster => "private") unless an
  # explicit override is set. Mirrors the operator contract (>= v0.8.0).
  hub_registration_access_mode = (
    var.hub_registration_api_server_access_mode != ""
    ? var.hub_registration_api_server_access_mode
    : (var.enable_private_cluster ? "private" : "allowlist")
  )
}

resource "azuread_application" "workload_operator" {
  count        = var.hub_registration_enabled ? 1 : 0
  display_name = "sp-${local.base_name}-workload-operator"
}

resource "azuread_service_principal" "workload_operator" {
  count     = var.hub_registration_enabled ? 1 : 0
  client_id = azuread_application.workload_operator[0].client_id
}

resource "azuread_service_principal_password" "workload_operator" {
  count                = var.hub_registration_enabled ? 1 : 0
  service_principal_id = azuread_service_principal.workload_operator[0].id
}

resource "azurerm_role_assignment" "workload_operator_aks" {
  count                = var.hub_registration_enabled ? 1 : 0
  scope                = azurerm_kubernetes_cluster.workload.id
  role_definition_name = "Azure Kubernetes Service Contributor Role"
  principal_id         = azuread_service_principal.workload_operator[0].object_id
}

# The operator reads spec.bearerToken as the NAME of a Secret in the SAME
# namespace as the WorkloadCluster CR (hub/estabilis-system). The actual
# ServiceAccount token lives on the workload cluster, so we copy it over to
# the hub here before creating the CR.
resource "kubernetes_secret_v1" "hub_workload_token" {
  count    = var.hub_registration_enabled ? 1 : 0
  provider = kubernetes.hub

  metadata {
    name      = "workload-${local.base_name}-token"
    namespace = "estabilis-system"
    labels = {
      "estabilis.io/managed-by"       = "workload-terraform"
      "estabilis.io/workload-cluster" = local.base_name
      "estabilis.io/purpose"          = "argocd-bearer-token"
    }
  }

  type = "Opaque"

  data = {
    token = kubernetes_secret_v1.argocd_token.data["token"]
  }
}

resource "kubernetes_manifest" "workload_registration" {
  count    = var.hub_registration_enabled ? 1 : 0
  provider = kubernetes.hub

  manifest = {
    apiVersion = "estabilis.io/v1alpha1"
    kind       = "WorkloadCluster"
    metadata = {
      name      = local.base_name
      namespace = "estabilis-system"
    }
    spec = {
      name          = local.base_name
      cloud         = "azure"
      apiServerUrl  = azurerm_kubernetes_cluster.workload.kube_config[0].host
      caCertificate = azurerm_kubernetes_cluster.workload.kube_config[0].cluster_ca_certificate
      bearerToken   = kubernetes_secret_v1.hub_workload_token[0].metadata[0].name
      # apiServerAccess (operator contract >= v0.8.0). hubEgressIp is emitted
      # ONLY in allowlist mode; private/none omit it entirely so the operator
      # never builds a malformed "/32".
      apiServerAccess = merge(
        { mode = local.hub_registration_access_mode },
        local.hub_registration_access_mode == "allowlist" ? { hubEgressIp = local.hub_egress } : {}
      )
      bridgeSecretRef = {
        name      = kubernetes_secret_v1.bridge[0].metadata[0].name
        namespace = kubernetes_secret_v1.bridge[0].metadata[0].namespace
      }
      azure = {
        subscriptionId = var.subscription_id
        resourceGroup  = azurerm_resource_group.workload.name
        aksClusterName = azurerm_kubernetes_cluster.workload.name
        tenantId       = var.tenant_id
        clientId       = azuread_application.workload_operator[0].client_id
        clientSecret   = azuread_service_principal_password.workload_operator[0].value
      }
    }
  }

  depends_on = [
    azurerm_kubernetes_cluster.workload,
    azurerm_kubernetes_cluster_node_pool.workload_spot,
    azurerm_kubernetes_cluster_node_pool.workload_regular,
    azurerm_role_assignment.workload_operator_aks,
    kubernetes_secret_v1.hub_workload_token,
    kubernetes_secret_v1.bridge,
  ]

  lifecycle {
    precondition {
      condition     = local.hub_registration_access_mode != "allowlist" || local.hub_egress != ""
      error_message = "apiServerAccess mode 'allowlist' requires a non-empty hub egress IP. Set hub_egress_ip, or populate the hub Key Vault 'hub-egress-ip' secret, or use mode 'private'/'none'."
    }
  }
}
