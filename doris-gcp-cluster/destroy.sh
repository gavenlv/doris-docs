#!/bin/bash
# Doris GCP Cluster Destruction Script

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
    echo "Note: Persistent disks and GCS buckets will be preserved."
    echo "      Use './clean-all.sh' to remove all resources including data."
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
        echo "Valid environments: dev, sit, uat, prod"
        exit 1
        ;;
esac

# Check if tfvars file exists
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
echo -e "${YELLOW}Warning: This will destroy all compute instances but preserve persistent disks and GCS buckets.${NC}"
echo ""

# Confirm destruction
read -p "Are you sure you want to destroy the cluster? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Destruction cancelled."
    exit 0
fi

# Initialize Terraform
echo -e "${YELLOW}[1/2] Initializing Terraform...${NC}"
terraform init

# Destroy resources
echo -e "${YELLOW}[2/2] Destroying cluster...${NC}"
terraform destroy -var-file="$TFVARS_FILE" -auto-approve

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cluster destroyed successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Persistent disks and GCS buckets have been preserved."
echo "To permanently delete them, use:"
echo "  ./clean-all.sh $ENVIRONMENT"
echo ""
