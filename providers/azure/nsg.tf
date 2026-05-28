# ---------------------------------------------------------------------------
# Network Security Group — defense in depth for AKS node subnet
# Toggle via: nsg_enabled = false
# Skipped when network_existing_enabled = true (external network repo owns
# NSG/route table on the subnet).
# ---------------------------------------------------------------------------

resource "azurerm_network_security_group" "aks_nodes" {
  count               = !var.network_existing_enabled && var.nsg_enabled ? 1 : 0
  name                = "nsg-${local.base_name}"
  location            = azurerm_resource_group.workload.location
  resource_group_name = azurerm_resource_group.workload.name
  tags                = local.tags
}

resource "azurerm_subnet_network_security_group_association" "aks_nodes" {
  count                     = !var.network_existing_enabled && var.nsg_enabled ? 1 : 0
  subnet_id                 = azurerm_subnet.aks_nodes[0].id
  network_security_group_id = azurerm_network_security_group.aks_nodes[0].id
}

# ---------------------------------------------------------------------------
# Ingress rules — ADR 0014: allow HTTP/HTTPS when Traefik is enabled
# ---------------------------------------------------------------------------

locals {
  ingress_source_prefixes = length(var.ingress_allowed_ip_ranges) > 0 ? var.ingress_allowed_ip_ranges : null
  ingress_source_prefix   = length(var.ingress_allowed_ip_ranges) > 0 ? null : "*"
}

resource "azurerm_network_security_rule" "ingress_https" {
  count                       = !var.network_existing_enabled && var.nsg_enabled && (var.traefik_enabled || var.traefik_internal_enabled) ? 1 : 0
  name                        = "AllowHTTPSInbound"
  priority                    = 200
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = local.ingress_source_prefix
  source_address_prefixes     = local.ingress_source_prefixes
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.workload.name
  network_security_group_name = azurerm_network_security_group.aks_nodes[0].name
}

resource "azurerm_network_security_rule" "ingress_http" {
  count                       = !var.network_existing_enabled && var.nsg_enabled && (var.traefik_enabled || var.traefik_internal_enabled) ? 1 : 0
  name                        = "AllowHTTPInbound"
  priority                    = 201
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "80"
  source_address_prefix       = local.ingress_source_prefix
  source_address_prefixes     = local.ingress_source_prefixes
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.workload.name
  network_security_group_name = azurerm_network_security_group.aks_nodes[0].name
}
