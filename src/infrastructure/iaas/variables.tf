variable "resource_group_name" {
  type        = string
  description = "Name of the resource group"
}

variable "location" {
  type        = string
  description = "Azure region"
}

variable "SQL_SERVER" {
  type        = string
  description = "The fully qualified domain name of the SQL server"
}

variable "SQL_DATABASE" {
  type        = string
  description = "The name of the SQL database"
}

variable "SQL_USER" {
  type        = string
  description = "SQL administrator username"
}

variable "SQL_PASSWORD" {
  type        = string
  description = "SQL administrator password"
  sensitive   = true
}

variable "GOLEMIO_API_KEY" {
  type        = string
  description = "API key for Golemio"
  sensitive   = true
}

variable "ACR_LOGIN_SERVER" {
  type        = string
  description = "Login server for the Azure Container Registry"
}

variable "ACR_ADMIN_USERNAME" {
  type        = string
  description = "Admin username for the Azure Container Registry"
}

variable "ACR_ADMIN_PASSWORD" {
  type        = string
  description = "Admin password for the Azure Container Registry"
  sensitive   = true
}

variable "APPLICATIONINSIGHTS_CONNECTION_STRING" {
  type        = string
  description = "Connection string for Application Insights"
  default     = null
}
