# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.1.1] - 2026-04-21

### Fixed — `terraform validate` rejects `cost-export.tf`

Same fix as `estabilis-platform` v0.12.1. `plantimestamp()` at
validate time resolves to `0001-01-01T00:00:00Z`; `formatdate("YYYY",
...)` returns `"1"`, `+ 10` yields `11`, final string is
`"11-01-01T00:00:00Z"` — rejected by the azurerm provider.

Replace with `formatdate("YYYY-MM-DD", timeadd(plantimestamp(),
"87600h"))` — well-formed RFC3339 under both validate and plan.

Unblocks PR validation on downstream consumers
(transfero-workload-azure-eastus2-hml, etc.).

## [1.0.0] - 2026-04-13

### Added

- AKS with system + optional workload node pools (regular and spot)
- Container networking: Azure CNI, Cilium managed, Cilium ACNS, BYO Cilium
- VNet with node and pod subnets, NSG, NAT Gateway
- Key Vault with RBAC and firewall
- Storage accounts: Terraform state, Velero backup, cost export
- Azure Container Registry with public registry cache
- Workload Identity for platform components (external-secrets, velero, external-dns, cert-manager)
- Hub registration for platform integration
- Hub Key Vault data sources for automated registration
- Per-cluster identity values annotated on ArgoCD Cluster Secret
- Diagnostics with Log Analytics
- Azure CAF naming convention and tagging
- DNS zone creation (optional)
- Resource locks on critical storage (optional)
- LICENSE (Elastic License 2.0)
- README, SECURITY, CHANGELOG documentation
