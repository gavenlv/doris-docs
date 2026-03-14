#!/bin/bash

# ==========================================
# Doris GKE Cluster - Scale Script
# ==========================================
# Purpose: 手动扩缩容 Doris BE
# Version: 1.0

set -e

# ==========================================
# Configuration
# ==========================================
NAMESPACE="${NAMESPACE:-doris}"

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

scale_be() {
    local replicas="$1"
    
    log_info "扩缩容 BE 到 $replicas 副本..."
    
    kubectl scale statefulset be -n "$NAMESPACE" --replicas="$replicas"
    
    log_info "等待 Pod 就绪..."
    kubectl rollout status statefulset/be -n "$NAMESPACE"
}

show_status() {
    log_info "当前状态:"
    echo ""
    
    echo "=== Pods ==="
    kubectl get pods -n "$NAMESPACE" -o wide
    echo ""
    
    echo "=== StatefulSets ==="
    kubectl get statefulsets -n "$NAMESPACE"
    echo ""
    
    echo "=== HPA ==="
    kubectl get hpa -n "$NAMESPACE" 2>/dev/null || echo "无 HPA"
}

# ==========================================
# Main
# ==========================================

main() {
    local action="${1:-status}"
    local value="${2:-}"
    
    case "$action" in
        up)
            if [ -z "$value" ]; then
                log_error "请指定副本数"
                echo "用法: $0 up <replicas>"
                exit 1
            fi
            scale_be "$value"
            ;;
        down)
            if [ -z "$value" ]; then
                log_error "请指定副本数"
                echo "用法: $0 down <replicas>"
                exit 1
            fi
            scale_be "$value"
            ;;
        status)
            show_status
            ;;
        *)
            echo "用法: $0 {up|down|status} [replicas]"
            echo ""
            echo "示例:"
            echo "  $0 up 10     # 扩容到 10 副本"
            echo "  $0 down 5    # 缩容到 5 副本"
            echo "  $0 status    # 查看状态"
            exit 1
            ;;
    esac
}

main "$@"
