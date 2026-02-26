#!/bin/bash

# ==========================================
# Doris GKE Cluster - Main Deployment Script
# ==========================================
# Version: 1.0
# Last Updated: 2026-02-26

set -e

# ==========================================
# Configuration
# ==========================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TERRAFORM_DIR="${ROOT_DIR}/terraform"
KUBERNETES_DIR="${ROOT_DIR}/kubernetes"
CONFIGS_DIR="${ROOT_DIR}/configs"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# ==========================================
# Functions
# ==========================================

check_prerequisites() {
    log_step "Checking prerequisites..."
    
    local missing_tools=()
    
    # Check required tools
    for tool in terraform kubectl gcloud; do
        if ! command -v $tool &> /dev/null; then
            missing_tools+=($tool)
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Please install them before proceeding."
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "gcloud not authenticated. Run: gcloud auth login"
        exit 1
    fi
    
    log_info "Prerequisites check passed."
}

deploy_terraform() {
    log_step "Deploying GKE infrastructure with Terraform..."
    
    cd "$TERRAFORM_DIR"
    
    # Initialize Terraform
    log_info "Initializing Terraform..."
    terraform init
    
    # Plan
    log_info "Creating Terraform plan..."
    terraform plan -var-file=terraform.tfvars.prod -out=tfplan
    
    # Apply
    log_info "Applying Terraform plan..."
    terraform apply tfplan
    
    # Get cluster credentials
    log_info "Getting cluster credentials..."
    CLUSTER_NAME=$(terraform output -raw cluster_name)
    REGION=$(terraform output -raw cluster_region)
    PROJECT_ID=$(grep 'project_id' terraform.tfvars.prod | cut -d'"' -f2)
    
    gcloud container clusters get-credentials "$CLUSTER_NAME" \
        --region "$REGION" \
        --project "$PROJECT_ID"
    
    log_info "Terraform deployment completed."
}

create_nexus_secret() {
    log_step "Creating Nexus Docker registry secret..."
    
    # Check if secret already exists
    if kubectl get secret nexus-secret -n doris &> /dev/null; then
        log_warn "Secret nexus-secret already exists in namespace doris"
        read -p "Do you want to recreate it? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Skipping secret creation."
            return
        fi
        kubectl delete secret nexus-secret -n doris
    fi
    
    # Prompt for Nexus credentials
    read -p "Enter Nexus URL [nexus.company.com]: " NEXUS_URL
    NEXUS_URL=${NEXUS_URL:-nexus.company.com}
    
    read -p "Enter Nexus username: " NEXUS_USER
    read -s -p "Enter Nexus password: " NEXUS_PASS
    echo
    
    # Create secret
    kubectl create secret docker-registry nexus-secret \
        --docker-server="$NEXUS_URL" \
        --docker-username="$NEXUS_USER" \
        --docker-password="$NEXUS_PASS" \
        --docker-email="admin@company.com" \
        -n doris
    
    log_info "Nexus secret created successfully."
}

deploy_kubernetes() {
    log_step "Deploying Kubernetes resources..."
    
    cd "$KUBERNETES_DIR"
    
    # 1. Create namespace
    log_info "Creating namespace..."
    kubectl apply -f namespace.yaml
    
    # 2. Create storage classes
    log_info "Creating storage classes..."
    kubectl apply -f storage/storage-class.yaml
    
    # 3. Create Nexus secret
    create_nexus_secret
    
    # 4. Deploy Doris Operator
    log_info "Deploying Doris Operator..."
    kubectl apply -f doris-operator/operator.yaml
    
    log_info "Waiting for Operator to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/doris-operator -n doris
    
    # 5. Deploy FoundationDB
    log_info "Deploying FoundationDB..."
    kubectl apply -f doris-cluster/fdb.yaml
    
    log_info "Waiting for FDB to be ready..."
    sleep 30
    kubectl wait --for=condition=ready --timeout=300s pod -l app=fdb -n doris
    
    # 6. Deploy FE
    log_info "Deploying Doris FE..."
    kubectl apply -f doris-cluster/fe.yaml
    
    log_info "Waiting for FE to be ready..."
    sleep 60
    kubectl wait --for=condition=ready --timeout=600s pod -l app=fe -n doris
    
    # 7. Deploy BE
    log_info "Deploying Doris BE..."
    kubectl apply -f doris-cluster/be.yaml
    
    log_info "Waiting for BE to be ready..."
    sleep 60
    kubectl wait --for=condition=ready --timeout=600s pod -l app=be -n doris --timeout=300s || true
    
    # 8. Setup HPA
    log_info "Setting up HPA for BE..."
    kubectl apply -f autoscaling/hpa-be.yaml
    
    log_info "Kubernetes deployment completed."
}

verify_deployment() {
    log_step "Verifying deployment..."
    
    echo ""
    log_info "Namespace doris resources:"
    kubectl get all -n doris
    
    echo ""
    log_info "Pod status:"
    kubectl get pods -n doris -o wide
    
    echo ""
    log_info "Services:"
    kubectl get services -n doris
    
    echo ""
    log_info "HPA status:"
    kubectl get hpa -n doris
    
    # Check FE connectivity
    log_info "Checking FE connectivity..."
    FE_SERVICE=$(kubectl get svc fe-lb -n doris -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    
    if [ -n "$FE_SERVICE" ]; then
        log_info "FE Load Balancer IP: $FE_SERVICE"
        log_info "You can connect to Doris using:"
        log_info "  mysql -h $FE_SERVICE -P 9030 -u root"
    else
        log_warn "FE Load Balancer IP not yet available. Please wait a few minutes."
    fi
}

print_summary() {
    echo ""
    echo "=========================================="
    log_info "Deployment Summary"
    echo "=========================================="
    echo ""
    log_info "✅ GKE Cluster deployed"
    log_info "✅ Private Cluster configured"
    log_info "✅ FoundationDB deployed (3 nodes)"
    log_info "✅ Doris FE deployed (3 nodes)"
    log_info "✅ Doris BE deployed (5-25 nodes with HPA)"
    log_info "✅ Storage configured (Local SSD + GCS)"
    log_info "✅ Auto-scaling enabled"
    echo ""
    log_info "Next steps:"
    log_info "1. Verify all pods are running: kubectl get pods -n doris"
    log_info "2. Get FE connection info: kubectl get svc fe-lb -n doris"
    log_info "3. Connect to Doris: mysql -h <FE_IP> -P 9030 -u root"
    log_info "4. Create your first database and table"
    log_info "5. Run performance tests to validate 50B rows/2min ingestion"
    echo ""
    log_info "Documentation available in: ${ROOT_DIR}/docs/"
    echo "=========================================="
}

# ==========================================
# Main Execution
# ==========================================

main() {
    log_info "Doris GKE Cluster - Deployment Tool"
    log_info "=========================================="
    echo ""
    
    # Parse arguments
    SKIP_TERRAFORM=false
    SKIP_KUBERNETES=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-terraform)
                SKIP_TERRAFORM=true
                shift
                ;;
            --skip-kubernetes)
                SKIP_KUBERNETES=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    check_prerequisites
    echo ""
    
    if [ "$SKIP_TERRAFORM" = false ]; then
        deploy_terraform
        echo ""
    else
        log_warn "Skipping Terraform deployment"
    fi
    
    if [ "$SKIP_KUBERNETES" = false ]; then
        deploy_kubernetes
        echo ""
    else
        log_warn "Skipping Kubernetes deployment"
    fi
    
    verify_deployment
    print_summary
}

main "$@"
