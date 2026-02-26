#!/bin/bash

# ==========================================
# Doris GKE Cluster - Destroy Script
# ==========================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TERRAFORM_DIR="${ROOT_DIR}/terraform"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "=========================================="
log_warn "WARNING: This will destroy the entire Doris cluster!"
echo "=========================================="
echo ""
read -p "Are you sure you want to continue? (yes/no) " -r
echo ""

if [[ ! $REPLY == "yes" ]]; then
    log_info "Aborted."
    exit 1
fi

# Delete Kubernetes resources
log_info "Deleting Kubernetes resources..."
kubectl delete namespace doris --ignore-not-found=true

# Destroy Terraform infrastructure
log_info "Destroying Terraform infrastructure..."
cd "$TERRAFORM_DIR"
terraform destroy -var-file=terraform.tfvars.prod

log_info "Cluster destroyed successfully."
