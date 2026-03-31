# ---------------------------------------------------------------------------
# Operator Registration — Workload Operator
#
# Creates a Service Principal with minimal scope on this AKS cluster for the
# Operator to call the Azure ARM API (add/remove authorized_ip_ranges).
# Then registers this cluster in the platform hub via WorkloadCluster CRD.
#
# Enable with: hub_registration_enabled = true
# Required variables: hub_api_server_url, hub_registrar_token, hub_egress_ip
# ---------------------------------------------------------------------------

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
      hubEgressIp   = local.hub_egress
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
  ]
}
