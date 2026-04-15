# Azure Onboarding Portal — Simplified Sample
# Entra ID + API Management + Storage

terraform {
  required_version = ">= 1.6"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.azure_subscription_id
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = "${var.environment}-onboarding-rg"
  location = var.azure_region
}

# Key Vault for secrets
resource "azurerm_key_vault" "main" {
  name                            = "${var.environment}onboardingkv${random_string.kv_suffix.result}"
  location                        = azurerm_resource_group.main.location
  resource_group_name             = azurerm_resource_group.main.name
  enabled_for_disk_encryption     = true
  enabled_for_template_deployment = true
  tenant_id                       = var.azure_tenant_id
  sku_name                        = "standard"

  access_policy {
    tenant_id = var.azure_tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "Get",
      "List",
      "Create",
      "Delete",
      "Update"
    ]

    secret_permissions = [
      "Get",
      "List",
      "Set",
      "Delete"
    ]
  }

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }
}

# Storage Account (documents)
resource "azurerm_storage_account" "documents" {
  name                     = "${var.environment}onboardingdocs${random_string.storage_suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "GRS"

  https_traffic_only_enabled       = true
  min_tls_version                  = "TLS1_2"
  shared_access_key_enabled        = false
  public_network_access_enabled    = false

  identity {
    type = "SystemAssigned"
  }
}

# Storage Account encryption with CMK
resource "azurerm_storage_account_customer_managed_key" "documents" {
  storage_account_id = azurerm_storage_account.documents.id
  key_vault_id       = azurerm_key_vault.main.id
  key_name           = azurerm_key_vault_key.storage.name
}

# Key Vault Key for storage encryption
resource "azurerm_key_vault_key" "storage" {
  name         = "${var.environment}-storage-key"
  key_vault_id = azurerm_key_vault.main.id
  key_type     = "RSA"
  key_size     = 2048

  key_opts = [
    "decrypt",
    "encrypt",
    "sign",
    "unwrapKey",
    "verify",
    "wrapKey",
  ]
}

# Storage Container (quarantine)
resource "azurerm_storage_container" "quarantine" {
  name                  = "quarantine"
  storage_account_name  = azurerm_storage_account.documents.name
  container_access_type = "private"
}

# Storage Container (clean)
resource "azurerm_storage_container" "clean" {
  name                  = "clean"
  storage_account_name  = azurerm_storage_account.documents.name
  container_access_type = "private"
}

# Storage Container (rejected)
resource "azurerm_storage_container" "rejected" {
  name                  = "rejected"
  storage_account_name  = azurerm_storage_account.documents.name
  container_access_type = "private"
}

# Azure SQL Database
resource "azurerm_mssql_server" "main" {
  name                         = "${var.environment}-onboarding-sql"
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  version                      = "12.0"
  administrator_login          = "azadmin"
  administrator_login_password = random_password.sql_admin.result

  azuread_administrator {
    login_username              = var.azure_admin_object_id
    object_id                   = var.azure_admin_object_id
    azuread_authentication_only = false
  }

  identity {
    type = "SystemAssigned"
  }
}

# SQL Database
resource "azurerm_mssql_database" "main" {
  name           = "onboarding"
  server_id      = azurerm_mssql_server.main.id
  collation      = "SQL_Latin1_General_CP1_CI_AS"
  license_type   = "LicenseIncluded"
  sku_name       = var.azure_sql_sku

  short_term_retention_policy {
    retention_days = 7
  }

  long_term_retention_policy {
    weekly_retention  = "P4W"
    monthly_retention = "P12M"
  }
}

# SQL Server Firewall Rule
resource "azurerm_mssql_firewall_rule" "azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# App Service Plan
resource "azurerm_service_plan" "main" {
  name                = "${var.environment}-onboarding-plan"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Linux"
  sku_name            = var.app_service_sku
}

# App Service
resource "azurerm_linux_web_app" "main" {
  name                = "${var.environment}-onboarding-${random_string.app_suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.main.id

  https_only = true

  site_config {
    minimum_tls_version = "1.2"

    application_stack {
      docker_image_name   = var.app_docker_image
      docker_registry_url = "https://index.docker.io"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  app_settings = {
    "WEBSITES_ENABLE_APP_SERVICE_STORAGE" = "false"
    "DOCKER_REGISTRY_SERVER_USERNAME"     = var.docker_username
    "DOCKER_REGISTRY_SERVER_PASSWORD"     = var.docker_password
  }
}

# API Management (gateway)
resource "azurerm_api_management" "main" {
  name                = "${var.environment}-onboarding-apim"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  publisher_name      = var.publisher_name
  publisher_email     = var.publisher_email
  sku_name            = "Developer_1"

  identity {
    type = "SystemAssigned"
  }
}

# Application Insights
resource "azurerm_application_insights" "main" {
  name                = "${var.environment}-onboarding-insights"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  retention_in_days   = 30
}

# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.environment}-onboarding-logs"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# Data sources
data "azurerm_client_config" "current" {}

# Random suffixes for globally unique names
resource "random_string" "kv_suffix" {
  length  = 4
  special = false
}

resource "random_string" "storage_suffix" {
  length  = 4
  special = false
}

resource "random_string" "app_suffix" {
  length  = 4
  special = false
}

resource "random_password" "sql_admin" {
  length  = 16
  special = true
}

# Outputs
output "app_service_url" {
  value       = azurerm_linux_web_app.main.default_hostname
  description = "App Service URL"
}

output "sql_server_name" {
  value       = azurerm_mssql_server.main.fully_qualified_domain_name
  description = "SQL Server FQDN"
}

output "storage_account_name" {
  value       = azurerm_storage_account.documents.name
  description = "Storage account name"
}

output "apim_gateway_url" {
  value       = azurerm_api_management.main.gateway_url
  description = "API Management gateway URL"
}

output "key_vault_uri" {
  value       = azurerm_key_vault.main.vault_uri
  description = "Key Vault URI"
}
