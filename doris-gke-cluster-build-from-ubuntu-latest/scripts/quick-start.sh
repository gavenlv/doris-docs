#!/bin/bash

# ==========================================
# Doris 安全镜像快速开始脚本
# ==========================================
# Purpose: 一键执行构建、扫描、推送流程
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
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_phase() { echo -e "${CYAN}[PHASE]${NC} $1"; }

# ==========================================
# Functions
# ==========================================

check_environment() {
    log_phase "检查环境..."
    
    # 检查 Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装，请先安装 Docker"
        exit 1
    fi
    
    # 检查 Trivy
    if ! command -v trivy &> /dev/null; then
        log_warn "Trivy 未安装，安全扫描将跳过"
        log_info "安装 Trivy: https://aquasecurity.github.io/trivy/latest/getting-started/installation/"
    fi
    
    # 检查环境变量
    if [ -z "$NEXUS_PASS" ]; then
        log_warn "NEXUS_PASS 未设置，推送镜像时需要"
        log_info "设置: export NEXUS_PASS=your-password"
    fi
    
    log_info "环境检查完成"
}

show_menu() {
    echo ""
    echo "=========================================="
    echo " Doris 安全镜像构建工具"
    echo "=========================================="
    echo ""
    echo "请选择操作:"
    echo ""
    echo "  1) 构建所有镜像"
    echo "  2) 扫描所有镜像"
    echo "  3) 构建并扫描"
    echo "  4) 推送到 Nexus"
    echo "  5) 完整流程 (构建 -> 扫描 -> 推送)"
    echo "  6) 查看扫描报告"
    echo "  7) 漏洞修复指南"
    echo "  8) 部署到 GKE"
    echo ""
    echo "  0) 退出"
    echo ""
}

build_images() {
    log_phase "构建镜像"
    "${SCRIPT_DIR}/build-images.sh" all
}

scan_images() {
    log_phase "扫描镜像"
    "${SCRIPT_DIR}/scan-images.sh" all
}

push_images() {
    if [ -z "$NEXUS_PASS" ]; then
        log_error "请先设置 NEXUS_PASS"
        exit 1
    fi
    log_phase "推送镜像"
    "${SCRIPT_DIR}/push-to-nexus.sh" all
}

view_report() {
    local report="${SCRIPT_DIR}/../reports/security-scan-report.txt"
    if [ -f "$report" ]; then
        cat "$report"
    else
        log_warn "报告不存在，请先运行扫描"
    fi
}

show_fix_guide() {
    "${SCRIPT_DIR}/fix-vulnerabilities.sh"
}

deploy() {
    "${SCRIPT_DIR}/deploy.sh"
}

# ==========================================
# Main
# ==========================================

main() {
    check_environment
    
    while true; do
        show_menu
        read -p "请输入选项: " choice
        
        case "$choice" in
            1)
                build_images
                ;;
            2)
                scan_images
                ;;
            3)
                "${SCRIPT_DIR}/build-and-scan.sh" all
                ;;
            4)
                push_images
                ;;
            5)
                "${SCRIPT_DIR}/build-and-scan.sh" all
                echo ""
                push_images
                ;;
            6)
                view_report
                ;;
            7)
                show_fix_guide
                ;;
            8)
                deploy
                ;;
            0)
                log_info "再见!"
                exit 0
                ;;
            *)
                log_error "无效选项"
                ;;
        esac
        
        echo ""
        read -p "按回车继续..."
    done
}

main "$@"
