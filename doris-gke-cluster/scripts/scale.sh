#!/bin/bash

# ==========================================
# Doris GKE Cluster - Manual Scaling Script
# ==========================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

usage() {
    echo "Usage: $0 [command] [value]"
    echo ""
    echo "Commands:"
    echo "  up <replicas>      Scale BE up to specified replicas"
    echo "  down <replicas>    Scale BE down to specified replicas"
    echo "  status             Show current scaling status"
    echo ""
    echo "Examples:"
    echo "  $0 up 15       # Scale BE to 15 replicas"
    echo "  $0 down 5      # Scale BE to 5 replicas"
    echo "  $0 status      # Show current status"
}

scale_be() {
    local replicas=$1
    
    if [ -z "$replicas" ]; then
        log_error "Please specify number of replicas"
        usage
        exit 1
    fi
    
    log_info "Scaling BE to $replicas replicas..."
    
    # Patch HPA
    kubectl patch hpa be-hpa -n doris --type='json' \
        -p="[{\"op\": \"replace\", \"path\": \"/spec/minReplicas\", \"value\":$replicas}]"
    
    # Also scale StatefulSet directly for immediate effect
    kubectl scale statefulset be -n doris --replicas=$replicas
    
    log_info "BE scaling initiated. Check status with: kubectl get pods -n doris -l app=be"
}

show_status() {
    log_info "Current BE StatefulSet status:"
    kubectl get statefulset be -n doris
    
    echo ""
    log_info "Current HPA status:"
    kubectl get hpa be-hpa -n doris
    
    echo ""
    log_info "Pod distribution:"
    kubectl get pods -n doris -l app=be -o wide
}

# Main
if [ $# -eq 0 ]; then
    usage
    exit 1
fi

case "$1" in
    up)
        scale_be $2
        ;;
    down)
        scale_be $2
        ;;
    status)
        show_status
        ;;
    *)
        log_error "Unknown command: $1"
        usage
        exit 1
        ;;
esac
