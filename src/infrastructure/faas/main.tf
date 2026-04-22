resource "random_password" "api_key" {
  length  = 32
  special = false
}

resource "azurerm_container_app_job" "faas_job" {
  name                         = "faas-benchmark-job"
  container_app_environment_id = azurerm_container_app_environment.faas_env.id
  resource_group_name          = var.resource_group_name
  location                     = var.location

  replica_timeout_in_seconds = 300

  schedule_trigger_config {
    cron_expression          = "* * * * *"
    parallelism              = 1
    replica_completion_count = 1
  }

  registry {
    server               = var.ACR_LOGIN_SERVER
    username             = var.ACR_ADMIN_USERNAME
    password_secret_name = "acr-password"
  }

  secret {
    name  = "acr-password"
    value = var.ACR_ADMIN_PASSWORD
  }

  secret {
    name  = "sql-password"
    value = var.SQL_PASSWORD
  }

  secret {
    name  = "golemio-api-key"
    value = var.GOLEMIO_API_KEY
  }

  template {
    container {
      name    = "benchmark-etl"
      image   = "${var.ACR_LOGIN_SERVER}/benchmark-etl:latest"
      cpu     = 0.5
      memory  = "1Gi"
      command = ["python", "/home/site/wwwroot/main.py"]

      env {
        name  = "SQL_SERVER"
        value = var.SQL_SERVER
      }

      env {
        name  = "SQL_DATABASE"
        value = var.SQL_DATABASE
      }

      env {
        name  = "SQL_USER"
        value = var.SQL_USER
      }

      env {
        name        = "SQL_PASSWORD"
        secret_name = "sql-password"
      }

      env {
        name        = "GOLEMIO_API_KEY"
        secret_name = "golemio-api-key"
      }

      env {
        name  = "TABLE_NAME"
        value = "VehiclePositions_FaaS"
      }

      env {
        name  = "IMAGE_HASH"
        value = var.image_hash
      }

      env {
        name  = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        value = var.APPLICATIONINSIGHTS_CONNECTION_STRING
      }

      env {
        name  = "OTEL_SERVICE_NAME"
        value = "faas-benchmark-job"
      }
    }
  }
}

resource "azurerm_log_analytics_workspace" "faas_logs" {
  name                = "faas-benchmark-logs"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_container_app_environment" "faas_env" {
  name                       = "faas-benchmark-env"
  resource_group_name        = var.resource_group_name
  location                   = var.location
  log_analytics_workspace_id = azurerm_log_analytics_workspace.faas_logs.id
}

resource "azurerm_container_app" "faas_app" {
  name                         = "faas-benchmark-app"
  container_app_environment_id = azurerm_container_app_environment.faas_env.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"

  registry {
    server               = var.ACR_LOGIN_SERVER
    username             = var.ACR_ADMIN_USERNAME
    password_secret_name = "acr-password"
  }

  secret {
    name  = "acr-password"
    value = var.ACR_ADMIN_PASSWORD
  }

  secret {
    name  = "sql-password"
    value = var.SQL_PASSWORD
  }

  secret {
    name  = "golemio-api-key"
    value = var.GOLEMIO_API_KEY
  }

  secret {
    name  = "faas-api-key"
    value = random_password.api_key.result
  }

  template {
    min_replicas = 0
    max_replicas = 1

    container {
      name   = "benchmark-etl"
      image  = "${var.ACR_LOGIN_SERVER}/benchmark-etl:latest"
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "SQL_SERVER"
        value = var.SQL_SERVER
      }

      env {
        name  = "SQL_DATABASE"
        value = var.SQL_DATABASE
      }

      env {
        name  = "SQL_USER"
        value = var.SQL_USER
      }

      env {
        name        = "SQL_PASSWORD"
        secret_name = "sql-password"
      }

      env {
        name        = "GOLEMIO_API_KEY"
        secret_name = "golemio-api-key"
      }

      env {
        name  = "TABLE_NAME"
        value = "VehiclePositions_FaaS"
      }

      env {
        name  = "IMAGE_HASH"
        value = var.image_hash
      }

      env {
        name        = "API_KEY"
        secret_name = "faas-api-key"
      }

      env {
        name  = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        value = var.APPLICATIONINSIGHTS_CONNECTION_STRING
      }

      env {
        name  = "OTEL_SERVICE_NAME"
        value = "faas-benchmark-app"
      }

      startup_probe {
        path             = "/health"
        port             = 8080
        transport        = "HTTP"
        interval_seconds = 1
      }

      liveness_probe {
        path             = "/health"
        port             = 8080
        transport        = "HTTP"
        interval_seconds = 1
      }

      readiness_probe {
        path             = "/health"
        port             = 8080
        transport        = "HTTP"
        interval_seconds = 1
      }
    }
  }

  ingress {
    external_enabled = true
    target_port      = 8080

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }
}
