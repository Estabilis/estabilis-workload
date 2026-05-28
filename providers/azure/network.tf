# ---------------------------------------------------------------------------
# Virtual Network — auto-created when network_existing_enabled = false (default).
# When true, consume external VNet/subnet from another Terraform repo
# (separation of concerns: network repo owns the VNet lifecycle).
# ---------------------------------------------------------------------------

resource "azurerm_virtual_network" "workload" {
  count               = var.network_existing_enabled ? 0 : 1
  name                = "vnet-${local.base_name}"
  location            = azurerm_resource_group.workload.location
  resource_group_name = azurerm_resource_group.workload.name
  address_space       = [var.vnet_address_space]
  tags                = local.tags
}

# Optional data source to inspect external VNet metadata when in BYO mode.
data "azurerm_virtual_network" "external" {
  count               = var.network_existing_enabled && var.existing_vnet_name != "" && var.existing_vnet_resource_group_name != "" ? 1 : 0
  name                = var.existing_vnet_name
  resource_group_name = var.existing_vnet_resource_group_name
}

# ---------------------------------------------------------------------------
# Subnets — auto-created in legacy mode; BYO mode receives subnet IDs via vars
# ---------------------------------------------------------------------------

resource "azurerm_subnet" "aks_nodes" {
  count                = var.network_existing_enabled ? 0 : 1
  name                 = "snet-${local.base_name}-nodes"
  resource_group_name  = azurerm_resource_group.workload.name
  virtual_network_name = azurerm_virtual_network.workload[0].name
  address_prefixes     = [var.subnet_nodes_prefix]
  service_endpoints    = ["Microsoft.KeyVault", "Microsoft.Storage"]
}

resource "azurerm_subnet" "aks_pods" {
  count                = var.network_existing_enabled ? 0 : 1
  name                 = "snet-${local.base_name}-pods"
  resource_group_name  = azurerm_resource_group.workload.name
  virtual_network_name = azurerm_virtual_network.workload[0].name
  address_prefixes     = [var.subnet_pods_prefix]
  service_endpoints    = ["Microsoft.KeyVault", "Microsoft.Storage"]
}

# ---------------------------------------------------------------------------
# RBAC — AKS identity needs Network Contributor on the node subnet to
# create/manage Load Balancers and associate them with the subnet.
# Scope works for both internal subnet (resource ref) and external subnet
# (consumed via local.subnet_nodes_id).
# ---------------------------------------------------------------------------

resource "azurerm_role_assignment" "aks_network_contributor" {
  scope                = local.subnet_nodes_id
  role_definition_name = "Network Contributor"
  principal_id         = local.aks_identity_principal_id
}
