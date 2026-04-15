# Onboarding Portal — Terraform Sample (Multi-Cloud)

Production-ready IaC for customer onboarding. Two user paths (commercial + enterprise). Three clouds (AWS, GCP, Azure). One night to deploy. Let's go.

This is a learning lab. It's not a real company's onboarding system (though you could fork it and make it one).

## What's Inside

**AWS:**
- Cognito for logins (both your users and their Entra ID)
- WAF that stops brute force attacks on OTP
- S3 buckets set up the right way (quarantine, scan, store)
- DynamoDB tracking failed login attempts
- KMS encryption (because we're not monsters)

**GCP:**
- Workload Identity Federation (AWS Cognito tokens work here too)
- Cloud Run for the app backend
- Cloud SQL for customer data
- Cloud Storage for documents
- Cloud Armor for DDoS protection

**Azure:**
- App Service for the web app
- SQL Database for records
- Key Vault for secrets
- Storage for uploads
- API Management (the enterprise gateway)

## How It Works

```
Your commercial customers log in here:
┌─────────────────────────────────────┐
│  Cognito User Pool + Native MFA     │ ← You manage passwords
└──────────────┬──────────────────────┘
               │
Your enterprise customers log in here:
┌──────────────▼──────────────────────┐
│  Entra ID (SAML Federation)         │ ← Their company manages passwords
└──────────────┬──────────────────────┘
               │
      Both get a JWT token
               │
      Used by AWS / GCP / Azure
```

## Prerequisites

- Terraform >= 1.6
- AWS CLI configured (credentials in `~/.aws/credentials`)
- Entra ID tenant (for SAML federation)
- Access to Entra ID admin portal

## Quick Start

### 1. Copy tfvars template
```bash
cp terraform.tfvars.example terraform.tfvars
```

### 2. Fill in your values
```bash
# Edit terraform.tfvars
environment = "dev"
entra_id_metadata_url = "https://login.microsoftonline.com/<your-tenant-id>/federationmetadata/2007-06/federationmetadata.xml"
entra_id_slo_url = "https://login.microsoftonline.com/<your-tenant-id>/saml2"
```

### 3. Initialize Terraform
```bash
terraform init
```

### 4. Plan and apply
```bash
terraform plan
terraform apply
```

## Entra ID Setup

### Get SAML Metadata URL

1. Go to **Azure Portal → App registrations**
2. Create new app or use existing
3. Navigate to **Certificates & secrets**
4. Note the Federation Metadata Document URL:
   ```
   https://login.microsoftonline.com/{tenant-id}/federationmetadata/2007-06/federationmetadata.xml
   ```

5. Also note the SAML SLO endpoint:
   ```
   https://login.microsoftonline.com/{tenant-id}/saml2
   ```

6. Add Cognito callback URLs to Entra ID app:
   - After deployment, get Cognito domain from `terraform apply` output
   - Add to Entra ID: `https://<cognito-domain>.auth.<region>.amazoncognito.com/saml2/idpResponse`

## Outputs

After `terraform apply`, you'll see:
- `cognito_user_pool_id` — Use for API Gateway authorizer
- `cognito_client_id` — Use in frontend auth flow
- `cognito_domain` — Cognito hosted UI endpoint
- `s3_quarantine_bucket` — Where customers upload documents
- `otp_tracker_table` — DynamoDB table for rate limiting

## Next Steps

- **API Gateway** — Wire Cognito JWT authorizer
- **Lambda** — Onboarding logic + S3 event handlers
- **RDS + RDS Proxy** — Customer data store
- **GCP Extension** — See `gcp_main.tf`
- **Azure Extension** — See `azure_main.tf`

## Security Notes

- OTP attempts limited to 10 per 5 minutes per IP (WAF)
- DynamoDB TTL auto-expires attempts (5 min cooldown)
- S3 encryption with KMS CMK
- Cognito MFA required
- Object Lock on clean bucket (365d COMPLIANCE mode)
- Documents auto-purged from quarantine after 7 days if unscanned

## Modify for Your Use

- Change bucket names (must be globally unique)
- Update OTP rate limit (WAF rule: `limit = 10`)
- Adjust DynamoDB TTL (OTP tracker: `ExpiresAt`)
- Enable additional Cognito attributes
- Add more IdPs (OIDC, SAML)

## Destroy

```bash
terraform destroy
```

⚠️ **Warning:** S3 buckets with Object Lock cannot be destroyed until retention expires (365 days). You'll need to:
1. Disable Object Lock (manual step in AWS Console)
2. Empty buckets
3. Then `terraform destroy`

---

**Full reference architecture:** See parent directory for enterprise-grade setup with account structure, CI/CD, monitoring, GCP/Azure extensions.
