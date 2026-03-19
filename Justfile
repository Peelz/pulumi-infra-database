# Pulumi IaC Database - Justfile
# Run `just --list` to see all available commands

# Default recipe - show help
default:
    @just --list

# ============================================
# Configuration
# ============================================

# Default GCP region
default_region := "asia-southeast1"

# KMS keyring name
kms_keyring := "pulumi-secrets"

# ============================================
# Aliases for environments
# ============================================

# Alias: Initialize dev environment
alias dev := init-dev

# Alias: Initialize prod environment  
alias prod := init-prod

# ============================================
# Setup & Dependencies
# ============================================

# Create virtual environment and install dependencies
setup:
    python -m venv venv
    . venv/bin/activate && pip install -r requirements.txt
    @echo "✓ Setup complete. Run: source venv/bin/activate"

# Install dependencies only (venv must exist)
install:
    . venv/bin/activate && pip install -r requirements.txt

# ============================================
# Onboarding - Full Setup
# ============================================

# Full onboarding: bucket + KMS + stacks (interactive)
onboard project_id region=default_region:
    ./scripts/onboard.sh {{ project_id }} {{ region }}

# ============================================
# GCS Bucket Management
# ============================================

# Create GCS bucket for Pulumi state
bucket-create project_id region=default_region:
    #!/usr/bin/env bash
    set -euo pipefail
    bucket_name="pulumi-state-{{ project_id }}"
    echo "Creating GCS bucket: ${bucket_name}..."
    if gsutil ls -b "gs://${bucket_name}" &>/dev/null; then
        echo "⚠ Bucket ${bucket_name} already exists"
    else
        gsutil mb -p "{{ project_id }}" -l "{{ region }}" -b on "gs://${bucket_name}"
        gsutil versioning set on "gs://${bucket_name}"
        echo "✓ Bucket created with versioning enabled"
    fi

# Login to Pulumi with GCS backend
bucket-login project_id:
    pulumi login "gs://pulumi-state-{{ project_id }}"

# ============================================
# KMS Key Management
# ============================================

# Create KMS keyring
kms-keyring-create project_id region=default_region:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Creating KMS keyring: {{ kms_keyring }}..."
    if gcloud kms keyrings describe "{{ kms_keyring }}" --location="{{ region }}" --project="{{ project_id }}" &>/dev/null; then
        echo "⚠ Keyring {{ kms_keyring }} already exists"
    else
        gcloud kms keyrings create "{{ kms_keyring }}" --location="{{ region }}" --project="{{ project_id }}"
        echo "✓ Keyring created"
    fi

# Create KMS key for dev environment
kms-dev project_id region=default_region: (kms-key-create project_id region "dev-key")

# Create KMS key for prod environment
kms-prod project_id region=default_region: (kms-key-create project_id region "prod-key")

# Create KMS key (internal)
kms-key-create project_id region key_name:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Creating KMS key: {{ key_name }}..."
    if gcloud kms keys describe "{{ key_name }}" --keyring="{{ kms_keyring }}" --location="{{ region }}" --project="{{ project_id }}" &>/dev/null; then
        echo "⚠ Key {{ key_name }} already exists"
    else
        gcloud kms keys create "{{ key_name }}" \
            --keyring="{{ kms_keyring }}" \
            --location="{{ region }}" \
            --purpose="encryption" \
            --project="{{ project_id }}"
        echo "✓ Key {{ key_name }} created"
    fi

# Create all KMS keys (keyring + dev + prod)
kms-all project_id region=default_region: (kms-keyring-create project_id region) (kms-dev project_id region) (kms-prod project_id region)

# ============================================
# Stack Initialization
# ============================================

# Initialize dev stacks (postgresql-dev, mongodb-dev)
init-dev project_id region=default_region: (stack-init project_id region "postgresql" "dev") (stack-init project_id region "mongodb" "dev")
    @echo "✓ Dev stacks initialized"

# Initialize prod stacks (postgresql-prod, mongodb-prod)
init-prod project_id region=default_region: (stack-init project_id region "postgresql" "prod") (stack-init project_id region "mongodb" "prod")
    @echo "✓ Prod stacks initialized"

# Initialize all stacks
init-all project_id region=default_region: (init-dev project_id region) (init-prod project_id region)
    @echo "✓ All stacks initialized"

