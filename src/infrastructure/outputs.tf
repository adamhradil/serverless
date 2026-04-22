output "resource_group_name" {
  description = "The name of the resource group."
  value       = azurerm_resource_group.rg.name
}

output "SQL_SERVER_FQDN" {
  description = "The fully qualified domain name of the SQL server."
  value       = azurerm_mssql_server.sql.fully_qualified_domain_name
}

output "faas_fqdn" {
  description = "The FQDN of the FaaS Container App."
  value       = module.faas.faas_fqdn
}

output "faas_api_key" {
  description = "Generated API key for the FaaS HTTP endpoint."
  value       = module.faas.faas_api_key
  sensitive   = true
}

output "iaas_ssh_key_path" {
  description = "Path to the generated SSH private key for the IaaS VM."
  value       = module.iaas.iaas_ssh_key_path
}

output "iaas_vm_public_ip" {
  description = "The public IP address of the Linux VM."
  value       = module.iaas.iaas_vm_public_ip
}

output "ACR_LOGIN_SERVER" {
  description = "The login server for the Azure Container Registry."
  value       = azurerm_container_registry.acr.login_server
}

output "ACR_ADMIN_USERNAME" {
  description = "The admin username for the ACR."
  value       = azurerm_container_registry.acr.admin_username
}

output "ACR_ADMIN_PASSWORD" {
  description = "The admin password for the ACR."
  value       = azurerm_container_registry.acr.admin_password
  sensitive   = true
}
