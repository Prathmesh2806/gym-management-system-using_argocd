resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.cluster_name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.dns_prefix
  tags                = var.tags

  default_node_pool {
    name           = var.node_pool_name
    node_count     = var.node_count
    vm_size        = var.vm_size
    vnet_subnet_id = var.vnet_subnet_id
  }

  identity {
    type = "SystemAssigned"
  }

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # --Enabled Application Gateway Ingress Controller ---
  ingress_application_gateway {
    gateway_id = var.app_gateway_id
  }

  network_profile {
    network_plugin     = var.network_plugin
    load_balancer_sku  = var.load_balancer_sku
    outbound_type      = var.outbound_type
    service_cidr       = var.service_cidr
    dns_service_ip     = var.dns_service_ip
  }
}

# 1. Identity created by the AGIC Addon
data "azurerm_user_assigned_identity" "agic_identity" {
  name                = "${var.agic_identity_name_prefix}-${var.cluster_name}"
  resource_group_name = "MC_${var.resource_group_name}_${var.cluster_name}_${var.location}" 
  
  depends_on = [azurerm_kubernetes_cluster.aks]
}

resource "azurerm_role_assignment" "agic_rg_reader" {
  scope                = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}"
  role_definition_name = "Reader"
  principal_id         = data.azurerm_user_assigned_identity.agic_identity.principal_id
}

# 2. Assigned Network Contributor to the AGIC Identity so it can use the Subnet
resource "azurerm_role_assignment" "agic_network_contributor" {
  scope                = var.vnet_id 
  role_definition_name = "Network Contributor"
  principal_id         = data.azurerm_user_assigned_identity.agic_identity.principal_id
}

# Application Gateway 
resource "azurerm_role_assignment" "agic_appgw_contributor" {
  scope                = var.app_gateway_id
  role_definition_name = "Contributor"
  principal_id         = data.azurerm_user_assigned_identity.agic_identity.principal_id

  depends_on = [azurerm_kubernetes_cluster.aks]
}