#!/bin/bash
# Doris GCP Compute Storage Separation Cluster Destruction Script

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
    echo "Note: Persistent disks and GCS buckets will be preserved."
    echo "      Data will NOT be lost."
    echo ""
    exit 1
}

if [ -z "$1" ]; then
    usage
fi

ENVIRONMENT=$1
TFVARS_FILE="terraform.tfvars.${ENVIRONMENT}"

case $ENVIRONMENT in
    dev|sit|uat|prod)
        ;;
    *)
        echo -e "${RED}Error: Invalid environment '${ENVIRONMENT}'${NC}"
        exit 1
        ;;
esac

if [ ! -f "$TFVARS_FILE" ]; then
    echo -e "${RED}Error: Configuration file '$TFVARS_FILE' not found${NC}"
    exit 1
fi

echo -e "${RED}========================================${NC}"
echo -e "${RED}Doris GCP Cluster Destruction${NC}"
echo -e "${RED}========================================${NC}"
echo -e "${YELLOW}Environment: ${ENVIRONMENT}${NC}"
echo -e "${YELLOW}Config File: ${TFVARS_FILE}${NC}"
echo ""
echo -e "${GREEN}Note: Persistent disks and GCS buckets will be preserved.${NC}"
echo -e "${GREEN}      Your data is safe!${NC}"
echo ""

read -p "Are you sure you want to destroy the cluster? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Destruction cancelled."
    exit 0
fi

echo -e "${YELLOW}[1/2] Initializing Terraform...${NC}"
terraform init

echo -e "${YELLOW}[2/2] Destroying cluster...${NC}"
terraform destroy -var-file="$TFVARS_FILE" -auto-approve

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cluster destroyed successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Preserved Resources:${NC}"
echo "  - FE Meta Disks (Persistent)"
echo "  - BE Storage Disks (Persistent)"
echo "  - GCS Bucket (Cold Storage)"
echo ""
echo -e "${BLUE}To redeploy with existing data:${NC}"
echo "  ./deploy.sh ${ENVIRONMENT}"
echo ""
echo -e "${BLUE}To permanently delete all data:${NC}"
echo "  ./clean-all.sh ${ENVIRONMENT}"
echo ""
