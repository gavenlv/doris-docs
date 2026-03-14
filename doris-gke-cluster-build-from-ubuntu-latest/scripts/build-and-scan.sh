#!/bin/bash

# ==========================================
# Doris GKE Cluster - Build and Scan Script
# ==========================================
# Purpose: 一键构建并扫描镜像
# Version: 1.0

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ==========================================
# Color Output
# ==========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_phase() { echo -e "${BLUE}[PHASE]${NC} $1"; }

# ==========================================
# Main
# ==========================================

main() {
    local target="${1:-all}"
    
    echo "=========================================="
    echo " Doris 安全镜像 - 构建和扫描"
    echo "=========================================="
    echo ""
    
    # Phase 1: 构建
    log_phase "阶段 1: 构建镜像"
    echo "----------------------------------------"
    "${SCRIPT_DIR}/build-images.sh" "$target"
    echo ""
    
    # Phase 2: 扫描
    log_phase "阶段 2: 安全扫描"
    echo "----------------------------------------"
    "${SCRIPT_DIR}/scan-images.sh" "$target"
    
    echo ""
    log_info "构建和扫描完成!"
    log_info "查看报告: cat reports/security-scan-report.txt"
}

main "$@"
