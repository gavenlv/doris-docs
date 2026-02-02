#!/bin/bash
# Doris GCP Compute Storage Separation Cluster Status Script

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ ! -f "terraform.tfstate" ]; then
    echo -e "${YELLOW}Error: Terraform state file not found${NC}"
    echo "Run 'terraform init' and deploy the cluster first"
    exit 1
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Doris GCP Cluster Status${NC}"
echo -e "${GREEN}Compute Storage Separation${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

echo -e "${BLUE}[Cluster Configuration]${NC}"
terraform output -json cluster_info | jq .

echo ""
echo -e "${BLUE}[Connection Information]${NC}"
terraform output -json connection_info | jq .

echo ""
echo -e "${BLUE}[Storage Configuration]${NC}"
terraform output -json storage_info | jq .

echo ""
echo -e "${BLUE}[Auto Scaling Configuration]${NC}"
terraform output -json scaling_info | jq .

echo ""
echo -e "${BLUE}[Persistent Disks]${NC}"
terraform output -json persistent_disks | jq .

echo ""
echo -e "${BLUE}[Service Account]${NC}"
terraform output -json service_account | jq .

echo ""
echo -e "${BLUE}[SQL Examples for Storage Separation]${NC}"
terraform output -json sql_examples | jq .

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}GCP Console Commands:${NC}"
echo -e "${YELLOW}  # View instances${NC}"
echo -e "  gcloud compute instances list --filter='name~doris-separation*'"
echo ""
echo -e "${YELLOW}  # View instance group${NC}"
echo -e "  gcloud compute instance-groups managed list"
echo ""
echo -e "${YELLOW}  # View GCS bucket${NC}"
echo -e "  gsutil ls gs://$(terraform output -json gcs_bucket | jq -r)"
echo ""
echo -e "${YELLOW}  # Connect to cluster${NC}"
echo -e "  mysql -h $(terraform output -json connection_info | jq -r '.lb_internal_ip') -P 9030 -u root"
echo -e "${GREEN}========================================${NC}"
echo ""
