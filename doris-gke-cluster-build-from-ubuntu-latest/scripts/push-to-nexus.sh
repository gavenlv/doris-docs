#!/bin/bash

# ==========================================
# Doris GKE Cluster - Push to Nexus Script
# ==========================================
# Purpose: 推送安全扫描通过的镜像到 Nexus
# Version: 1.0

set -e

# ==========================================
# Configuration
# ==========================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPORTS_DIR="${PROJECT_DIR}/reports"

# Nexus 配置
NEXUS_URL="${NEXUS_URL:-nexus.company.com:8082}"
NEXUS_USER="${NEXUS_USER:-admin}"
NEXUS_PASS="${NEXUS_PASS:-}"
NEXUS_REPO="${NEXUS_REPO:-doris}"

# 版本配置
DORIS_VERSION="${DORIS_VERSION:-3.1.4}"
FDB_VERSION="${FDB_VERSION:-7.1.37}"
OPERATOR_VERSION="${OPERATOR_VERSION:-v1.1.0}"

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
log_push() { echo -e "${BLUE}[PUSH]${NC} $1"; }

# ==========================================
# Functions
# ==========================================

check_nexus_credentials() {
    if [ -z "$NEXUS_PASS" ]; then
        log_error "未设置 Nexus 密码"
        log_info "请设置环境变量: export NEXUS_PASS=your-password"
        exit 1
    fi
}

login_nexus() {
    log_info "登录 Nexus Registry: ${NEXUS_URL}"
    
    echo "$NEXUS_PASS" | docker login "$NEXUS_URL" \
        --username "$NEXUS_USER" \
        --password-stdin
    
    if [ $? -eq 0 ]; then
        log_info "登录成功"
    else
        log_error "登录失败，请检查凭据"
        exit 1
    fi
}

verify_scan_passed() {
    log_info "验证安全扫描状态..."
    
    local has_vulns=0
    
    for json in "${REPORTS_DIR}"/json/*-scan.json; do
        if [ -f "$json" ]; then
            local critical=$(cat "$json" | jq '[.Results[]?.Vulnerabilities[] | select(.Severity=="CRITICAL")] | length // 0')
            local high=$(cat "$json" | jq '[.Results[]?.Vulnerabilities[] | select(.Severity=="HIGH")] | length // 0')
            
            if [ "$critical" -gt 0 ] || [ "$high" -gt 0 ]; then
                local name=$(basename "$json" -scan.json)
                log_error "${name} 存在高危漏洞 (${critical} CRITICAL, ${high} HIGH)"
                has_vulns=1
            fi
        fi
    done
    
    if [ $has_vulns -eq 1 ]; then
        echo ""
        log_error "存在高危漏洞，禁止推送到 Nexus!"
        log_info "请先修复漏洞: ./scripts/fix-vulnerabilities.sh"
        exit 1
    fi
    
    log_info "安全验证通过"
}

push_image() {
    local image="$1"
    local name="$2"
    
    log_push "推送镜像: ${image}"
    
    if docker push "$image"; then
        log_info "推送成功: ${name}"
    else
        log_error "推送失败: ${name}"
        return 1
    fi
}

verify_image_in_nexus() {
    local image="$1"
    local name="$2"
    
    log_info "验证镜像已存在于 Nexus: ${name}"
    
    # 使用 docker manifest 检查
    if docker manifest inspect "$image" &> /dev/null; then
        log_info "验证成功: ${name}"
        return 0
    else
        log_warn "无法验证镜像: ${name}"
        return 1
    fi
}

# ==========================================
# Main
# ==========================================

main() {
    local target="${1:-all}"
    
    echo "=========================================="
    echo " 推送镜像到 Nexus Registry"
    echo "=========================================="
    echo ""
    
    # 检查凭据
    check_nexus_credentials
    echo ""
    
    # 验证扫描状态
    verify_scan_passed
    echo ""
    
    # 登录 Nexus
    login_nexus
    echo ""
    
    local images=()
    
    case "$target" in
        fe)
            images+=("${NEXUS_URL}/${NEXUS_REPO}/fe:${DORIS_VERSION}-secure:fe")
            ;;
        be)
            images+=("${NEXUS_URL}/${NEXUS_REPO}/be:${DORIS_VERSION}-secure:be")
            ;;
        fdb)
            images+=("${NEXUS_URL}/foundationdb:${FDB_VERSION}-secure:fdb")
            ;;
        operator)
            images+=("${NEXUS_URL}/doris-operator:${OPERATOR_VERSION}-secure:operator")
            ;;
        all)
            images+=("${NEXUS_URL}/${NEXUS_REPO}/fe:${DORIS_VERSION}-secure:fe")
            images+=("${NEXUS_URL}/${NEXUS_REPO}/be:${DORIS_VERSION}-secure:be")
            images+=("${NEXUS_URL}/foundationdb:${FDB_VERSION}-secure:fdb")
            images+=("${NEXUS_URL}/doris-operator:${OPERATOR_VERSION}-secure:operator")
            ;;
        *)
            echo "用法: $0 {all|fe|be|fdb|operator}"
            exit 1
            ;;
    esac
    
    # 推送镜像
    local success=0
    local failed=0
    
    for item in "${images[@]}"; do
        local image=$(echo "$item" | cut -d':' -f1-3)
        local name=$(echo "$item" | cut -d':' -f4)
        
        if push_image "$image" "$name"; then
            verify_image_in_nexus "$image" "$name"
            ((success++))
        else
            ((failed++))
        fi
        echo ""
    done
    
    # 汇总
    echo "=========================================="
    echo " 推送汇总"
    echo "=========================================="
    log_info "成功: ${success}"
    if [ $failed -gt 0 ]; then
        log_error "失败: ${failed}"
        exit 1
    fi
    
    echo ""
    log_info "镜像已推送到 Nexus，可以开始部署"
    log_info "运行: ./scripts/deploy.sh"
}

main "$@"
