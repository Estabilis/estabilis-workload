# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.0.0] - 2026-05-28

### Added — BYO Network mode + Private Cluster + PE-only parity with `estabilis-platform`

21 new variables that unlock four orthogonal capabilities:

1. **BYO Network**: cluster can consume VNet/subnet/NAT GW provisioned by another
   Terraform repo (separation of concerns network ≠ workload). New variables:
   `network_existing_enabled`, `existing_vnet_id`, `existing_vnet_name`,
   `existing_vnet_resource_group_name`, `existing_subnet_nodes_id`,
   `existing_subnet_pods_id`, `external_nat_gateway_egress_ips`, `outbound_type`.

2. **Naming per domain**: `workload_domain` replaces hardcoded `"workload"` in
   `base_name`. Enables multi-cluster-per-region setups (one cluster per
   business domain, e.g. `payments`, `analytics`, `search`) with distinct
   names. Default `"workload"` preserves backward compat.

3. **Private cluster + UAMI**: parity with `estabilis-platform`. API server via
   PE, PDZ canonical from hub, UAMI with Private DNS Zone Contributor. New
   variables: `enable_private_cluster`, `private_dns_zone_id`,
   `private_cluster_public_fqdn_enabled`.

4. **PE-only PaaS (granular)**: 4 separate toggles + 3 external PDZ IDs. Each
   `*_private_endpoint_enabled` creates a dedicated PE on the local AKS nodes
   subnet. New variables: `keyvault_private_endpoint_enabled`,
   `tfstate_private_endpoint_enabled`, `velero_private_endpoint_enabled`,
   `cost_exports_private_endpoint_enabled`, `external_pdz_blob_id`,
   `external_pdz_vaultcore_id`, `external_pdz_acr_id`.

5. **External LAW (additive)**: diagnostic setting added (not replaced)
   pointing to a central LAW (e.g. cross-region observability bootstrap). New
   variable: `external_log_analytics_workspace_id`.

6. **`workload_regular_min_count`**: parity with platform — controls scale
   floor of the regular workload pool.

7. **`shared_hub_secrets_prefix`**: reserved for future use (hub KV secret
   namespacing per env).

### Added — Azure CNI Pod Subnet support (opt-in)

New variable `network_plugin_mode` (default `"overlay"`) controls Azure CNI
plugin mode. Valid values:

- `"overlay"` (default) — Azure CNI Overlay. Pods allocated from `pod_cidr`
  (RFC1918 private overlay range, no VNet IP consumption). Single nodes
  subnet. Backward-compatible with v2.x behavior.
- `"pod-subnet"` — Azure CNI Pod Subnet (flat networking, GA per Microsoft
  Learn 2026-05-13). Pods receive routable VNet IPs from a **dedicated pods
  subnet** (`subnet_pods_prefix` in auto-VNet mode, or `existing_subnet_pods_id`
  in BYO Network mode). Required when downstream consumers need pod IPs
  reachable across peerings or NVA inspection.
- `null` — only when `network_dataplane = "byo-cni"` (BYO CNI ignores plugin
  mode entirely).

**Translation to provider**: the variable is enum-descriptive; the module
translates internally to the value `azurerm` provider 4.x accepts:
`"overlay"` → `"overlay"`, `"pod-subnet"` → `null` (the value the azurerm
AKS resource interprets as "Azure CNI flat / Pod Subnet mode"),
`network_dataplane=="byo-cni"` → `null`.

**Wiring**: `pod_subnet_id` is now passed to `default_node_pool` and both
extra node pools (`workload_regular`, `workload_spot`), gated to only
populate when `network_plugin_mode == "pod-subnet"` AND
`local.subnet_pods_id != ""`. Otherwise `null` (preserves current state).

**Precondition** added to the AKS cluster: `network_plugin_mode = "pod-subnet"`
requires a non-empty pods subnet (auto-VNet `subnet_pods_prefix` or BYO
`existing_subnet_pods_id`). Caught at plan time, not apply.

**Backward compat**: default `"overlay"` preserves the v2.x behavior
(hardcoded `"overlay"` previously in `aks.tf`). Existing consumers see
zero diff. Only consumers flipping to `"pod-subnet"` get a non-empty
`pod_subnet_id` on their node pools (in-place node-pool cycling per provider
behavior — not cluster recreate).

### Changed — BREAKING — `network_dataplane` default flipped to `cilium-acns`

Previously defaulted to `"default"` (Azure CNI cru, no Cilium, no Hubble).
Now defaults to `"cilium-acns"` (Cilium dataplane + ACNS observability +
ACNS security via FQDN filtering).

