# GCP Onboarding Portal — Simplified Sample
# Extends AWS Cognito identity to GCP workloads

terraform {
  required_version = ">= 1.6"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

# KMS Key Ring
resource "google_kms_key_ring" "main" {
  name     = "${var.environment}-onboarding-keyring"
  location = var.gcp_region
}

# KMS Crypto Key (HSM-backed for enterprise)
resource "google_kms_crypto_key" "main" {
  name            = "${var.environment}-onboarding-key"
  key_ring        = google_kms_key_ring.main.id
  rotation_period = "7776000s" # 90 days

  lifecycle {
    prevent_destroy = true
  }

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "HSM"
  }
}

# Workload Identity Federation Pool (trusts AWS Cognito)
resource "google_iam_workload_identity_pool" "cognito" {
  project                   = var.gcp_project_id
  workload_identity_pool_id = "${var.environment}-cognito-pool"
  display_name              = "Cognito Identity Pool"
  location                  = "global"
  disabled                  = false
}

# Workload Identity Provider (AWS Cognito OIDC)
resource "google_iam_workload_identity_pool_provider" "cognito" {
  project                   = var.gcp_project_id
  workload_identity_pool_id = google_iam_workload_identity_pool.cognito.workload_identity_pool_id
  workload_identity_pool_provider_id = "${var.environment}-cognito-oidc"
  display_name                       = "Cognito OIDC Provider"
  disabled                           = false

  attribute_mapping = {
    "google.subject"      = "assertion.sub"
    "attribute.email"     = "assertion.email"
    "attribute.email_verified" = "assertion.email_verified"
  }

  attribute_condition = "assertion.email_verified == 'true'"

  oidc {
    issuer_uri        = var.cognito_issuer_uri
    allowed_audiences = [var.cognito_client_id]
  }
}

# Service Account for Cloud Run
resource "google_service_account" "cloud_run" {
  account_id   = "${var.environment}-onboarding-cr"
  display_name = "Cloud Run Onboarding Service Account"
}

# Workload Identity Binding
resource "google_service_account_iam_binding" "cloud_run_wif" {
  service_account_id = google_service_account.cloud_run.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "principalSet://iam.googleapis.com/projects/${var.gcp_project_number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.cognito.workload_identity_pool_id}/attribute.email_verified/true"
  ]
}

# Cloud Storage Bucket for documents
resource "google_storage_bucket" "documents" {
  project       = var.gcp_project_id
  name          = "${var.environment}-onboarding-docs-${var.gcp_project_id}"
  location      = var.gcp_region
  force_destroy = false

  uniform_bucket_level_access = true

  encryption {
    default_kms_key_name = google_kms_crypto_key.main.id
  }

  retention_policy {
    retention_days = 365
  }

  versioning {
    enabled = true
  }
}

# Prevent public access to bucket
resource "google_storage_bucket_iam_binding" "documents_private" {
  bucket = google_storage_bucket.documents.name
  role   = "roles/storage.objectViewer"
  members = [
    "serviceAccount:${google_service_account.cloud_run.email}"
  ]
}

# Cloud SQL — PostgreSQL
resource "google_sql_database_instance" "main" {
  name             = "${var.environment}-onboarding-db"
  database_version = "POSTGRES_16"
  region           = var.gcp_region

  settings {
    tier      = var.cloud_sql_tier
    disk_size = 20

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.main.id
      require_ssl     = true
    }

    database_flags {
      name  = "cloudsql_iam_authentication"
      value = "on"
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      backup_location                = var.gcp_region
    }

    insights_config {
      query_insights_enabled = true
    }
  }

  deletion_protection = false
}

resource "google_sql_database" "main" {
  name     = "onboarding"
  instance = google_sql_database_instance.main.name
}

# Cloud Armor Security Policy (OTP rate limiting)
resource "google_compute_security_policy" "main" {
  name   = "${var.environment}-onboarding-armor"
  type   = "CLOUD_ARMOR"

  rule {
    action   = "allow"
    priority = "65535"
    match {
      versioned_expr = "SRCIP_LIST"
      source_ipranges = ["*"]
    }
    description = "default rule"
  }

  rule {
    action   = "rate_based_ban"
    priority = "100"
    match {
      expr { expression = "origin.region_code == 'US'" }
    }

    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"

      enforce_on_key = "IP"

      rate_limit_threshold {
        count        = 10
        interval_sec = 300
      }

      ban_duration_sec = 600
    }

    description = "OTP rate limit"
  }

  rule {
    action   = "deny(403)"
    priority = "200"
    match {
      expr { expression = "evaluatePreconfiguredExpr('xss-stable')" }
    }
    description = "XSS protection"
  }

  rule {
    action   = "deny(403)"
    priority = "201"
    match {
      expr { expression = "evaluatePreconfiguredExpr('sqli-stable')" }
    }
    description = "SQLi protection"
  }
}

# VPC Network
resource "google_compute_network" "main" {
  name                    = "${var.environment}-onboarding-vpc"
  auto_create_subnetworks = false
}

# Private Subnet
resource "google_compute_subnetwork" "private" {
  name          = "${var.environment}-private-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.gcp_region
  network       = google_compute_network.main.id

  private_ip_google_access = true
}

# Cloud Run Service (private)
resource "google_cloud_run_v2_service" "app" {
  name     = "${var.environment}-onboarding"
  location = var.gcp_region
  project  = var.gcp_project_id

  ingress = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  template {
    service_account = google_service_account.cloud_run.email

    containers {
      image = var.cloud_run_image # "gcr.io/your-project/onboarding:latest"

      env {
        name  = "DATABASE_URL"
        value = "postgresql://"
      }

      env {
        name  = "GCP_PROJECT"
        value = var.gcp_project_id
      }
    }

    vpc_access {
      network_interfaces {
        network     = google_compute_network.main.name
        subnetwork  = google_compute_subnetwork.private.name
      }
      egress = "ALL_TRAFFIC"
    }
  }
}

# Cloud Logging
resource "google_logging_project_sink" "audit_logs" {
  name        = "${var.environment}-audit-logs"
  destination = "storage.googleapis.com/${google_storage_bucket.logs.name}"
  filter      = "resource.type=cloud_run_revision OR resource.type=cloud_sql_database"
}

resource "google_storage_bucket" "logs" {
  project       = var.gcp_project_id
  name          = "${var.environment}-onboarding-logs-${var.gcp_project_id}"
  location      = var.gcp_region
  force_destroy = false

  uniform_bucket_level_access = true

  encryption {
    default_kms_key_name = google_kms_crypto_key.main.id
  }

  retention_policy {
    retention_days = 90
  }
}

# Outputs
output "workload_identity_pool_id" {
  value       = google_iam_workload_identity_pool.cognito.workload_identity_pool_id
  description = "WIF Pool ID (trusts Cognito)"
}

output "cloud_run_service_url" {
  value       = google_cloud_run_v2_service.app.uri
  description = "Cloud Run service URL"
}

output "cloud_sql_instance" {
  value       = google_sql_database_instance.main.connection_name
  description = "Cloud SQL connection string"
}

output "gcs_documents_bucket" {
  value       = google_storage_bucket.documents.name
  description = "GCS bucket for documents"
}
