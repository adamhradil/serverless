output "faas_fqdn" {
  description = "The FQDN of the FaaS Container App"
  value       = azurerm_container_app.faas_app.ingress[0].fqdn
}

output "faas_api_key" {
  description = "Generated API key for the FaaS HTTP endpoint"
  value       = random_password.api_key.result
  sensitive   = true
}
