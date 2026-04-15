variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

# ===== AWS =====
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "entra_id_metadata_url" {
  description = "Entra ID SAML metadata URL"
  type        = string
  sensitive   = true
}

variable "entra_id_slo_url" {
  description = "Entra ID SAML SLO URL"
  type        = string
}

# ===== GCP =====
variable "gcp_project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "gcp_project_number" {
  description = "GCP Project Number"
  type        = string
}

variable "gcp_region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "cognito_issuer_uri" {
  description = "Cognito OIDC issuer URI"
  type        = string
  # Example: https://cognito-idp.us-east-1.amazonaws.com/<user-pool-id>
}

variable "cognito_client_id" {
  description = "Cognito client ID"
  type        = string
}

variable "cloud_sql_tier" {
  description = "Cloud SQL instance tier"
  type        = string
  default     = "db-f1-micro"
}

variable "cloud_run_image" {
  description = "Cloud Run container image"
  type        = string
  # Example: gcr.io/my-project/onboarding:latest
}

# ===== Azure =====
variable "azure_subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "azure_tenant_id" {
  description = "Azure tenant ID"
  type        = string
}

variable "azure_region" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "azure_admin_object_id" {
  description = "Azure AD object ID of admin user for SQL Server"
  type        = string
}

variable "azure_sql_sku" {
  description = "Azure SQL Database SKU"
  type        = string
  default     = "Basic"
}

variable "app_service_sku" {
  description = "App Service Plan SKU"
  type        = string
  default     = "B1"
}

variable "app_docker_image" {
  description = "Docker image for App Service"
  type        = string
  # Example: myregistry.azurecr.io/onboarding:latest
}

variable "docker_username" {
  description = "Docker registry username"
  type        = string
  sensitive   = true
}

variable "docker_password" {
  description = "Docker registry password"
  type        = string
  sensitive   = true
}

variable "publisher_name" {
  description = "API Management publisher name"
  type        = string
}

variable "publisher_email" {
  description = "API Management publisher email"
  type        = string
}
