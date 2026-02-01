#!/bin/bash
# Doris GCP Cluster Complete Cleanup Script
# WARNING: This will permanently delete all resources including data

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
    echo "Usage: $0 <environment>"
    echo ""
    echo "Environments:"
    echo "  dev   - Development environment"
    echo "  sit   - System Integration Testing"
    echo "  uat   - User Acceptance Testing"
    echo "  prod  - Production environment"
    echo ""
    echo -e "${RED}WARNING: This will permanently delete ALL resources including:${NC}"
    echo "  - Compute instances"
    echo "  - Persistent disks (FE meta, BE storage)"
    echo "  - GCS buckets (Cold storage data)"
    echo "  - ALL DATA stored in Doris"
    echo ""
    echo -e "${RED}This action CANNOT be undone!${NC}"
    echo ""
    exit 1
}

if [ -z "$1" ]; then
    usage
fi

ENVIRONMENT=$1
TFVARS_FILE="terraform.tfvars.${ENVIRONMENT}"

echo -e "${RED}========================================${NC}"
echo -e "${RED}Doris GCP Cluster Complete Cleanup${NC}"
echo -e "${RED}========================================${NC}"
echo -e "${YELLOW}Environment: ${ENVIRONMENT}${NC}"
echo ""
echo -e "${RED}WARNING: This will permanently delete ALL resources and DATA!${NC}"
echo -e "${RED}This includes:${NC}"
echo "  - All compute instances"
echo "  - All persistent disks (FE meta, BE storage)"
echo "  - GCS buckets and all cold storage data"
echo "  - ALL Doris data - HOT and COLD"
echo ""
echo -e "${RED}This action CANNOT be undone!${NC}"
echo ""

read -p "Type 'DELETE ALL DATA' to confirm: " confirm1
if [ "$confirm1" != "DELETE ALL DATA" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

read -p "Are you absolutely sure? This will delete all data permanently. Type 'YES DELETE EVERYTHING': " confirm2
if [ "$confirm2" != "YES DELETE EVERYTHING" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo -e "${YELLOW}Starting complete cleanup...${NC}"

# Get project info
PROJECT_ID=$(grep -E "^project_id" "$TFVARS_FILE" | cut -d'"' -f2)
CLUSTER_NAME=$(grep -E "^cluster_name" "$TFVARS_FILE" | cut -d'"' -f2)
ENV_TAG=$(grep -E "^environment" "$TFVARS_FILE" | cut -d'"' -f2)

echo -e "${YELLOW}[1/5] Initializing Terraform...${NC}"
terraform init

echo -e "${YELLOW}[2/5] Destroying Terraform resources...${NC}"
terraform destroy -var-file="$TFVARS_FILE" -auto-approve || true

echo -e "${YELLOW}[3/5] Removing orphaned disks...${NC}"
gcloud compute disks list --project="$PROJECT_ID" --filter="name:${CLUSTER_NAME}-${ENV_TAG}" --format="value(name)" 2>/dev/null | \
while read disk; do
    if [ -n "$disk" ]; then
        echo "  Deleting disk: $disk"
        ZONE=$(gcloud compute disks describe "$disk" --project="$PROJECT_ID" --format="value(zone.basename())" 2>/dev/null)
        if [ -n "$ZONE" ]; then
            gcloud compute disks delete "$disk" --project="$PROJECT_ID" --zone="$ZONE" --quiet || true
        fi
    fi
done

echo -e "${YELLOW}[4/5] Removing GCS buckets...${NC}"
gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep -i "${CLUSTER_NAME}-${ENV_TAG}" | while read bucket; do
    if [ -n "$bucket" ]; then
        echo "  Deleting bucket: $bucket"
        gsutil -m rm -r "$bucket" 2>/dev/null || true
    fi
done

echo -e "${YELLOW}[5/5] Cleaning Terraform state...${NC}"
rm -f terraform.tfstate terraform.tfstate.backup .terraform.lock.hcl

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Complete cleanup finished!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${RED}All resources and data have been permanently deleted.${NC}"
echo ""