# Initialize a specific stack (internal)
stack-init project_id region service env:
    #!/usr/bin/env bash
    set -euo pipefail
    stack_name="{{ service }}-{{ env }}"
    secrets_provider="gcpkms://projects/{{ project_id }}/locations/{{ region }}/keyRings/{{ kms_keyring }}/cryptoKeys/{{ env }}-key"
    
    echo "Initializing stack: ${stack_name}..."
    if pulumi stack ls 2>/dev/null | grep -q "^${stack_name}"; then
        echo "⚠ Stack ${stack_name} already exists"
    else
        pulumi stack init "${stack_name}" --secrets-provider="${secrets_provider}"
        pulumi stack select "${stack_name}"
        pulumi config set gcp:project "{{ project_id }}"
        pulumi config set service_type "{{ service }}"
        pulumi config set environment "{{ env }}"
        echo "✓ Stack ${stack_name} initialized"
    fi

# Initialize PostgreSQL dev stack only
init-postgresql-dev project_id region=default_region: (stack-init project_id region "postgresql" "dev")

# Initialize PostgreSQL prod stack only
init-postgresql-prod project_id region=default_region: (stack-init project_id region "postgresql" "prod")

# Initialize MongoDB dev stack only
init-mongodb-dev project_id region=default_region: (stack-init project_id region "mongodb" "dev")

# Initialize MongoDB prod stack only
init-mongodb-prod project_id region=default_region: (stack-init project_id region "mongodb" "prod")

# ============================================
# Quick Start (Bucket + KMS + Stacks)
# ============================================

# Quick start for dev: bucket + KMS + dev stacks
quickstart-dev project_id region=default_region: (bucket-create project_id region) (bucket-login project_id) (kms-keyring-create project_id region) (kms-dev project_id region) (init-dev project_id region)
    @echo ""
    @echo "✓ Dev environment ready!"
    @echo ""
    @echo "Next steps:"
    @echo "  pulumi stack select postgresql-dev"
    @echo "  pulumi config set --secret postgres_password 'your-password'"
    @echo "  pulumi up"

# Quick start for prod: bucket + KMS + prod stacks
quickstart-prod project_id region=default_region: (bucket-create project_id region) (bucket-login project_id) (kms-keyring-create project_id region) (kms-prod project_id region) (init-prod project_id region)
    @echo ""
    @echo "✓ Prod environment ready!"
    @echo ""
    @echo "Next steps:"
    @echo "  pulumi stack select postgresql-prod"
    @echo "  pulumi config set --secret postgres_password 'your-password'"
    @echo "  pulumi up"

# Quick start all: bucket + all KMS + all stacks
quickstart-all project_id region=default_region: (bucket-create project_id region) (bucket-login project_id) (kms-all project_id region) (init-all project_id region)
    @echo ""
    @echo "✓ All environments ready!"

# ============================================
# Pulumi Operations
# ============================================

# Select a stack
select stack:
    pulumi stack select {{ stack }}

# Preview changes for current stack
preview:
    pulumi preview

# Deploy current stack
up:
    pulumi up

# Destroy current stack
destroy:
    pulumi destroy

# Show stack outputs
output:
    pulumi stack output

# List all stacks
stacks:
    pulumi stack ls

# ============================================
# Linting & Formatting
# ============================================

# Run ruff linter
lint:
    ruff check .

# Fix lint errors automatically
lint-fix:
    ruff check . --fix

# Format code with ruff
fmt:
    ruff format .

# Check formatting without changes
fmt-check:
    ruff format . --check

# ============================================
# Testing
# ============================================

# Run all tests
test:
    pytest

# Run tests with verbose output
test-verbose:
    pytest -v

# Run a single test file
test-file file:
    pytest {{ file }}

# Run a single test function
test-one file test:
    pytest {{ file }}::{{ test }}

# ============================================
# GCP APIs
# ============================================

# Enable required GCP APIs
enable-apis project_id:
    gcloud services enable storage.googleapis.com --project="{{ project_id }}"
    gcloud services enable cloudkms.googleapis.com --project="{{ project_id }}"
    gcloud services enable sqladmin.googleapis.com --project="{{ project_id }}"
    @echo "✓ APIs enabled"
