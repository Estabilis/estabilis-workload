# ---------------------------------------------------------------------------
# NAT Gateway — static outbound IP for AKS
# Toggle via: nat_gateway_enabled = false
# Skipped when network_existing_enabled = true (external network repo owns
# the NAT GW; egress IPs come via var.external_nat_gateway_egress_ips).
# ---------------------------------------------------------------------------

resource "azurerm_public_ip" "nat_gateway" {
  count               = !var.network_existing_enabled && var.nat_gateway_enabled ? 1 : 0
  name                = "pip-${local.base_name}-natgw"
  location            = azurerm_resource_group.workload.location
  resource_group_name = azurerm_resource_group.workload.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_nat_gateway" "workload" {
  count                   = !var.network_existing_enabled && var.nat_gateway_enabled ? 1 : 0
  name                    = "natgw-${local.base_name}"
  location                = azurerm_resource_group.workload.location
  resource_group_name     = azurerm_resource_group.workload.name
  sku_name                = "Standard"
  idle_timeout_in_minutes = var.nat_gateway_idle_timeout
  tags                    = local.tags
}

resource "azurerm_nat_gateway_public_ip_association" "workload" {
  count                = !var.network_existing_enabled && var.nat_gateway_enabled ? 1 : 0
  nat_gateway_id       = azurerm_nat_gateway.workload[0].id
  public_ip_address_id = azurerm_public_ip.nat_gateway[0].id
}

resource "azurerm_subnet_nat_gateway_association" "aks_nodes" {
  count          = !var.network_existing_enabled && var.nat_gateway_enabled ? 1 : 0
  subnet_id      = azurerm_subnet.aks_nodes[0].id
  nat_gateway_id = azurerm_nat_gateway.workload[0].id
}
