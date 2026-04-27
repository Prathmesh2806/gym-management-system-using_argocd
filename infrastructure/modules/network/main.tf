# --- Shared Infrastructure (Created only if create_shared_resources is true) ---
resource "azurerm_virtual_network" "vnet" {
  count               = var.create_shared_resources ? 1 : 0
  name                = var.vnet_name
  address_space       = var.vnet_address_space
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# If we are NOT creating shared resources, we need to fetch the existing VNet
data "azurerm_virtual_network" "vnet_data" {
  count               = var.create_shared_resources ? 0 : 1
  name                = var.vnet_name
  resource_group_name = var.shared_resource_group # Anchor to dev
}

locals {
  vnet_name = var.create_shared_resources ? azurerm_virtual_network.vnet[0].name : data.azurerm_virtual_network.vnet_data[0].name
  vnet_id   = var.create_shared_resources ? azurerm_virtual_network.vnet[0].id : data.azurerm_virtual_network.vnet_data[0].id
}

# --- NAT Gateway (Shared Outbound) ---
resource "azurerm_public_ip" "nat_pip" {
  count               = var.create_shared_resources ? 1 : 0
  name                = var.nat_pip_name
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway" "nat_gw" {
  count                   = var.create_shared_resources ? 1 : 0
  name                    = var.nat_gw_name
  location                = var.location
  resource_group_name     = var.resource_group_name
  sku_name            = var.nat_sku
  idle_timeout_in_minutes = var.nat_idle_timeout
  tags                    = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "nat_assoc" {
  count              = var.create_shared_resources ? 1 : 0
  nat_gateway_id     = azurerm_nat_gateway.nat_gw[0].id
  public_ip_address_id = azurerm_public_ip.nat_pip[0].id
}

# Fetch NAT Gateway if not creating
data "azurerm_nat_gateway" "nat_data" {
  count               = var.create_shared_resources ? 0 : 1
  name                = var.nat_gw_name
  resource_group_name = var.shared_resource_group
}

locals {
  nat_gateway_id = var.create_shared_resources ? azurerm_nat_gateway.nat_gw[0].id : data.azurerm_nat_gateway.nat_data[0].id

  # Dynamic offset based on environment to prevent overlap in Shared VNet
  # Each env gets 50 indices (~12,800 IPs)
  env_offsets = {
    "dev"  = 0
    "qa"   = 50
    "prod" = 100
    "dr"   = 150
  }
  offset = lookup(local.env_offsets, var.env, 0)
}

# Public Subnets
resource "azurerm_subnet" "public" {
  count                = var.public_subnet_count
  name                 = "${var.public_subnet_prefix}-${var.env}-${count.index + 1}"
  resource_group_name  = var.create_shared_resources ? var.resource_group_name : var.shared_resource_group
  virtual_network_name = local.vnet_name
  address_prefixes     = [cidrsubnet(var.vnet_address_space[0], var.subnet_newbits, count.index + 1 + local.offset)]
}

# Private App Subnets (Where AKS Lives)
resource "azurerm_subnet" "app" {
  count                = var.app_subnet_count
  name                 = "${var.app_subnet_prefix}-${var.env}-${count.index + 1}"
  resource_group_name  = var.create_shared_resources ? var.resource_group_name : var.shared_resource_group
  virtual_network_name = local.vnet_name
  address_prefixes     = [cidrsubnet(var.vnet_address_space[0], var.subnet_newbits, count.index + 11 + local.offset)]
  service_endpoints    = var.app_service_endpoints
}

# Associate App Subnet with NAT Gateway
resource "azurerm_subnet_nat_gateway_association" "app_nat" {
  count          = var.app_subnet_count
  subnet_id      = azurerm_subnet.app[count.index].id
  nat_gateway_id = local.nat_gateway_id
}

# Private DB Subnets
resource "azurerm_subnet" "db" {
  count                = var.db_subnet_count
  name                 = "${var.db_subnet_prefix}-${var.env}-${count.index + 1}"
  resource_group_name  = var.create_shared_resources ? var.resource_group_name : var.shared_resource_group
  virtual_network_name = local.vnet_name
  address_prefixes     = [cidrsubnet(var.vnet_address_space[0], var.subnet_newbits, count.index + 21 + local.offset)]
}

# Subnet for Application Gateway
resource "azurerm_subnet" "appgw" {
  name                 = "appgw-subnet-${var.env}"
  resource_group_name  = var.create_shared_resources ? var.resource_group_name : var.shared_resource_group
  virtual_network_name = local.vnet_name
  address_prefixes     = [cidrsubnet(var.vnet_address_space[0], var.subnet_newbits, 31 + local.offset)] 
}

# NSG for App Subnet
resource "azurerm_network_security_group" "app_nsg" {
  name                = "gym-app-nsg-${var.env}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "AllowHTTPInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowHTTPSInbound"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "app_assoc" {
  count                     = var.app_subnet_count
  subnet_id                 = azurerm_subnet.app[count.index].id
  network_security_group_id = azurerm_network_security_group.app_nsg.id
}

# NSG for DB Subnet
resource "azurerm_network_security_group" "db_nsg" {
  name                = "${var.db_nsg_name}-${var.env}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "AllowAppToDB"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = var.db_port
    source_address_prefixes    = azurerm_subnet.app[*].address_prefixes[0]
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "db_assoc" {
  count                     = var.db_subnet_count
  subnet_id                 = azurerm_subnet.db[count.index].id
  network_security_group_id = azurerm_network_security_group.db_nsg.id
}

# --- Application Gateway Security (Required for V2) ---
resource "azurerm_network_security_group" "appgw_nsg" {
  name                = "gym-appgw-nsg-${var.env}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "AllowHTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowHTTPS"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowGatewayManager"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "65200-65535"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "appgw_assoc" {
  subnet_id                 = azurerm_subnet.appgw.id
  network_security_group_id = azurerm_network_security_group.appgw_nsg.id
}
