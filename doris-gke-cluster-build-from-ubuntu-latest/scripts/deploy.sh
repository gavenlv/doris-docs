#!/bin/bash

# ==========================================
# Doris GKE Cluster - Deploy Script
# ==========================================
# Purpose: 部署 Doris 到 GKE 集群
# Version: 1.0

set -e

# ==========================================
# Configuration
# ==========================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
K8S_DIR="${PROJECT_DIR}/kubernetes"

# 集群配置
CLUSTER_NAME="${CLUSTER_NAME:-doris-prod}"
CLUSTER_REGION="${CLUSTER_REGION:-us-central1}"
GCP_PROJECT="${GCP_PROJECT:-your-project-id}"

# ==========================================
# Color Output
# ==========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_deploy() { echo -e "${BLUE}[DEPLOY]${NC} $1"; }

# ==========================================
# Functions
# ==========================================

check_prerequisites() {
    log_info "检查部署环境..."
    
    # 检查 kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl 未安装"
        exit 1
    fi
    
    # 检查 gcloud
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud 未安装"
        exit 1
    fi
    
    log_info "环境检查通过"
}

configure_kubectl() {
    log_info "配置 kubectl..."
    
    gcloud container clusters get-credentials "$CLUSTER_NAME" \
        --region "$CLUSTER_REGION" \
        --project "$GCP_PROJECT"
    
    if [ $? -eq 0 ]; then
        log_info "kubectl 配置成功"
    else
        log_error "kubectl 配置失败"
        exit 1
    fi
}

verify_cluster() {
    log_info "验证集群连接..."
    
    if kubectl cluster-info &> /dev/null; then
        log_info "集群连接正常"
        kubectl get nodes
    else
        log_error "无法连接到集群"
        exit 1
    fi
}

deploy_namespace() {
    log_deploy "创建命名空间..."
    kubectl apply -f "${K8S_DIR}/namespace.yaml"
}

deploy_storage() {
    log_deploy "创建存储类..."
    kubectl apply -f "${K8S_DIR}/storage/storage-class.yaml"
}

deploy_fdb() {
    log_deploy "部署 FoundationDB..."
    kubectl apply -f "${K8S_DIR}/doris-cluster/fdb.yaml"
    
    log_info "等待 FoundationDB 就绪..."
    kubectl wait --for=condition=ready pod -l app=fdb -n doris --timeout=300s || true
}

deploy_fe() {
    log_deploy "部署 Doris FE..."
    kubectl apply -f "${K8S_DIR}/doris-cluster/fe.yaml"
    
    log_info "等待 FE 就绪..."
    sleep 60
    kubectl wait --for=condition=ready pod -l app=fe -n doris --timeout=600s || true
}

deploy_be() {
    log_deploy "部署 Doris BE..."
    kubectl apply -f "${K8S_DIR}/doris-cluster/be.yaml"
    
    log_info "等待 BE 就绪..."
    sleep 60
    kubectl wait --for=condition=ready pod -l app=be -n doris --timeout=600s || true
}

verify_deployment() {
    log_info "验证部署状态..."
    echo ""
    
    kubectl get pods -n doris -o wide
    echo ""
    
    kubectl get services -n doris
    echo ""
    
    log_info "部署完成!"
}

# ==========================================
# Main
# ==========================================

main() {
    echo "=========================================="
    echo " 部署 Doris 到 GKE"
    echo "=========================================="
    echo ""
    
    check_prerequisites
    echo ""
    
    configure_kubectl
    echo ""
    
    verify_cluster
    echo ""
    
    deploy_namespace
    echo ""
    
    deploy_storage
    echo ""
    
    deploy_fdb
    echo ""
    
    deploy_fe
    echo ""
    
    deploy_be
    echo ""
    
    verify_deployment
}

main "$@"