**Impact**:
- Existing consumers that DID NOT set `network_dataplane` explicitly will
  see the cluster **destroyed and recreated** on apply (AKS does not allow
  changing `network_data_plane` in-place from `azure` to `cilium`).
- Consumers that already set `network_dataplane = "cilium-acns"` explicitly
  in their tfvars are unaffected.
- To preserve legacy behavior, set explicitly: `network_dataplane = "default"`.

**Why**: ACNS is the standard for Estabilis-managed clusters
(Hubble flow logs + metrics + FQDN-based NetworkPolicies). Greenfield
clusters should opt-in by default, not opt-out.

### Added — Platform parity: `internal_domain` + `deployment_id`

Two new variables align the workload module with `estabilis-platform`
(host derivation + GitOps cluster identity):

- `internal_domain` (string, default `""`) — split-horizon DNS. When set,
  `hubble_ui_exposures` entries keyed `"internal"` derive their host as
  `{app}.{cluster_name}.{internal_domain}` instead of
  `{...}.{domain}`. Enables an internal-only subdomain (e.g.
  `internal.example.com`) separated from the public domain.
  Empty (default) preserves prior behavior — all exposures use `var.domain`.
  Explicit `host = "..."` in an exposure entry always wins over derivation.
- `deployment_id` (string, default `""`) — unique identifier of this
  workload deployment (e.g. `{domain}-azure-{region}-{env}`). When set,
  the bridge Secret emits `cluster-name = "$${name_prefix}-$${deployment_id}"`
  (parity with platform's `deployment_id`-based naming). When empty
  (default), `cluster-name` falls back to the AKS resource name (legacy
  behavior — current default). The `deployment-id` and `internal-domain`
  values are emitted as bridge data keys so the workload-operator stamps
  them on the ArgoCD Cluster Secret for ApplicationSets to consume.

### Changed — Default Kubernetes version bumped to 1.35

`kubernetes_version` default `"1.34"` → `"1.35"`. Aligns the
greenfield default with the `estabilis-platform` recommended version.
Existing consumers pinning explicitly in tfvars are unaffected
(no diff in plan). Greenfield consumers (no `kubernetes_version` in
tfvars) will see an in-place version upgrade on next apply — AKS
performs a rolling node-pool upgrade respecting the configured
maintenance window and `max_surge`.

### Added — `traefik_internal_enabled` (parity with `estabilis-platform`)

New variable `traefik_internal_enabled` (bool, default `false`) deploys a
second Traefik ingress controller in internal mode (Azure Internal Load
Balancer, no Public IP). Use cases:

- Workload behind an NVA (FortiGate) where ingress only via DNAT
- Apps reachable only from peered VNets (private peering pattern)
- Coexists with `traefik_enabled = true` — two ingress classes available
  on the same cluster: `traefik` (public) + `traefik-internal` (ILB)

Implementation:
- NSG ingress rules (443/80) now gated by
  `traefik_enabled || traefik_internal_enabled` (either toggle opens NSG).
- Bridge Secret emits `traefik-internal-enabled` key — the
  `workload-operator` stamps it as an annotation on the ArgoCD Cluster
  Secret; the gitops ApplicationSet reads it to decide whether to deploy
  the second Traefik chart.

Defaults preserved: backward-compat unchanged for consumers that don't
set this var.

### Added — ACNS observability/security toggles

Two new variables expose previously-hardcoded ACNS knobs:

- `acns_observability_enabled` (bool, default `true`) — Hubble flow logs +
  metrics. Disable to drop ~30% of ACNS cost when only FQDN filtering
  matters.
- `acns_security_enabled` (bool, default `true`) — Cilium FQDN-based
  NetworkPolicy enforcement. Disable for pure observability deployments.

Both apply only when `network_dataplane = "cilium-acns"`. Defaults preserve
prior behavior (always-on). Note: `estabilis-platform` v0.61.4 does NOT
expose these — workload is intentionally ahead here.

### Diagnostic Settings — full coverage (parity with `estabilis-platform`)

Previously only AKS shipped logs/metrics to LAW (local + external). The
remaining PaaS resources (ACR, Key Vault, all storage accounts) were
invisible to both workspaces. Five additional dual pairs were added,
mirroring the platform module's `diagnostics.tf` pattern (local + external,
each one gated by its feature toggle plus `diagnostics_enabled` /
`external_law_enabled` respectively):

