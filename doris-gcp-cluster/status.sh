#!/bin/bash
# Doris GCP Cluster Status Script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if terraform state exists
if [ ! -f "terraform.tfstate" ]; then
    echo -e "${RED}Error: Terraform state file not found${NC}"
    echo "Run 'terraform init' and deploy the cluster first"
    exit 1
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Doris GCP Cluster Status${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Get cluster info
echo -e "${BLUE}[Cluster Configuration]${NC}"
terraform output -json cluster_info | jq .

echo ""
echo -e "${BLUE}[FE Instances]${NC}"
terraform output -json fe_ips | jq -r '.[]' | nl

echo ""
echo -e "${BLUE}[BE Instances]${NC}"
BE_IPS=$(terraform output -json be_ips 2>/dev/null || echo "[]")
if [ "$BE_IPS" != "[]" ]; then
    echo "$BE_IPS" | jq -r '.[]' | nl
else
    echo "  Auto-scaling enabled - use Instance Group Manager"
fi

echo ""
echo -e "${BLUE}[Load Balancer]${NC}"
LB_IP=$(terraform output -json lb_internal_ip 2>/dev/null || echo "null")
if [ "$LB_IP" != "null" ] && [ "$LB_IP" != "" ]; then
    echo "  Internal IP: $LB_IP"
else
    echo "  Load balancer disabled"
fi

echo ""
echo -e "${BLUE}[Persistent Disks]${NC}"
terraform output -json persistent_disks | jq .

echo ""
echo -e "${BLUE}[Storage Configuration]${NC}"
GCS_BUCKET=$(terraform output -json gcs_bucket 2>/dev/null || echo "null")
if [ "$GCS_BUCKET" != "null" ] && [ "$GCS_BUCKET" != "" ]; then
    echo "  GCS Bucket: $GCS_BUCKET"
else
    echo "  Compute-Storage Separation disabled"
fi

echo ""
echo -e "${BLUE}[Terraform State]${NC}"
terraform state list | nl

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}For detailed instance status, run:${NC}"
echo -e "${YELLOW}  gcloud compute instances list --filter='name~doris*'${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
