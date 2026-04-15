# AWS Onboarding Portal — Simplified Sample
# Commercial + Enterprise (Entra ID) identity paths

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "OnboardingPortal"
      ManagedBy   = "Terraform"
    }
  }
}

# KMS CMK for encryption
resource "aws_kms_key" "main" {
  description             = "CMK for onboarding portal encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true
}

resource "aws_kms_alias" "main" {
  name          = "alias/onboarding-${var.environment}"
  target_key_id = aws_kms_key.main.key_id
}

# Cognito User Pool — Commercial users (native MFA + OTP)
resource "aws_cognito_user_pool" "commercial" {
  name = "${var.environment}-commercial-pool"

  password_policy {
    minimum_length    = 12
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

  mfa_configuration = "OPTIONAL"

  software_token_mfa_configuration {
    enabled = true
  }

  account_recovery_setting {
    recovery_mechanism {
      name       = "verified_email"
      priority   = 1
    }
  }
}

# Cognito User Pool Client — Commercial
resource "aws_cognito_user_pool_client" "commercial" {
  user_pool_id = aws_cognito_user_pool.commercial.id
  name         = "${var.environment}-commercial-client"

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  generate_secret = false
}

# Cognito Identity Provider — Entra ID (Enterprise)
resource "aws_cognito_identity_provider" "entra_id" {
  user_pool_id  = aws_cognito_user_pool.commercial.id
  provider_name = "EntraID"
  provider_type = "SAML"

  provider_details = {
    MetadataURL           = var.entra_id_metadata_url
    SLORedirectBindingURI = var.entra_id_slo_url
  }

  attribute_mapping = {
    email    = "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress"
    name     = "http://schemas.microsoft.com/identity/claims/displayname"
    username = "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name"
  }
}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.environment}-onboarding-${data.aws_caller_identity.current.account_id}"
  user_pool_id = aws_cognito_user_pool.commercial.id
}

# DynamoDB — OTP Attempt Tracker
resource "aws_dynamodb_table" "otp_tracker" {
  name           = "${var.environment}-otp-tracker"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "PhoneOrEmail"

  attribute {
    name = "PhoneOrEmail"
    type = "S"
  }

  ttl {
    attribute_name = "ExpiresAt"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.main.arn
  }

  tags = {
    Name = "${var.environment}-otp-tracker"
  }
}

# S3 Bucket — Quarantine (pre-scan)
resource "aws_s3_bucket" "quarantine" {
  bucket = "${var.environment}-onboarding-quarantine-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "quarantine" {
  bucket = aws_s3_bucket.quarantine.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.arn
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "quarantine" {
  bucket = aws_s3_bucket.quarantine.id

  rule {
    id     = "expire-unscanned"
    status = "Enabled"
    filter { prefix = "" }
    expiration { days = 7 }
  }
}

# S3 Bucket — Clean (post-scan, Object Lock)
resource "aws_s3_bucket" "clean" {
  bucket = "${var.environment}-onboarding-clean-${data.aws_caller_identity.current.account_id}"

  object_lock_enabled = true
}

resource "aws_s3_bucket_object_lock_configuration" "clean" {
  bucket = aws_s3_bucket.clean.id

  rule {
    default_retention {
      mode = "COMPLIANCE"
      days = 365
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "clean" {
  bucket = aws_s3_bucket.clean.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.arn
    }
  }
}

# S3 Bucket — Rejected (quarantine, forensics)
resource "aws_s3_bucket" "rejected" {
  bucket = "${var.environment}-onboarding-rejected-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_lifecycle_configuration" "rejected" {
  bucket = aws_s3_bucket.rejected.id

  rule {
    id     = "purge-after-30-days"
    status = "Enabled"
    filter { prefix = "" }
    expiration { days = 30 }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "rejected" {
  bucket = aws_s3_bucket.rejected.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.arn
    }
  }
}

# WAF — OTP Rate Limiting
resource "aws_wafv2_web_acl" "main" {
  name  = "${var.environment}-otp-waf"
  scope = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "OTPRateLimit"
    priority = 1
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = 10
        aggregate_key_type = "IP"
        scope_down_statement {
          byte_match_statement {
            field_to_match { uri_path {} }
            positional_constraint = "CONTAINS"
            search_string         = "/auth/otp"
            text_transformation { priority = 0; type = "LOWERCASE" }
          }
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "OTPRateLimit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.environment}-waf"
    sampled_requests_enabled   = true
  }
}

# CloudWatch — Basic monitoring
resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${var.environment}-onboarding"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.main.arn
}

# Outputs
data "aws_caller_identity" "current" {}

output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.commercial.id
  description = "Cognito User Pool ID"
}

output "cognito_client_id" {
  value       = aws_cognito_user_pool_client.commercial.id
  description = "Cognito Client ID"
}

output "cognito_domain" {
  value       = aws_cognito_user_pool_domain.main.domain
  description = "Cognito Domain"
}

output "s3_quarantine_bucket" {
  value       = aws_s3_bucket.quarantine.id
  description = "S3 Quarantine Bucket"
}

output "s3_clean_bucket" {
  value       = aws_s3_bucket.clean.id
  description = "S3 Clean Bucket"
}

output "otp_tracker_table" {
  value       = aws_dynamodb_table.otp_tracker.name
  description = "DynamoDB OTP Tracker Table"
}

output "waf_acl_arn" {
  value       = aws_wafv2_web_acl.main.arn
  description = "WAF Web ACL ARN"
}
