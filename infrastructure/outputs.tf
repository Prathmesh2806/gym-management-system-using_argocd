output "acr_name" {
  value = module.acr.acr_name  
}

output "public_ip" {
  value = azurerm_public_ip.appgw_pip.ip_address
}