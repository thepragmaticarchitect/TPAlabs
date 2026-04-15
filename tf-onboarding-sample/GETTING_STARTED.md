# Getting Started — Onboarding Portal Lab

I built this to work. Not to look fancy. You'll deploy a production-grade customer onboarding system across three clouds in a few hours.

Fair warning: It's hands-on. You'll need admin access, patience, and a willingness to dig into cloud consoles when something doesn't match the docs (it happens).

---

## Prerequisites

You need three things: tools, cloud access, and some cloud knowledge.

### Tools

Install these:
- **Terraform** >= 1.6 ([get it](https://www.terraform.io/downloads))
- **AWS CLI** v2 ([get it](https://aws.amazon.com/cli/))
- **GCloud CLI** ([get it](https://cloud.google.com/sdk/docs/install))
- **Azure CLI** ([get it](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli))
- **Git** ([get it](https://git-scm.com/))

You probably have Git. AWS CLI too, if you've touched AWS before. The others? Yeah, install them.

### Cloud Accounts

You need live, paid accounts. Not free tiers (they'll work for a bit, then hit limits).

- **AWS**: One account. Admin role. Period.
- **GCP**: New project. Billing enabled (it's cheap for testing).
- **Azure**: Active subscription. You'll create resources in it.
- **Entra ID**: Tenant with admin access. This is how enterprise users log in.

### Cloud Knowledge

You should know your way around. Not an expert. Just comfortable.

- Spin up an EC2 instance? You're good.
- Navigate IAM policies? You'll figure it out.
- Command line doesn't scare you? Perfect.

If you've never touched any of these clouds, grab a buddy or a coffee. You'll learn fast.

---

## Step 1: Set Up Authentication

You need to prove to each cloud that you own the account. It sounds simple. It is.

### AWS

First, the one you probably already have:

```bash
aws configure
```

It'll ask for access key, secret key, region. If you don't have keys, go to IAM console, create them (don't share them, obviously).

Then verify it worked:

```bash
aws sts get-caller-identity
```

You should see your AWS account ID. If not? Wrong keys or no permissions. Fix before moving on.

### GCP

This one's slightly different.

```bash
gcloud auth application-default login
gcloud config set project YOUR_GCP_PROJECT_ID
```

A browser window pops up. Sign in. Approve the scary warning. Then come back to terminal.

Verify:

```bash
gcloud projects describe YOUR_GCP_PROJECT_ID
```

Should show your project details. If it doesn't, your project ID is wrong or you don't have access.

### Azure

This one's the easiest.

```bash
az login
```

Browser opens. Sign in. Done. It remembers your subscription automatically.

Check it:

```bash
az account show
```

See your subscription ID? Good. You're in.

---

## Step 2: Prepare Configuration Files

### Clone or Download This Project

```bash
git clone https://github.com/thepragmaticarchitect/TPAlabs.git
cd TPAlabs/onboarding-portal/tf-onboarding-sample
```

### Create terraform.tfvars

Copy the example and fill in your values:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your details:

```hcl
environment = "dev"

# AWS
aws_region = "us-east-1"
entra_id_metadata_url = "https://login.microsoftonline.com/<your-tenant-id>/federationmetadata/2007-06/federationmetadata.xml"
entra_id_slo_url = "https://login.microsoftonline.com/<your-tenant-id>/saml2"

# GCP
gcp_project_id     = "your-gcp-project"
gcp_project_number = "123456789"
cognito_issuer_uri = "https://cognito-idp.us-east-1.amazonaws.com/<user-pool-id>"
cognito_client_id  = "<client-id>"
cloud_run_image    = "gcr.io/your-project/onboarding:latest"

# Azure
azure_subscription_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
azure_tenant_id       = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
azure_admin_object_id = "<your-object-id>"
```

---

## Step 3: Get Entra ID SAML Metadata

This is the annoying part. Enterprise users need to log in via their company Entra ID. Cognito needs Entra ID's SAML metadata to trust it.

I won't sugarcoat it: Microsoft's UI is confusing. But it's doable.

### In Azure Portal

1. Go to **Azure Active Directory** (search for it at the top).
2. Click **App registrations** → **New registration**.
3. Name it something like `OnboardingPortal-SAML`.
4. Pick **Accounts in this organizational directory only** (unless you're doing multi-tenant).
5. Register it.

Now the metadata part:

6. Click your app → **Single sign-on** in the left menu.
7. Pick **SAML** as the protocol.
8. Scroll down. You'll see **Federation Metadata Document URL**. Copy it:
   ```
   https://login.microsoftonline.com/{tenant-id}/federationmetadata/2007-06/federationmetadata.xml
   ```
   Paste this into `terraform.tfvars` later as `entra_id_metadata_url`.

9. Also grab the **Logout URL** (SLO endpoint):
   ```
   https://login.microsoftonline.com/{tenant-id}/saml2
   ```
   This goes into `entra_id_slo_url`.

10. Here's the important part: After you deploy Terraform (step 5), you'll get a Cognito domain. Come back and add this as a redirect URI:
    ```
    https://<cognito-domain>.auth.us-east-1.amazoncognito.com/saml2/idpResponse
    ```
    Cognito will send users back here after they log in with Entra ID.

Doing it backwards? Totally fine. Deploy first, then add the callback. Just don't forget.

---

## Step 4: Deploy AWS

### Initialize Terraform

```bash
terraform init
```

### Plan AWS Resources

```bash
terraform plan -var-file=terraform.tfvars | grep -E "aws_cognito|aws_s3|aws_dynamodb|aws_wafv2"
```

Expected: 9+ AWS resources planned (Cognito, S3 buckets, DynamoDB, WAF, KMS).

### Apply AWS

```bash
terraform apply -var-file=terraform.tfvars
```

Type `yes` to confirm.

#### What Happens During terraform apply

When you run `terraform apply`, Terraform:

1. **Reads all .tf files** (aws_main.tf, gcp_main.tf, azure_main.tf)
2. **Builds dependency graph** — determines order based on resource dependencies
3. **Creates independent resources in parallel** — multiple resources created simultaneously if no dependencies
4. **Waits for dependencies** — if resource B needs output from resource A, waits for A first
5. **Applies to each cloud** — AWS, GCP, Azure resources intermixed based on dependencies

#### Actual Execution Order (Example)

```
terraform apply

├─ AWS KMS Key (5s)
├─ AWS Cognito User Pool (10s)  ├─ AWS S3 Buckets (parallel, 3s each)
│  ├─ AWS Cognito Client
│  ├─ AWS Cognito Identity Provider (Entra ID)
│  └─ AWS Cognito Domain
│
├─ AWS DynamoDB OTP Table (5s)
├─ AWS WAF Web ACL (8s)
├─ AWS CloudWatch Log Group (2s)
│
├─ GCP KMS Key Ring + Crypto Key (15s) [WAITS for nothing]
├─ GCP WIF Pool (8s)
├─ GCP WIF Provider (8s) [NEEDS: cognito_issuer_uri from variables, no Terraform dependency]
├─ GCP Service Account (3s)
├─ GCP Cloud SQL Instance (60s) [SLOW — largest GCP resource]
├─ GCP Cloud Storage Bucket (3s)
├─ GCP VPC Network (5s)
└─ GCP Cloud Run Service (15s) [WAITS for VPC, Service Account]
│
├─ Azure Key Vault (15s)
├─ Azure Key Vault Key (5s)
├─ Azure Storage Account (10s)
├─ Azure Storage Containers (parallel, 2s each)
├─ Azure SQL Server (30s)
├─ Azure SQL Database (20s) [WAITS for SQL Server]
├─ Azure App Service Plan (5s)
├─ Azure App Service (10s) [WAITS for App Service Plan]
├─ Azure API Management (45s) [SLOW]
└─ Azure Log Analytics + Application Insights (parallel, 10s each)

Total time: ~120-180 seconds (2-3 minutes)
```

#### Key Points

**Parallel Execution:**
- All AWS resources (except those with dependencies) create in parallel
- All GCP resources (except those with dependencies) create in parallel
- All Azure resources (except those with dependencies) create in parallel
- AWS, GCP, Azure resources **interleave** — not strictly one cloud then the next

**Dependencies:**
- GCP WIF Provider needs `cognito_issuer_uri` and `cognito_client_id` from your `terraform.tfvars`
  - ⚠️ **NOT from AWS Terraform state** — you must manually fill in `terraform.tfvars` with AWS outputs first
  - This is intentional (allows independent cloud deployments)
- GCP Cloud Run waits for VPC and Service Account to exist
- Azure SQL Database waits for SQL Server
- Everything else is independent

**No Cross-Cloud Dependencies in Terraform:**
- Terraform doesn't automatically tie AWS outputs to GCP/Azure inputs
- You manually update `terraform.tfvars` with AWS outputs before deploying GCP/Azure
- This allows you to deploy clouds independently if needed

---

#### Why Not Automatic Cross-Cloud Linking?

In production, you'd use:
```hcl
# gcp_main.tf
cognito_issuer_uri = data.terraform_remote_state.aws.outputs.cognito_issuer_uri
```

But in this **sample**, we keep it simple:
- You control when to update `terraform.tfvars`
- You can deploy AWS only, or AWS + GCP, or all three
- You avoid accidental cross-cloud dependencies in a learning environment

For production, see `tf-onboarding-portal/` (full enterprise setup) where remote state is used.

### Capture AWS Outputs

```bash
terraform output -json > aws_outputs.json
```

Save these for later:
- `cognito_user_pool_id`
- `cognito_client_id`
- `cognito_domain`
- `s3_quarantine_bucket`
- `otp_tracker_table`

---

## Step 5: Deploy GCP

### Update terraform.tfvars with Cognito Details

From AWS outputs, update:
```hcl
cognito_issuer_uri = "https://cognito-idp.us-east-1.amazonaws.com/<pool-id>"
cognito_client_id  = "<client-id-from-aws>"
```

### Plan GCP Resources

```bash
terraform plan -var-file=terraform.tfvars | grep -E "google_iam|google_cloud_run|google_sql|google_storage"
```

Expected: 15+ GCP resources (WIF, Cloud Run, Cloud SQL, Storage).

### Apply GCP

```bash
terraform apply -var-file=terraform.tfvars
```

### Capture GCP Outputs

```bash
terraform output -json | jq '.[] | select(.value | type == "string") | {key: .key, value: .value}' > gcp_outputs.json
```

---

## Step 6: Deploy Azure

### Plan Azure Resources

```bash
terraform plan -var-file=terraform.tfvars | grep -E "azurerm_sql|azurerm_storage|azurerm_app_service"
```

Expected: 18+ Azure resources (SQL, Storage, App Service, APIM).

### Apply Azure

```bash
terraform apply -var-file=terraform.tfvars
```

---

## Step 7: Test the Deployment

Okay. It's built. Now make sure it actually works.

### Test AWS Cognito

#### 1. Access Cognito Hosted UI

Get the login link:

```bash
COGNITO_DOMAIN=$(terraform output -raw cognito_domain)
REGION="us-east-1"
CLIENT_ID=$(terraform output -raw cognito_client_id)

# Copy and paste this into your browser
echo "https://${COGNITO_DOMAIN}.auth.${REGION}.amazoncognito.com/login?client_id=${CLIENT_ID}&response_type=code&redirect_uri=http://localhost:3000/callback"
```

Open it. You should see the Cognito login page.

#### 2. Test Commercial User Flow

This is the normal user path. Sign up, verify email, log in.

1. Click **"Sign up"** (bottom of login page).
2. Email: `user+test@example.com` (the `+test` part stops Gmail spam).
3. Password: Needs uppercase, number, symbol. Something like `TestPass123!`.
4. Click **"Sign up"**.
5. Check your email (and spam folder). Cognito sends a confirmation code.
6. Paste the code. You're in.
7. Log back in with the same email and password.
8. Cognito asks for MFA. Pick authenticator app (or SMS if you set it up).
9. Done. You're logged in.

This flow works for employees or trusted users.

#### 3. Test Entra ID Federated Flow

This is the enterprise path. Users log in with their company credentials.

1. Go back to Cognito login page.
2. Look for the **"EntraID"** button (should be there if you deployed correctly).
3. Click it. You get redirected to Microsoft login.
4. Use your company Entra ID credentials. (Your personal Microsoft account won't work here.)
5. Microsoft asks you to consent to the app. Click "Accept."
6. You're redirected back to Cognito. Logged in.

This is what your enterprise customers use. Their company manages the password. You just trust Entra ID.

### Test S3 Document Upload

```bash
QUARANTINE_BUCKET=$(terraform output -raw s3_quarantine_bucket)

# Create test file
echo "test document content" > test.txt

# Upload via CLI (no Lambda scanning yet, just test bucket access)
aws s3 cp test.txt s3://${QUARANTINE_BUCKET}/test.txt --region us-east-1
```

Verify in AWS Console:
- S3 → `${QUARANTINE_BUCKET}` → object appears

### Test DynamoDB OTP Tracker

```bash
TABLE_NAME=$(terraform output -raw otp_tracker_table)

# Scan table (should be empty initially)
aws dynamodb scan --table-name ${TABLE_NAME} --region us-east-1
```

### Test WAF OTP Rate Limit

The WAF rule blocks more than 10 requests to `/auth/otp` per 5 minutes per IP.

```bash
COGNITO_DOMAIN=$(terraform output -raw cognito_domain)

# Simulate 11 requests in 5 minutes (request 11 will be blocked)
for i in {1..11}; do
  curl -X POST "https://${COGNITO_DOMAIN}.auth.us-east-1.amazoncognito.com/sign_up" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "ClientId=${CLIENT_ID}&Username=test$i&Password=TempPass123!&UserAttributes=email&AttributeValue=test$i@example.com"
  sleep 1
done

# Request 11 should return WAF block (403)
```

### Test GCP Workload Identity Federation

```bash
PROJECT_ID=$(gcloud config get-value project)

# List WIF pool
gcloud iam workload-identity-pools list --location=global --project=${PROJECT_ID}

# Output: should show "${environment}-cognito-pool"
```

### Test Azure App Service

```bash
APP_URL=$(terraform output -raw app_service_url)

# Test app is running
curl -I "https://${APP_URL}/health"

# Expected: 200 OK (if health endpoint exists) or 404 (if not implemented)
```

---

## Step 8: Clean Up

Done testing? Time to delete everything and save money.

### The Annoying Part: S3 Object Lock

Remember that `clean` S3 bucket? It has Object Lock enabled. 365-day retention. That means Terraform can't delete it. AWS won't let you delete it. Period. Not until 365 days pass.

This was intentional (protects customer documents in production). But for testing? It's a pain.

#### Option A: Disable It Manually (Recommended for Testing)

1. Go to **AWS Console → S3 → Buckets**.
2. Find the bucket named `dev-onboarding-clean-<your-account-id>`.
3. Click it → **Object Lock**.
4. Click **Edit** → **Disable** → **Confirm**.
5. Wait 30 seconds.

Now Terraform can delete it:

```bash
terraform destroy -var-file=terraform.tfvars
```

Type `yes`. Everything else deletes fine. Takes 2-3 minutes.

#### Option B: Leave It Alone

Don't want to mess with Object Lock? Just leave the bucket. It'll charge you storage costs (~$0.50/month for empty storage). After 365 days, the retention expires and it auto-deletes. Or you can manually delete it then.

#### Destroy Specific Clouds

Want to keep AWS but delete GCP and Azure? Do it:

```bash
terraform destroy -var-file=terraform.tfvars -target=azurerm_resource_group.main
terraform destroy -var-file=terraform.tfvars -target=google_iam_workload_identity_pool.cognito
```

Specify what to destroy. Terraform asks before deleting anything.

---

## Troubleshooting

Things break. Usually it's one of these.

### AWS Cognito SAML Not Working

You're trying to log in with Entra ID. It fails.

**Error:** "SAML metadata is invalid"

**What happened:** Entra ID and Cognito aren't talking.

**Fix it:**
1. Double-check your metadata URL. Copy-paste from Azure Portal. No typos.
2. Did you add the Cognito callback URL to Entra ID yet? Go back and do that if not.
3. Entra ID takes forever to sync. Wait 5 minutes. Not joking.
4. Run `terraform apply` again.

Still broken? Check the Cognito console and look at the SAML metadata field. It should match what you pasted.

### GCP WIF Token Exchange Fails

Your Cloud Run can't talk to AWS.

**Error:** "Token exchange failed: invalid_audience"

**What happened:** The audience in the Cognito token doesn't match what GCP expects.

**Fix it:**
1. In `terraform.tfvars`, is `cognito_client_id` exactly right? Copy it from AWS output. Paste it. No spaces.
2. `cognito_issuer_uri` needs to be perfect. No trailing slash. I've seen people add one. Don't.
3. Run this and make sure the pool actually exists:
   ```bash
   gcloud iam workload-identity-pools list --location=global
   ```
   You should see your pool.

### Azure App Service Won't Start

It's trying to pull a Docker image and failing.

**Error:** "Docker image pull failed"

**What happened:** Azure can't find or access your image.

**Fix it:**
1. Does your image actually exist? Go to your container registry and check.
2. Is it public or private? If private, did you provide registry credentials in `terraform.tfvars`? Both username and password?
3. Open Azure Portal → App Service → Logs → Application Logs. Read them. They're usually helpful.

This one's annoying because Azure logs are... sparse. But they'll point you in the right direction.

### Terraform State Lock

You ran two terraform commands at the same time. Terraform got confused.

**Error:** "Error acquiring the lock"

**Fix it:**
Just wait. Terraform releases the lock after the first command finishes.

If it's stuck for real (like a process crashed mid-terraform), you can nuke it:

```bash
rm .terraform.tfstate.lock.hcl
```

But only if you're sure nothing else is running.

---

## Estimated Costs

**AWS (monthly):**
- Cognito: ~$0.50 (auth requests)
- S3: ~$5 (storage + requests)
- DynamoDB: ~$1 (on-demand)
- WAF: ~$5
- Total: ~$11/month

**GCP (monthly):**
- Cloud Run: ~$0 (free tier, 2 million requests)
- Cloud SQL: ~$20 (db-f1-micro)
- Storage: ~$0.50
- Total: ~$20/month

**Azure (monthly):**
- App Service (B1): ~$15
- SQL Database (Basic): ~$5
- Storage: ~$0.50
- Total: ~$20/month

**Total: ~$50/month for dev environment**

---

## Next Steps

1. **Add Lambda for document scanning** — Integrate antivirus scanning
2. **Add API Gateway** — Wire Cognito authorizer
3. **Add RDS + RDS Proxy** — Customer data store
4. **Add CI/CD** — CodePipeline for deployments
5. **Cross-cloud connectivity** — Dedicated Interconnect / HA VPN

---

## Support

For issues:
1. Check Terraform logs: `TF_LOG=DEBUG terraform plan`
2. Check cloud provider logs in AWS Console, GCP Console, Azure Portal
3. Open issue on GitHub with plan output

---

**Lab Duration:** 30-45 minutes to deploy all three clouds
**Difficulty:** Intermediate (requires cloud account knowledge)
