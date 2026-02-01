#!/bin/bash
# Doris GCP Cluster Complete Cleanup Script
# WARNING: This will permanently delete all resources including data

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Usage function
usage() {
    echo "Usage: $0 <environment>"
    echo ""
    echo "Environments:"
    echo "  dev   - Development environment"
    echo "  sit   - System Integration Testing"
    echo "  uat   - User Acceptance Testing"
    echo "  prod  - Production environment"
    echo ""
    echo -e "${RED}WARNING: This will permanently delete all resources including:${NC}"
    echo "  - Compute instances"
    echo "  - Persistent disks"
    echo "  - GCS buckets"
    echo "  - All data stored in Doris"
    echo ""
    echo "Examples:"
    echo "  $0 dev"
    echo "  $0 prod"
    exit 1
}

# Check if environment is provided
if [ -z "$1" ]; then
    usage
fi

ENVIRONMENT=$1
TFVARS_FILE="terraform.tfvars.${ENVIRONMENT}"

# Validate environment
case $ENVIRONMENT in
    dev|sit|uat|prod)
        ;;
    *)
        echo -e "${RED}Error: Invalid environment '${ENVIRONMENT}'${NC}"
        exit 1
        ;;
esac

echo -e "${RED}========================================${NC}"
echo -e "${RED}Doris GCP Cluster Complete Cleanup${NC}"
echo -e "${RED}========================================${NC}"
echo -e "${YELLOW}Environment: ${ENVIRONMENT}${NC}"
echo ""
echo -e "${RED}WARNING: This will permanently delete ALL resources and DATA!${NC}"
echo -e "${RED}This action cannot be undone!${NC}"
echo ""

# Require multiple confirmations
read -p "Type 'DELETE ALL' to confirm: " confirm1
if [ "$confirm1" != "DELETE ALL" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

read -p "Are you absolutely sure? This will delete all data. Type 'YES' to proceed: " confirm2
if [ "$confirm2" != "YES" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo -e "${YELLOW}Starting complete cleanup...${NC}"

# Get project ID
PROJECT_ID=$(grep -E "^project_id" "$TFVARS_FILE" | cut -d'"' -f2)
CLUSTER_NAME=$(grep -E "^cluster_name" "$TFVARS_FILE" | cut -d'"' -f2)
ENV_TAG=$(grep -E "^environment" "$TFVARS_FILE" | cut -d'"' -f2)

echo -e "${YELLOW}[1/5] Initializing Terraform...${NC}"
terraform init

echo -e "${YELLOW}[2/5] Destroying Terraform resources...${NC}"
terraform destroy -var-file="$TFVARS_FILE" -auto-approve || true

echo -e "${YELLOW}[3/5] Removing orphaned disks...${NC}"
gcloud compute disks list --project="$PROJECT_ID" --filter="name:${CLUSTER_NAME}-${ENV_TAG}" --format="value(name)" | \
while read disk; do
    echo "  Deleting disk: $disk"
    gcloud compute disks delete "$disk" --project="$PROJECT_ID" --zone=$(gcloud compute disks describe "$disk" --project="$PROJECT_ID" --format="value(zone)") --quiet || true
done

echo -e "${YELLOW}[4/5] Removing GCS buckets...${NC}"
gsutil ls -p "$PROJECT_ID" | grep -i "${CLUSTER_NAME}-${ENV_TAG}" | while read bucket; do
    echo "  Deleting bucket: $bucket"
    gsutil -m rm -r "$bucket" || true
done

echo -e "${YELLOW}[5/5] Cleaning Terraform state...${NC}"
rm -f terraform.tfstate terraform.tfstate.backup .terraform.lock.hcl

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Complete cleanup finished!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "All resources and data have been permanently deleted."
echo ""
