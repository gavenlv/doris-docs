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

echo -e "${BLUE}[1/6] Checking prerequisites...${NC}"

# Check if artifacts bucket exists
ARTIFACTS_BUCKET="${GCS_BUCKET}-artifacts"
if ! gsutil ls "gs://${ARTIFACTS_BUCKET}" > /dev/null 2>&1; then
    echo -e "${RED}Error: Artifacts bucket 'gs://${ARTIFACTS_BUCKET}' not found!${NC}"
    echo "Please run ./upload-artifacts.sh ${ENVIRONMENT} first."
    echo ""
    echo "This is required for private network deployment."
    exit 1
fi

echo -e "${GREEN}  ✓ Artifacts bucket found${NC}"

echo -e "${BLUE}[2/6] Initializing Terraform...${NC}"
terraform init

echo -e "${BLUE}[3/6] Validating configuration...${NC}"
terraform validate -var-file="$TFVARS_FILE"

echo -e "${BLUE}[4/6] Planning deployment...${NC}"
terraform plan -var-file="$TFVARS_FILE" -out=tfplan

echo ""
echo -e "${YELLOW}This will deploy:${NC}"
echo "  - FE Cluster with FoundationDB (High Availability)"
echo "  - BE Cluster with auto-scaling"
echo "  - GCS Bucket for cold storage"
echo "  - Internal Load Balancer"
echo "  - Compute-Storage Separation enabled"
echo "  - Private Network (No internet access)"
echo ""

read -p "Do you want to proceed with the deployment? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Deployment cancelled."
    rm -f tfplan
    exit 0
fi

echo -e "${BLUE}[5/6] Applying changes...${NC}"
terraform apply tfplan

rm -f tfplan

echo -e "${BLUE}[6/6] Verifying deployment...${NC}"

# Get cluster info
LB_IP=$(terraform output -json connection_info 2>/dev/null | jq -r '.lb_internal_ip' || echo "N/A")
GCS_BUCKET=$(terraform output -json storage_info 2>/dev/null | jq -r '.cold_storage_bucket' || echo "N/A")

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment completed successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Cluster Information:${NC}"
echo "  Load Balancer IP: ${LB_IP}"
echo "  GCS Bucket: ${GCS_BUCKET}"
echo "  Artifacts Bucket: ${ARTIFACTS_BUCKET}"
echo ""
echo -e "${BLUE}Network Configuration:${NC}"
echo "  Mode: Private Network (No internet access)"
echo "  GCS Access: Via Private Google Access"
echo ""
echo -e "${BLUE}Connection:${NC}"
echo "  mysql -h ${LB_IP} -P 9030 -u root"
echo ""
echo -e "${BLUE}Storage Configuration:${NC}"
echo "  Hot Storage: SSD (Local)"
echo "  Cold Storage: GCS Bucket"
echo "  FE Metadata: FoundationDB (HA)"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo "  1. Connect to cluster: mysql -h ${LB_IP} -P 9030 -u root"
echo "  2. Create tables with storage policy:"
echo "     CREATE TABLE test (id INT) PROPERTIES ('storage_policy'='hot_to_cold');"
echo "  3. View cluster status:"
echo "     ./status.sh"
echo ""
echo -e "${YELLOW}Note: This cluster is running in private network mode.${NC}"
echo -e "${YELLOW}      VMs do not have direct internet access.${NC}"
echo ""
