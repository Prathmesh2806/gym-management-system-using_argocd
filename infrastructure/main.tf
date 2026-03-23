resource "azurerm_resource_group" "gym_rg" {
  name     = "gym-app-shared-rg"
  location = var.location
  tags     = var.tags
}

resource "random_string" "suffix" {
  length  = var.random_suffix_length
  special = false
  upper   = false
  # special/upper are usually safe to keep hardcoded as 'false' unless 
  # there's a specific need for special chars in ACR/resource names.
}

module "network" {
  source                = "./modules/network"
  resource_group_name   = azurerm_resource_group.gym_rg.name
  location              = azurerm_resource_group.gym_rg.location
  vnet_name             = var.vnet_name
  vnet_address_space    = var.vnet_address_space
  public_subnet_count   = var.public_subnet_count
  app_subnet_count      = var.app_subnet_count
  db_subnet_count       = var.db_subnet_count
  public_subnet_prefix  = var.public_subnet_prefix
  app_subnet_prefix     = var.app_subnet_prefix
  db_subnet_prefix      = var.db_subnet_prefix
  app_service_endpoints = var.app_service_endpoints
  db_nsg_name           = var.db_nsg_name
  db_port               = var.db_port
  env                   = var.env
  create_shared_resources = var.create_shared_resources
  shared_resource_group = var.shared_resource_group
  nat_sku               = var.nat_sku
  nat_idle_timeout      = var.nat_idle_timeout
  subnet_newbits        = var.subnet_newbits
  nat_pip_name          = var.nat_pip_name
  nat_gw_name           = var.nat_gw_name
  tags                 = var.tags
}

module "aks" {
  source              = "./modules/aks"
  resource_group_name = azurerm_resource_group.gym_rg.name
  location            = azurerm_resource_group.gym_rg.location
  cluster_name        = "gym-shared-aks"
  dns_prefix          = var.dns_prefix
  node_count          = var.node_count
  vm_size             = var.vm_size
  service_cidr        = var.service_cidr
  dns_service_ip      = var.dns_service_ip
  vnet_subnet_id      = module.network.aks_subnet_id 
  app_gateway_id      = azurerm_application_gateway.appgw.id
  vnet_id             = module.network.vnet_id
  subscription_id     = var.subscription_id
  node_pool_name      = var.node_pool_name
  network_plugin      = var.network_plugin
  load_balancer_sku   = var.load_balancer_sku
  outbound_type       = var.outbound_type
  agic_identity_name_prefix = var.agic_identity_name_prefix
  tags                = var.tags
}

module "acr" {
  source              = "./modules/acr"
  resource_group_name = azurerm_resource_group.gym_rg.name
  location            = azurerm_resource_group.gym_rg.location
  acr_name            = "gymappregistry${var.env}${random_string.suffix.result}"
  acr_sku             = var.acr_sku
  acr_admin_enabled   = var.acr_admin_enabled
  aks_principal_id    = module.aks.principal_id
  tags                = var.tags
}

resource "azurerm_public_ip" "appgw_pip" {
  name                = "gym-shared-appgw-pip"
  resource_group_name = azurerm_resource_group.gym_rg.name
  location            = azurerm_resource_group.gym_rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_application_gateway" "appgw" {
  name                = "gym-shared-appgw"
  resource_group_name = azurerm_resource_group.gym_rg.name
  location            = azurerm_resource_group.gym_rg.location
  tags                = var.tags

  sku {
    name     = var.appgw_sku_name
    tier     = var.appgw_sku_tier
    capacity = var.appgw_capacity
  }

  gateway_ip_configuration {
    name      = var.appgw_ip_config_name
    subnet_id = module.network.appgw_subnet_id
  }

  frontend_port {
    name = var.appgw_frontend_port_http_name
    port = var.appgw_http_port
  }

  frontend_port {
    name = var.appgw_frontend_port_https_name
    port = var.appgw_https_port
  }

  frontend_ip_configuration {
    name                 = var.appgw_frontend_ip_config_name
    public_ip_address_id = azurerm_public_ip.appgw_pip.id
  }

  backend_address_pool {
    name = var.appgw_backend_pool_name
  }

  backend_http_settings {
    name                  = var.appgw_http_settings_name
    cookie_based_affinity = "Disabled"
    port                  = var.appgw_http_port
    protocol              = "Http"
    request_timeout       = var.appgw_request_timeout
  }

  http_listener {
    name                           = var.appgw_listener_name
    frontend_ip_configuration_name = var.appgw_frontend_ip_config_name
    frontend_port_name             = var.appgw_frontend_port_http_name
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = var.appgw_routing_rule_name
    rule_type                  = "Basic"
    http_listener_name         = var.appgw_listener_name
    backend_address_pool_name  = var.appgw_backend_pool_name
    backend_http_settings_name = var.appgw_http_settings_name
    priority                   = var.appgw_routing_rule_priority
  }

  ssl_policy {
    policy_type = "Predefined"
    policy_name = var.appgw_ssl_policy_name
  }

  lifecycle {
    ignore_changes = [
      backend_address_pool,
      backend_http_settings,
      http_listener,
      request_routing_rule,
      probe,
      tags,
      frontend_port,
      ssl_certificate,
      redirect_configuration,
      url_path_map
    ]
  }
}
