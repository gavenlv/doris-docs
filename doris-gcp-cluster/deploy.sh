#!/bin/bash
# Doris GCP Cluster Deployment Script

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

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Doris GCP Cluster Deployment${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}Environment: ${ENVIRONMENT}${NC}"
echo -e "${YELLOW}Config File: ${TFVARS_FILE}${NC}"
echo ""

# Initialize Terraform
echo -e "${YELLOW}[1/4] Initializing Terraform...${NC}"
terraform init

# Validate configuration
echo -e "${YELLOW}[2/4] Validating configuration...${NC}"
terraform validate -var-file="$TFVARS_FILE"

# Plan deployment
echo -e "${YELLOW}[3/4] Planning deployment...${NC}"
terraform plan -var-file="$TFVARS_FILE" -out=tfplan

# Ask for confirmation
read -p "Do you want to proceed with the deployment? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Deployment cancelled."
    exit 0
fi

# Apply changes
echo -e "${YELLOW}[4/4] Applying changes...${NC}"
terraform apply tfplan

# Cleanup
rm -f tfplan

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment completed successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "To view outputs:"
echo "  terraform output -json | jq ."
echo ""
echo "To destroy the cluster:"
echo "  ./destroy.sh $ENVIRONMENT"
echo ""
