# POC IAC Database

Multi-service database infrastructure template using Pulumi with GCP Cloud SQL PostgreSQL and MongoDB Atlas.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         ONBOARDING (Bootstrap)                       │
│  ./scripts/onboard.sh - Creates GCS bucket + KMS keyring/keys       │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         PULUMI BACKEND (GCS)                         │
│  gs://pulumi-state-{project-id}/                                    │
│    ├── postgresql-dev/                                              │
│    ├── postgresql-prod/                                             │
│    ├── mongodb-dev/                                                 │
│    └── mongodb-prod/                                                │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         GCP KMS (Secrets Encryption)                 │
│  Keyring: pulumi-secrets                                            │
│    ├── dev-key    → encrypts dev stack secrets                     │
│    └── prod-key   → encrypts prod stack secrets                    │
└─────────────────────────────────────────────────────────────────────┘
```

## Project Structure

```
poc-iac-database/
├── scripts/
│   └── onboard.sh              # Bootstrap script
├── __main__.py                 # Main entry point
├── cloudsql_postgres.py        # PostgreSQL module
├── mongodb_atlas.py            # MongoDB Atlas module
├── Pulumi.yaml                 # Project config
├── Pulumi.postgresql-dev.yaml  # PostgreSQL dev stack
├── Pulumi.postgresql-prod.yaml # PostgreSQL prod stack
├── Pulumi.mongodb-dev.yaml     # MongoDB dev stack
├── Pulumi.mongodb-prod.yaml    # MongoDB prod stack
├── requirements.txt            # Python dependencies
└── README.md
```

## Stack Naming Convention

Pattern: `{service}-{env}`

| Stack | Service | Environment |
|-------|---------|-------------|
| `postgresql-dev` | Cloud SQL PostgreSQL | Development |
| `postgresql-prod` | Cloud SQL PostgreSQL | Production |
| `mongodb-dev` | MongoDB Atlas | Development |
| `mongodb-prod` | MongoDB Atlas | Production |

## Prerequisites

1. **GCP CLI** - Install and authenticate
   ```bash
   gcloud auth login
   gcloud auth application-default login
   ```

2. **Pulumi CLI** - Install from https://www.pulumi.com/docs/install/

3. **Python 3.9+** - Required for Pulumi Python runtime

4. **MongoDB Atlas Account** - Required for MongoDB stacks
   - Create an organization at https://cloud.mongodb.com
   - Generate API keys (Organization Access Manager → API Keys)

---

## Onboarding

The onboarding script bootstraps all required infrastructure for Pulumi state management and secrets encryption.

### What it creates

| Resource | Name | Purpose |
|----------|------|---------|
| **GCS Bucket** | `pulumi-state-{project-id}` | Stores Pulumi state files with versioning |
| **KMS Keyring** | `pulumi-secrets` | Contains encryption keys |
| **KMS Key** | `dev-key` | Encrypts secrets for dev stacks |
| **KMS Key** | `prod-key` | Encrypts secrets for prod stacks |
| **Pulumi Stacks** | `postgresql-dev`, `postgresql-prod`, `mongodb-dev`, `mongodb-prod` | Infrastructure stacks |

### Quick Start (Automated)

```bash
# Make script executable
chmod +x ./scripts/onboard.sh

# Run onboarding
./scripts/onboard.sh <gcp-project-id> [region]

# Example
./scripts/onboard.sh my-gcp-project asia-southeast1
```

### Manual Onboarding (Step-by-Step)

If you prefer to run steps manually or need to understand each step:

#### Step 1: Set Environment Variables

```bash
export PROJECT_ID="your-gcp-project-id"
export REGION="asia-southeast1"
export BUCKET_NAME="pulumi-state-${PROJECT_ID}"
export KMS_KEYRING="pulumi-secrets"
```

#### Step 2: Enable Required GCP APIs

```bash
gcloud services enable storage.googleapis.com --project="$PROJECT_ID"
gcloud services enable cloudkms.googleapis.com --project="$PROJECT_ID"
gcloud services enable sqladmin.googleapis.com --project="$PROJECT_ID"
```

#### Step 3: Create GCS Bucket for Pulumi State

```bash
# Create bucket with uniform bucket-level access
gsutil mb -p "$PROJECT_ID" -l "$REGION" -b on "gs://${BUCKET_NAME}"

# Enable versioning for state file protection
gsutil versioning set on "gs://${BUCKET_NAME}"
```

#### Step 4: Create KMS Keyring

```bash
gcloud kms keyrings create "$KMS_KEYRING" \
    --location="$REGION" \
    --project="$PROJECT_ID"
```

#### Step 5: Create KMS Keys for Each Environment

```bash
# Dev environment key
gcloud kms keys create "dev-key" \
    --keyring="$KMS_KEYRING" \
    --location="$REGION" \
    --purpose="encryption" \
    --project="$PROJECT_ID"

# Prod environment key
gcloud kms keys create "prod-key" \
    --keyring="$KMS_KEYRING" \
    --location="$REGION" \
    --purpose="encryption" \
    --project="$PROJECT_ID"
