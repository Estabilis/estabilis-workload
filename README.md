# Estabilis Workload

Terraform module for provisioning **Azure Kubernetes Service (AKS) workload clusters** as part of the [Estabilis Platform](https://github.com/Estabilis/estabilis-platform). A workload cluster is where client applications run, managed remotely by the platform hub's ArgoCD.

## Architecture

```
Platform Hub (estabilis-platform)
  |
  |-- ArgoCD manages workload clusters remotely
  |-- Observability (Grafana stack) collects metrics/logs from workloads
  |
Workload Cluster (this module)
  |-- AKS with configurable node pools
  |-- Cilium CNI (optional)
  |-- NAT Gateway for static outbound IP
  |-- Key Vault, ACR, Storage (Velero, tfstate, cost export)
  |-- Workload Identity (managed identities for platform components)
  |-- Auto-registration with platform hub
```

## Features

| Feature | Toggle | Default |
|---------|--------|---------|
| AKS cluster | always | Kubernetes 1.34, Azure RBAC |
| System node pool | always | 3x B2s, ephemeral OS disk |
| Workload node pool (regular) | `workload_regular_enabled` | `false` |
| Workload node pool (spot) | `workload_spot_enabled` | `false` |
| NAT Gateway (static outbound IP) | `nat_gateway_enabled` | `true` |
| Container networking | `network_dataplane` | `default` (Azure CNI) |
| Cilium (managed) | `network_dataplane = "cilium"` | — |
| Cilium + Hubble (ACNS) | `network_dataplane = "cilium-acns"` | — |
| Cilium (BYO CNI) | `network_dataplane = "byo-cni"` | — |
| Key Vault | `keyvault_enabled` | `true` |
| Azure Container Registry | `acr_enabled` | `false` |
| ACR public registry cache | `acr_cache_enabled` | `true` |
| Velero backup storage | `velero_enabled` | `true` |
| Cost export (OpenCost) | `cost_export_enabled` | `true` |
| Diagnostics (Log Analytics) | `diagnostics_enabled` | `true` |
| Firewall on resources | `firewall_enabled` | `true` |
| Hub registration | `hub_registration_enabled` | `false` |
| DNS zone | `domain` | `""` (disabled) |
| Resource locks | `storage_protect_critical` | `false` |

## Prerequisites

| Tool | Version |
|------|---------|
| [Terraform](https://developer.hashicorp.com/terraform/install) | >= 1.7.0 |
| [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) | >= 2.50 |

Required Azure resource providers (registered automatically or via `estabilis register-providers`):

- `Microsoft.ContainerService` (AKS)
- `Microsoft.Network` (VNet, NAT Gateway)
- `Microsoft.KeyVault`
- `Microsoft.Storage`
- `Microsoft.ContainerRegistry` (if ACR enabled)
- `Microsoft.OperationalInsights` (if diagnostics enabled)
- `Microsoft.CostManagement` (if cost export enabled)

## Quick Start

### 1. Clone and configure

```bash
cd providers/azure
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your subscription_id, tenant_id, environment
```

### 2. Authenticate and deploy

```bash
az login
az account set --subscription <subscription_id>

terraform init
terraform plan
terraform apply
```

### 3. Access the cluster

```bash
az aks get-credentials \
  --resource-group rg-<name_prefix>-workload-<env>-<location> \
  --name aks-<name_prefix>-workload-<env>-<location>
```

## Network Architecture

```
VNet: 10.1.0.0/16
  |-- Subnet (nodes):  10.1.0.0/22   (1022 IPs)
  |-- Subnet (pods):   10.1.4.0/22   (1022 IPs)
  |
Service CIDR:          172.17.0.0/16
Pod CIDR (overlay):    10.245.0.0/16
DNS Service IP:        172.17.0.10
```

All subnets have service endpoints for `Microsoft.KeyVault` and `Microsoft.Storage`.

## Container Networking Options

| Option | `network_dataplane` | Description | Cost |
|--------|---------------------|-------------|------|
| Azure CNI | `default` | Microsoft-managed CNI | Included |
| Cilium (managed) | `cilium` | Managed Cilium, no Hubble | Included |
| Cilium + ACNS | `cilium-acns` | Managed Cilium + Hubble + FQDN filtering | ~$70/mo |
| Cilium (BYO) | `byo-cni` | Bring-your-own Cilium via Helm | Included |

> **Warning**: Switching to `byo-cni` **destroys and recreates the cluster**. See `terraform.tfvars.example` for the two-step apply process.

## Hub Integration

When `hub_registration_enabled = true`, the module:

1. Creates a Service Principal for the platform's workload operator
2. Reads hub connection values from the platform's shared Key Vault
3. Creates a `WorkloadCluster` custom resource on the hub
4. Annotates the ArgoCD cluster secret with per-cluster identity values

This allows the platform hub's ArgoCD to deploy baseline components (Kyverno, cert-manager, external-secrets, etc.) to the workload cluster automatically.

## Security

### Default posture

- Azure RBAC for Kubernetes authorization (`azure_rbac_enabled = true`)
- Azure AD managed integration (`aad_managed_enabled = true`)
- Run Command disabled (`run_command_enabled = false`)
- Firewall enabled on Key Vault, Storage, ACR
- Auto-detected operator IP added to all firewalls
- TLS 1.2 minimum on all storage accounts
- Shared access keys disabled on storage (`storage_use_azuread = true`)

### Hardening for production

```hcl
# Disable local Kubernetes certificates (Azure AD only)
local_account_disabled = true
aad_admin_group_ids    = ["<azure-ad-group-object-id>"]

# AKS API server access control
authorized_ip_ranges = ["<platform-nat-gateway-ip>/32"]

# Storage protection
storage_protect_critical = true
```

## Workload Identity

The module creates managed identities with federated credentials (OIDC) for platform components:

| Identity | Purpose | Federated |
|----------|---------|-----------|
| `external-secrets` | Read secrets from Key Vault | Yes |
| `velero` | Access backup storage | Yes |
| `external-dns` | Manage DNS records (if domain set) | Yes |
| `cert-manager` | TLS certificate validation (if domain set) | Yes |
| `acr-ci` | CI/CD push to ACR (if enabled) | Yes |

No shared secrets — all identities use OIDC federation via the AKS OIDC issuer.

## Naming Convention

All resources follow [Azure CAF naming](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming):

```
{type}-{name_prefix}-workload-{env_code}-{location}
```

Examples:
```
rg-estabilis-workload-hml-eastus2           # Resource Group
aks-estabilis-workload-hml-eastus2          # AKS Cluster
kv-estabilis-wkl-hml-a3b5c2                # Key Vault (compact)
stestabilishmltfs-a3b5c2                    # Storage (compact)
```

## Tags

All resources receive [Azure CAF tags](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-tagging). Empty values are automatically filtered out.

| Category | Tags |
|----------|------|
| Functional | `app`, `env`, `region`, `tier`, `managed-by` |
| Classification | `criticality`, `confidentiality`, `sla` |
| Accounting | `costcenter`, `department`, `budget` |
| Purpose | `businessprocess`, `businessimpact`, `revenueimpact` |
| Ownership | `opsteam`, `businessunit` |

## Downstream Usage

This module is consumed by per-client downstream repos (e.g., `estabilis-<client>-workload-azure-<region>-<env>`). Each downstream contains only `terraform.tfvars` and references this module.

## Related Repositories

| Repository | Description |
|------------|-------------|
| [estabilis-platform](https://github.com/Estabilis/estabilis-platform) | Platform hub — ArgoCD, Grafana stack, Kyverno, cert-manager |
| [estabilis-platform-gitops](https://github.com/Estabilis/estabilis-platform-gitops) | Helm charts for platform-root and workload-bootstrap |

## License

[Elastic License 2.0](LICENSE) — free to use, modify, and distribute. Cannot be offered as a managed service.