| Resource             | Local resource                                       | External resource                                       | Categories                                                                       | Gate (local)                              | Gate (external)                       |
| -------------------- | ---------------------------------------------------- | ------------------------------------------------------- | -------------------------------------------------------------------------------- | ----------------------------------------- | ------------------------------------- |
| Key Vault            | `azurerm_monitor_diagnostic_setting.keyvault_local`  | `azurerm_monitor_diagnostic_setting.keyvault_external`  | `AuditEvent`, `AzurePolicyEvaluationDetails` + `AllMetrics`                      | `diagnostics_enabled && keyvault_enabled` | `external_law_enabled && keyvault_enabled` |
| Storage — TFState    | `azurerm_monitor_diagnostic_setting.sa_tfstate_local`| `azurerm_monitor_diagnostic_setting.sa_tfstate_external`| `StorageRead`, `StorageWrite`, `StorageDelete` + `Transaction`                   | `diagnostics_enabled` (sempre criado)     | `external_law_enabled`                |
| Storage — Velero     | `azurerm_monitor_diagnostic_setting.sa_velero_local` | `azurerm_monitor_diagnostic_setting.sa_velero_external` | `StorageRead`, `StorageWrite`, `StorageDelete` + `Transaction`                   | `diagnostics_enabled && velero_enabled`   | `external_law_enabled && velero_enabled` |
| Storage — Cost       | `azurerm_monitor_diagnostic_setting.sa_cost_local`   | `azurerm_monitor_diagnostic_setting.sa_cost_external`   | `StorageRead`, `StorageWrite`, `StorageDelete` + `Transaction`                   | `diagnostics_enabled && cost_export_enabled` | `external_law_enabled && cost_export_enabled` |
| ACR                  | `azurerm_monitor_diagnostic_setting.acr_local`       | `azurerm_monitor_diagnostic_setting.acr_external`       | `ContainerRegistryRepositoryEvents`, `ContainerRegistryLoginEvents` + `AllMetrics` | `diagnostics_enabled && acr_enabled`     | `external_law_enabled && acr_enabled` |

No new input variables — every pair gates on existing toggles
(`diagnostics_enabled`, `keyvault_enabled`, `velero_enabled`,
`cost_export_enabled`, `acr_enabled`, `external_log_analytics_workspace_id`).

Notes:
- `_external` resources gate ONLY on `external_law_enabled` (do NOT require
  `diagnostics_enabled`) — supports external-only mode where the local LAW
  is intentionally skipped to save cost while keeping audit shipped to a
  central workspace.
- AKS pair gained `AllMetrics` on the external side (platform parity);
  local-side AKS keeps existing category list to avoid drift on existing
  consumers.

Delta in resource count: **+10** `azurerm_monitor_diagnostic_setting`
(was 2 → now 12) when ALL toggles are on and `external_law_enabled = true`.
Existing consumers (no `external_log_analytics_workspace_id`, ACR/Velero/Cost
off) see only the new `keyvault_local` + `sa_tfstate_local`: **+2 resources**
on apply, both no-op safe.

### Added — Diagnostic category customization (operator-tunable)

Previously the `enabled_log` and `enabled_metric` categories on all 12
`azurerm_monitor_diagnostic_setting` resources were hardcoded literals.
Operators needing additional categories (e.g., `kube-apiserver` in the
local LAW for offline troubleshooting, or `Capacity` metrics on storage)
had to fork the upstream.

10 new variables expose category lists:

| Resource type | Logs var (shared local+external) | Metrics var | Notes |
|---|---|---|---|
| AKS | `aks_diagnostic_log_categories` + `aks_diagnostic_log_categories_external_extra` | `aks_diagnostic_metric_categories` (external) + `aks_diagnostic_metric_categories_local` | Splits external-extra to preserve current behavior of sending heavyweight `kube-apiserver` only to central LAW |
| Key Vault | `keyvault_diagnostic_log_categories` | `keyvault_diagnostic_metric_categories` | Shared local+external |
| Storage (tfstate + velero + cost) | `storage_diagnostic_log_categories` | `storage_diagnostic_metric_categories` | One pair drives all 3 SAs (homogeneous schema) |
| ACR | `acr_diagnostic_log_categories` | `acr_diagnostic_metric_categories` | Shared local+external |

Defaults preserve prior categories — zero diff in plan for existing
consumers. To extend, override in tfvars:

```hcl
aks_diagnostic_log_categories = [
  "kube-audit-admin", "kube-controller-manager", "kube-scheduler",
  "cluster-autoscaler", "guard",
  "csi-azuredisk-controller",  # operator-added
]
```

Implementation: each resource now uses `dynamic "enabled_log"` /
`dynamic "enabled_metric"` blocks iterating over `toset(var.*)`. Lists
are deduplicated via `toset()` so accidental repetition in tfvars is
harmless.