```

#### Step 6: Login to Pulumi with GCS Backend

```bash
pulumi login "gs://${BUCKET_NAME}"
```

#### Step 7: Initialize Pulumi Stacks with KMS Encryption

```bash
# PostgreSQL Dev
pulumi stack init postgresql-dev \
    --secrets-provider="gcpkms://projects/${PROJECT_ID}/locations/${REGION}/keyRings/${KMS_KEYRING}/cryptoKeys/dev-key"

# PostgreSQL Prod
pulumi stack init postgresql-prod \
    --secrets-provider="gcpkms://projects/${PROJECT_ID}/locations/${REGION}/keyRings/${KMS_KEYRING}/cryptoKeys/prod-key"

# MongoDB Dev
pulumi stack init mongodb-dev \
    --secrets-provider="gcpkms://projects/${PROJECT_ID}/locations/${REGION}/keyRings/${KMS_KEYRING}/cryptoKeys/dev-key"

# MongoDB Prod
pulumi stack init mongodb-prod \
    --secrets-provider="gcpkms://projects/${PROJECT_ID}/locations/${REGION}/keyRings/${KMS_KEYRING}/cryptoKeys/prod-key"
```

#### Step 8: Set Default Config for Each Stack

```bash
for stack in postgresql-dev postgresql-prod mongodb-dev mongodb-prod; do
    pulumi stack select "$stack"
    pulumi config set gcp:project "$PROJECT_ID"
    
    # Extract service and environment from stack name
    service=$(echo "$stack" | cut -d'-' -f1)
    env=$(echo "$stack" | cut -d'-' -f2)
    
    pulumi config set service_type "$service"
    pulumi config set environment "$env"
done
```

---

## Configuration

### PostgreSQL Stacks

```bash
# Select stack
pulumi stack select postgresql-dev  # or postgresql-prod

# Required: Set GCP project
pulumi config set gcp:project <your-gcp-project-id>

# Required: Set database password (encrypted with KMS)
pulumi config set --secret postgres_password <password>

# Optional: Override defaults
pulumi config set postgres_tier db-custom-2-4096
pulumi config set postgres_disk_size 50
pulumi config set postgres_private_network projects/<project>/global/networks/<network>
```

### MongoDB Stacks

```bash
# Select stack
pulumi stack select mongodb-dev  # or mongodb-prod

# Required: Set MongoDB Atlas API keys
pulumi config set mongodbatlas:publicKey <public-key>
pulumi config set --secret mongodbatlas:privateKey <private-key>

# Required: Set organization ID and password
pulumi config set mongodb_atlas_org_id <org-id>
pulumi config set --secret mongodb_password <password>

# Optional: Override defaults
pulumi config set mongodb_tier M10
pulumi config set mongodb_allowed_cidr "10.0.0.0/8"
```

---

## Environment Sizing

### PostgreSQL

| Setting | Dev | Prod |
|---------|-----|------|
| Tier | `db-f1-micro` | `db-custom-2-4096` |
| Availability | ZONAL | REGIONAL (HA) |
| Disk Size | 10 GB | 50 GB |
| Backup Retention | 3 days | 14 days |
| Point-in-Time Recovery | No | Yes |
| Deletion Protection | No | Yes |

### MongoDB Atlas

| Setting | Dev | Prod |
|---------|-----|------|
| Tier | M0 (Free) | M10 |
| Cloud Backup | Disabled | Enabled |
| Auto-scaling | Disabled | Enabled |

---

## Deployment

```bash
# Select stack
pulumi stack select postgresql-dev

# Preview changes
pulumi preview

# Deploy
pulumi up

# View outputs
pulumi stack output
```

---

## Outputs

### PostgreSQL

| Output | Description |
|--------|-------------|
| `postgres_instance_name` | Cloud SQL instance name |
| `postgres_connection_name` | Connection name for Cloud SQL Proxy |
| `postgres_public_ip` | Public IP address (if enabled) |
| `postgres_private_ip` | Private IP address |
| `postgres_database_name` | Database name |
| `postgres_user_name` | Database user name |

### MongoDB

| Output | Description |
|--------|-------------|
| `mongodb_project_id` | Atlas project ID |
| `mongodb_cluster_name` | Cluster name |
| `mongodb_connection_string` | SRV connection string |
| `mongodb_user_name` | Database user name |

---

## Cleanup

```bash
# Destroy resources (per stack)
pulumi stack select postgresql-dev
pulumi destroy

# Remove stack (optional)
pulumi stack rm postgresql-dev
```

---

## Troubleshooting

### KMS Permission Denied

Ensure your account has the required IAM roles:

```bash
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="user:your-email@example.com" \
    --role="roles/cloudkms.cryptoKeyEncrypterDecrypter"
```

### GCS Bucket Access Denied

Ensure your account has storage permissions:

```bash
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="user:your-email@example.com" \
    --role="roles/storage.admin"
```

### MongoDB Atlas API Error

1. Verify API keys are correct
2. Ensure API key has "Organization Owner" or "Organization Project Creator" role
3. Check IP access list allows your current IP

### Pulumi Login Issues

```bash
# Check current backend
pulumi whoami -v

# Re-login to GCS backend
pulumi login "gs://pulumi-state-${PROJECT_ID}"
```
