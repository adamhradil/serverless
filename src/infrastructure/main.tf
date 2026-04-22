provider "azurerm" {
  features {}
  resource_provider_registrations = "none"
}

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

resource "random_id" "suffix" {
  byte_length = 3
}

resource "azurerm_container_registry" "acr" {
  name                = "benchmarkacr${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = true
}

resource "azurerm_application_insights" "insights" {
  name                = "benchmark-insights"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  application_type    = "web"
}

resource "azurerm_mssql_server" "sql" {
  name                         = "benchmark-sql-${random_id.suffix.hex}"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = azurerm_resource_group.rg.location
  version                      = "12.0"
  administrator_login          = var.SQL_USER
  administrator_login_password = var.SQL_PASSWORD
}

resource "azurerm_mssql_database" "db" {
  name        = "etl-db"
  server_id   = azurerm_mssql_server.sql.id
  sku_name    = "S0"
  max_size_gb = 200
}

resource "azurerm_mssql_firewall_rule" "allow_all" {
  name             = "AllowAll"
  server_id        = azurerm_mssql_server.sql.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "255.255.255.255"
}

# hash of all files that affect the image, used to trigger redeployment
locals {
  image_hash = sha256(join("", concat(
    [filemd5("${path.module}/../../Dockerfile"), filemd5("${path.module}/../../pyproject.toml")],
    [for f in fileset("${path.module}/../../src/pipeline", "*.py") : filemd5("${path.module}/../../src/pipeline/${f}")]
  )))
}

# builds and pushes the image before any compute resources are provisioned
resource "terraform_data" "push_image" {
  depends_on = [azurerm_container_registry.acr]

  triggers_replace = [
    azurerm_container_registry.acr.login_server,
    local.image_hash,
  ]

  provisioner "local-exec" {
    working_dir = "${path.module}/../.."
    command     = <<-EOT
      docker login ${azurerm_container_registry.acr.login_server} \
        -u ${azurerm_container_registry.acr.admin_username} \
        -p ${azurerm_container_registry.acr.admin_password} \
      && docker build -t ${azurerm_container_registry.acr.login_server}/benchmark-etl:latest . \
      && docker push ${azurerm_container_registry.acr.login_server}/benchmark-etl:latest
    EOT
  }
}

module "faas" {
  depends_on                            = [terraform_data.push_image]
  source                                = "./faas"
  resource_group_name                   = azurerm_resource_group.rg.name
  location                              = azurerm_resource_group.rg.location
  ACR_LOGIN_SERVER                      = azurerm_container_registry.acr.login_server
  ACR_ADMIN_USERNAME                    = azurerm_container_registry.acr.admin_username
  ACR_ADMIN_PASSWORD                    = azurerm_container_registry.acr.admin_password
  SQL_SERVER                            = azurerm_mssql_server.sql.fully_qualified_domain_name
  SQL_DATABASE                          = var.SQL_DATABASE
  SQL_USER                              = var.SQL_USER
  SQL_PASSWORD                          = var.SQL_PASSWORD
  GOLEMIO_API_KEY                       = var.GOLEMIO_API_KEY
  APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.insights.connection_string
  image_hash                            = local.image_hash
}

module "iaas" {
  depends_on                            = [terraform_data.push_image]
  source                                = "./iaas"
  resource_group_name                   = azurerm_resource_group.rg.name
  location                              = azurerm_resource_group.rg.location
  SQL_SERVER                            = azurerm_mssql_server.sql.fully_qualified_domain_name
  SQL_USER                              = var.SQL_USER
  SQL_PASSWORD                          = var.SQL_PASSWORD
  SQL_DATABASE                          = var.SQL_DATABASE
  GOLEMIO_API_KEY                       = var.GOLEMIO_API_KEY
  ACR_LOGIN_SERVER                      = azurerm_container_registry.acr.login_server
  ACR_ADMIN_USERNAME                    = azurerm_container_registry.acr.admin_username
  ACR_ADMIN_PASSWORD                    = azurerm_container_registry.acr.admin_password
  APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.insights.connection_string
}