### Validation rigorous (`precondition` blocks)

- `enable_private_cluster=true` requires `private_dns_zone_id != ""`.
- `outbound_type=userDefinedRouting` requires `network_existing_enabled=true`
  (UDR with `0.0.0.0/0` must be owned by the external network repo).
- `outbound_type=userAssignedNATGateway` requires `nat_gateway_enabled=true`
  OR `network_existing_enabled=true` (external NAT GW via
  `external_nat_gateway_egress_ips`).
- Each `*_private_endpoint_enabled` requires the corresponding
  `external_pdz_*_id`.

### Changed — Providers exact-pinned (was `~> X.Y`)

| Provider                  | Was         | Now      |
| ------------------------- | ----------- | -------- |
| `hashicorp/azurerm`       | `~> 4.0`    | `4.68.0` |
| `hashicorp/azuread`       | `~> 3.0`    | `3.8.0`  |
| `hashicorp/http`          | `~> 3.4`    | `3.5.0`  |
| `hashicorp/random`        | `~> 3.6`    | `3.8.1`  |
| `hashicorp/time`          | `~> 0.12`   | `0.13.1` |
| `hashicorp/helm`          | `~> 2.17`   | `2.17.0` |
| `hashicorp/kubernetes`    | `~> 2.37`   | `2.38.0` |

### Upgrade path (IMPORTANT — read before bumping production)

Defaults preserve current behavior (all new variables have safe defaults).
BUT:

- **Bumping v2.x → v3.0.0 WITHOUT changing tfvars** triggers replacement of
  `azurerm_virtual_network.workload`, `azurerm_subnet.aks_nodes`,
  `azurerm_subnet.aks_pods`, `azurerm_network_security_group.aks_nodes`, NAT
  GW + associations — because the `count = var.network_existing_enabled ? 0 : 1`
  gate changes the resource address (`workload` → `workload[0]`). No
  `moved {}` blocks are included in this release. Use `moved {}` manually
  OR `terraform state mv` OR DO NOT bump in production until §"Upgrade path
  hardening" lands.
- **Greenfield consumers**: bump directly to v3.0.0; set
  `network_existing_enabled = true` if consuming VNet from another repo,
  OR keep `false` for auto-VNet (legacy mode).

### Production consumer recommendation

**Stay on v2.1.1** unless explicitly need v3.0.0 features. v3.0.0 is the
foundation for new BYO Network consumers (where VNet/subnet/NSG/NAT GW are
provisioned by a separate network repo).

## [2.1.1] - 2026-04-21

### Fixed — `terraform validate` rejects `cost-export.tf`

Same fix as `estabilis-platform` v0.12.1. `plantimestamp()` at
validate time resolves to `0001-01-01T00:00:00Z`; `formatdate("YYYY",
...)` returns `"1"`, `+ 10` yields `11`, final string is
`"11-01-01T00:00:00Z"` — rejected by the azurerm provider.

Replace with `formatdate("YYYY-MM-DD", timeadd(plantimestamp(),
"87600h"))` — well-formed RFC3339 under both validate and plan.

Unblocks PR validation on downstream consumers.

## [2.1.0] - 2026-04-15 (approximate — backfilled)

### Added
- `hub_cluster_name` bridge key for dynamic push URLs (Alloy → Loki/Mimir).

## [2.0.0] - 2026-04-12 (approximate — backfilled)

### Changed — BREAKING

- Host derivation: hostnames now derived as `{app}.{cluster_name}.{domain}`
  (was `{app}.{env}.{domain}`).
- Affects all ingress exposures (`hubble_ui_exposures`, etc.) — review and
  update DNS records before bumping.

## [1.3.1] - 2026-04-10 (approximate — backfilled)

### Fixed
- bridge: base64-encode exposure JSON for `helm --set-string` compatibility
  (curly braces/commas were metacharacters in the unencoded payload).

## [1.3.0] - 2026-04-08 (approximate — backfilled)

### Added — ADR 0014 exposure model
- Traefik ingress controller toggle (`traefik_enabled`).
- `hubble_ui_exposures` map (per-app exposure with `ingress_class`,
  `allowed_cidrs`, `basic_auth`, `issuer`).
- NSG rules for ingress HTTPS/HTTP when Traefik is enabled.

## [1.2.0] - 2026-04-05 (approximate — backfilled)

### Added — DNS provider abstraction
- `dns_provider` toggle (`azure | cloudflare`).
- Cloudflare DNS support — token stored in workload Key Vault, read by
  ExternalSecrets at runtime.
- New variables: `cloudflare_zone_id`, `cloudflare_api_token`.

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
