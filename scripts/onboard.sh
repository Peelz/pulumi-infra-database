#!/bin/bash
set -euo pipefail

#
# Pulumi Onboarding Script
# Creates GCS bucket for state storage and GCP KMS keys for secrets encryption
#
# Usage: ./onboard.sh <gcp-project-id> [region]
# Example: ./onboard.sh my-gcp-project asia-southeast1
#

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
DEFAULT_REGION="asia-southeast1"
KMS_KEYRING="pulumi-secrets"
ENVIRONMENTS=("dev" "prod")
SERVICES=("postgresql" "mongodb")

# Functions
log_info() {
	echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
	echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
	echo -e "${RED}[ERROR]${NC} $1"
}

check_dependencies() {
	log_info "Checking dependencies..."

	if ! command -v gcloud &>/dev/null; then
		log_error "gcloud CLI is not installed. Please install it first."
		exit 1
	fi

	if ! command -v pulumi &>/dev/null; then
		log_error "pulumi CLI is not installed. Please install it first."
		exit 1
	fi

	log_info "All dependencies are installed."
}

enable_apis() {
	local project_id=$1

	log_info "Enabling required GCP APIs..."

	gcloud services enable storage.googleapis.com --project="$project_id"
	gcloud services enable cloudkms.googleapis.com --project="$project_id"
	gcloud services enable sqladmin.googleapis.com --project="$project_id"

	log_info "APIs enabled successfully."
}

create_gcs_bucket() {
	local project_id=$1
	local region=$2
	local bucket_name="pulumi-state-${project_id}"

	log_info "Creating GCS bucket: ${bucket_name}..."

	if gsutil ls -b "gs://${bucket_name}" &>/dev/null; then
		log_warn "Bucket ${bucket_name} already exists. Skipping creation."
	else
		gsutil mb -p "$project_id" -l "$region" -b on "gs://${bucket_name}"

		# Enable versioning for state protection
		gsutil versioning set on "gs://${bucket_name}"

		log_info "Bucket created with versioning enabled."
	fi

	echo "$bucket_name"
}

create_kms_keyring() {
	local project_id=$1
	local region=$2
	local keyring=$3

	log_info "Creating KMS keyring: ${keyring}..."

	if gcloud kms keyrings describe "$keyring" --location="$region" --project="$project_id" &>/dev/null; then
		log_warn "Keyring ${keyring} already exists. Skipping creation."
	else
		gcloud kms keyrings create "$keyring" \
			--location="$region" \
			--project="$project_id"

		log_info "Keyring created successfully."
	fi
}

create_kms_key() {
	local project_id=$1
	local region=$2
	local keyring=$3
	local key_name=$4

	log_info "Creating KMS key: ${key_name}..."

	if gcloud kms keys describe "$key_name" --keyring="$keyring" --location="$region" --project="$project_id" &>/dev/null; then
		log_warn "Key ${key_name} already exists. Skipping creation."
	else
		gcloud kms keys create "$key_name" \
			--keyring="$keyring" \
			--location="$region" \
			--purpose="encryption" \
			--project="$project_id"

		log_info "Key ${key_name} created successfully."
	fi
}

login_pulumi_gcs() {
	local bucket_name=$1

	log_info "Logging into Pulumi with GCS backend..."
	pulumi login "gs://${bucket_name}"
	log_info "Pulumi logged in to GCS backend."
}

init_pulumi_stacks() {
	local project_id=$1
	local region=$2
	local keyring=$3

	log_info "Initializing Pulumi stacks..."

	for service in "${SERVICES[@]}"; do
		for env in "${ENVIRONMENTS[@]}"; do
			local stack_name="${service}-${env}"
			local kms_key="${env}-key"
			local secrets_provider="gcpkms://projects/${project_id}/locations/${region}/keyRings/${keyring}/cryptoKeys/${kms_key}"

			log_info "Initializing stack: ${stack_name}..."

			if pulumi stack ls 2>/dev/null | grep -q "^${stack_name}"; then
				log_warn "Stack ${stack_name} already exists. Skipping."
			else
				pulumi stack init "$stack_name" --secrets-provider="$secrets_provider"
				log_info "Stack ${stack_name} initialized."
			fi
		done
	done
}

