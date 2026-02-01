#!/bin/bash
# Doris GCP Compute Storage Separation Cluster Deployment Script

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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
    echo "Examples:"
    echo "  $0 dev"
    echo "  $0 prod"
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

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Doris GCP Compute Storage Separation${NC}"
echo -e "${GREEN}Cluster Deployment${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}Environment: ${ENVIRONMENT}${NC}"
echo -e "${YELLOW}Config File: ${TFVARS_FILE}${NC}"
echo ""

echo -e "${BLUE}[1/5] Initializing Terraform...${NC}"
terraform init

echo -e "${BLUE}[2/5] Validating configuration...${NC}"
terraform validate -var-file="$TFVARS_FILE"

echo -e "${BLUE}[3/5] Planning deployment...${NC}"
terraform plan -var-file="$TFVARS_FILE" -out=tfplan

echo ""
echo -e "${YELLOW}This will deploy:${NC}"
echo "  - FE Cluster with persistent meta storage"
echo "  - BE Cluster with auto-scaling"
echo "  - GCS Bucket for cold storage"
echo "  - Internal Load Balancer"
echo "  - Compute-Storage Separation enabled"
echo ""

read -p "Do you want to proceed with the deployment? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Deployment cancelled."
    rm -f tfplan
    exit 0
fi

echo -e "${BLUE}[4/5] Applying changes...${NC}"
terraform apply tfplan

rm -f tfplan

echo -e "${BLUE}[5/5] Configuring storage separation...${NC}"

# Get cluster info
LB_IP=$(terraform output -json | jq -r '.lb_internal_ip.value')
GCS_BUCKET=$(terraform output -json | jq -r '.gcs_bucket.value')

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment completed successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Cluster Information:${NC}"
echo "  Load Balancer IP: ${LB_IP}"
echo "  GCS Bucket: ${GCS_BUCKET}"
echo ""
echo -e "${BLUE}Connection:${NC}"
echo "  mysql -h ${LB_IP} -P 9030 -u root"
echo ""
echo -e "${BLUE}Storage Configuration:${NC}"
echo "  Hot Storage: SSD (Local)"
echo "  Cold Storage: GCS Bucket"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo "  1. Connect to cluster: mysql -h ${LB_IP} -P 9030 -u root"
echo "  2. Create tables with storage policy:"
echo "     CREATE TABLE test (id INT) PROPERTIES ('storage_policy'='hot_to_cold');"
echo "  3. View cluster status:"
echo "     ./status.sh"
echo ""
