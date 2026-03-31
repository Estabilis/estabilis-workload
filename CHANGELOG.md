# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