set_default_configs() {
	local project_id=$1

	log_info "Setting default configurations for each stack..."

	for service in "${SERVICES[@]}"; do
		for env in "${ENVIRONMENTS[@]}"; do
			local stack_name="${service}-${env}"

			log_info "Configuring stack: ${stack_name}..."
			pulumi stack select "$stack_name"

			# Set GCP project
			pulumi config set gcp:project "$project_id"

			# Set service type and environment
			pulumi config set service_type "$service"
			pulumi config set environment "$env"
		done
	done

	log_info "Default configurations set."
}

print_next_steps() {
	local project_id=$1

	echo ""
	echo "=============================================="
	echo -e "${GREEN}Onboarding Complete!${NC}"
	echo "=============================================="
	echo ""
	echo "Next steps:"
	echo ""
	echo "1. Configure PostgreSQL stacks:"
	echo "   pulumi stack select postgresql-dev"
	echo "   pulumi config set --secret postgres_password 'your-dev-password'"
	echo ""
	echo "   pulumi stack select postgresql-prod"
	echo "   pulumi config set --secret postgres_password 'your-prod-password'"
	echo ""
	echo "2. Configure MongoDB Atlas stacks:"
	echo "   pulumi config set mongodbatlas:publicKey 'your-public-key'"
	echo "   pulumi config set --secret mongodbatlas:privateKey 'your-private-key'"
	echo ""
	echo "   pulumi stack select mongodb-dev"
	echo "   pulumi config set mongodb_atlas_org_id 'your-org-id'"
	echo "   pulumi config set --secret mongodb_password 'your-dev-password'"
	echo ""
	echo "   pulumi stack select mongodb-prod"
	echo "   pulumi config set mongodb_atlas_org_id 'your-org-id'"
	echo "   pulumi config set --secret mongodb_password 'your-prod-password'"
	echo ""
	echo "3. Deploy:"
	echo "   pulumi stack select postgresql-dev && pulumi up"
	echo "   pulumi stack select mongodb-dev && pulumi up"
	echo ""
}

# Main
main() {
	if [[ $# -lt 1 ]]; then
		log_error "Usage: $0 <gcp-project-id> [region]"
		log_error "Example: $0 my-gcp-project asia-southeast1"
		exit 1
	fi

	local PROJECT_ID=$1
	local REGION=${2:-$DEFAULT_REGION}

	echo "=============================================="
	echo "Pulumi Onboarding Script"
	echo "=============================================="
	echo "Project ID: ${PROJECT_ID}"
	echo "Region: ${REGION}"
	echo "=============================================="
	echo ""

	# Confirm before proceeding
	read -p "Continue with onboarding? (y/N) " -n 1 -r
	echo
	if [[ ! $REPLY =~ ^[Yy]$ ]]; then
		log_info "Onboarding cancelled."
		exit 0
	fi

	# Run onboarding steps
	check_dependencies
	enable_apis "$PROJECT_ID"

	BUCKET_NAME=$(create_gcs_bucket "$PROJECT_ID" "$REGION")

	create_kms_keyring "$PROJECT_ID" "$REGION" "$KMS_KEYRING"

	for env in "${ENVIRONMENTS[@]}"; do
		create_kms_key "$PROJECT_ID" "$REGION" "$KMS_KEYRING" "${env}-key"
	done

	login_pulumi_gcs "$BUCKET_NAME"
	init_pulumi_stacks "$PROJECT_ID" "$REGION" "$KMS_KEYRING"
	set_default_configs "$PROJECT_ID"

	print_next_steps "$PROJECT_ID"
}

main "$@"
