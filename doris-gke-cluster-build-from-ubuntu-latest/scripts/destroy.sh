#!/bin/bash

# ==========================================
# Doris GKE Cluster - Destroy Script
# ==========================================
# Purpose: 清理 Doris 部署
# Version: 1.0

set -e

# ==========================================
# Configuration
# ==========================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
K8S_DIR="${PROJECT_DIR}/kubernetes"

# ==========================================
# Color Output
# ==========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ==========================================
# Functions
# ==========================================

confirm() {
    echo ""
    log_warn "警告: 此操作将删除所有 Doris 组件和数据!"
    read -p "确认删除? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        log_info "操作已取消"
        exit 0
    fi
}

delete_resources() {
    log_info "删除 Kubernetes 资源..."
    
    # 删除 HPA
    kubectl delete hpa -n doris --all 2>/dev/null || true
    
    # 删除 StatefulSets
    kubectl delete statefulset -n doris --all
    
    # 删除 Services
    kubectl delete service -n doris --all
    
    # 删除 PVCs
    kubectl delete pvc -n doris --all
    
    # 删除 ConfigMaps
    kubectl delete configmap -n doris --all
    
    # 删除 Secrets
    kubectl delete secret -n doris --all
    
    # 删除 StorageClasses
    kubectl delete -f "${K8S_DIR}/storage/storage-class.yaml" 2>/dev/null || true
    
    # 删除命名空间
    kubectl delete namespace doris
    
    log_info "资源删除完成"
}

verify_deletion() {
    log_info "验证删除..."
    
    if kubectl get namespace doris &> /dev/null; then
        log_warn "命名空间 doris 仍存在"
        kubectl get all -n doris
    else
        log_info "命名空间 doris 已删除"
    fi
}

# ==========================================
# Main
# ==========================================

main() {
    echo "=========================================="
    echo " 清理 Doris 部署"
    echo "=========================================="
    
    confirm
    echo ""
    
    delete_resources
    echo ""
    
    verify_deletion
    echo ""
    
    log_info "清理完成!"
}

main "$@"
