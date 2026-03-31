# ---------------------------------------------------------------------------
# ArgoCD Access — ServiceAccount + RBAC for platform ArgoCD
# ---------------------------------------------------------------------------
# The platform's ArgoCD needs access to this workload cluster to deploy
# and manage applications. This creates a ServiceAccount with a long-lived
# token that the platform uses as bearerToken in the ArgoCD Cluster Secret.
#
# The outputs (api_server_url, ca_certificate, argocd_token) are used by
# `estabilis workload register` to create the Cluster Secret on the platform.
# ---------------------------------------------------------------------------

# Kubernetes provider configured from AKS credentials
# Uses kube_admin_config when AAD is enabled (kube_config switches to AAD auth
# which doesn't provide client_certificate/client_key for the TF provider)
locals {
  kube_config = var.aad_managed_enabled ? azurerm_kubernetes_cluster.workload.kube_admin_config[0] : azurerm_kubernetes_cluster.workload.kube_config[0]
}

provider "kubernetes" {
  host                   = local.kube_config.host
  client_certificate     = base64decode(local.kube_config.client_certificate)
  client_key             = base64decode(local.kube_config.client_key)
  cluster_ca_certificate = base64decode(local.kube_config.cluster_ca_certificate)
}

provider "kubernetes" {
  alias                  = "hub"
  host                   = local.hub_api_server
  token                  = local.hub_token
  cluster_ca_certificate = local.hub_ca_cert != "" ? base64decode(local.hub_ca_cert) : ""
}

resource "kubernetes_namespace_v1" "argocd_access" {
  metadata {
    name = "estabilis-system"
    labels = {
      "estabilis.io/managed-by" = "workload"
    }
  }

  # BYO CNI: wait for Cilium to be ready before creating K8s resources
  depends_on = [helm_release.cilium]
}

resource "kubernetes_service_account_v1" "argocd" {
  metadata {
    name      = "platform-argocd"
    namespace = kubernetes_namespace_v1.argocd_access.metadata[0].name
    labels = {
      "estabilis.io/managed-by" = "workload"
      "estabilis.io/purpose"    = "platform-argocd-access"
    }
  }
}

resource "kubernetes_cluster_role_binding_v1" "argocd" {
  metadata {
    name = "platform-argocd-admin"
    labels = {
      "estabilis.io/managed-by" = "workload"
      "estabilis.io/purpose"    = "platform-argocd-access"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.argocd.metadata[0].name
    namespace = kubernetes_namespace_v1.argocd_access.metadata[0].name
  }
}

# Long-lived token for ArgoCD cluster registration
resource "kubernetes_secret_v1" "argocd_token" {
  metadata {
    name      = "platform-argocd-token"
    namespace = kubernetes_namespace_v1.argocd_access.metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account_v1.argocd.metadata[0].name
    }
    labels = {
      "estabilis.io/managed-by" = "workload"
      "estabilis.io/purpose"    = "platform-argocd-access"
    }
  }

  type = "kubernetes.io/service-account-token"
}
