variable "resource_group_name" {
  type        = string
  description = "Name of the resource group"
  default     = "benchmark-rg"
}

variable "location" {
  type        = string
  description = "Azure region"
  default     = "switzerlandnorth"
}

variable "SQL_USER" {
  type        = string
  description = "SQL administrator username"
}

variable "SQL_DATABASE" {
  type        = string
  description = "The name of the SQL database"
  default     = "etl-db"
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
