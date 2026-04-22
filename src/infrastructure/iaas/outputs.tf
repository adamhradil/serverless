output "iaas_vm_public_ip" {
  description = "The public IP address of the IaaS VM"
  value       = azurerm_public_ip.iaas_ip.ip_address
}

output "iaas_ssh_key_path" {
  description = "Path to the generated SSH private key for the IaaS VM"
  value       = local_sensitive_file.iaas_ssh_key.filename
}

