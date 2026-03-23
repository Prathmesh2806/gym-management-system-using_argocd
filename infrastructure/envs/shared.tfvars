env                  = "shared"
create_shared_resources = true
location             = "eastus2"
node_count           = 2
vm_size              = "Standard_D2s_v3"

# Networking Config
vnet_name            = "gym-shared-vnet"
vnet_address_space   = ["10.0.0.0/16"]
appgw_subnet_prefix  = ["10.0.2.0/24"]

public_subnet_count  = 2
app_subnet_count     = 2
db_subnet_count      = 2

public_subnet_prefix = "pub-sub"
app_subnet_prefix    = "app-sub-private"
db_subnet_prefix     = "db-sub-private"

app_service_endpoints = ["Microsoft.Storage"]
db_nsg_name           = "db-private-nsg"
db_port               = "3306"

# Registry & DNS
acr_name             = "gymappregshared"
dns_prefix           = "gymappshared"
service_cidr         = "10.1.0.0/16"
dns_service_ip       = "10.1.0.10"

# App Gateway
appgw_name           = "gym-shared-appgw"
appgw_pip_name       = "gym-shared-appgw-pip"
pip_resource_group   = "tfstate-mgmt-rg"
