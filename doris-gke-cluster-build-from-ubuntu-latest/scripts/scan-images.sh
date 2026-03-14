#!/bin/bash

# ==========================================
# Doris GKE Cluster - Security Scan Script
# ==========================================
# Purpose: 使用 Trivy 扫描镜像安全漏洞
# Version: 1.0

set -e

# ==========================================
# Configuration
# ==========================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPORTS_DIR="${PROJECT_DIR}/reports"
CONFIG_DIR="${PROJECT_DIR}/configs"

# 镜像配置
NEXUS_URL="${NEXUS_URL:-nexus.company.com:8082}"
NEXUS_REPO="${NEXUS_REPO:-doris}"
DORIS_VERSION="${DORIS_VERSION:-3.1.4}"
FDB_VERSION="${FDB_VERSION:-7.1.37}"
OPERATOR_VERSION="${OPERATOR_VERSION:-v1.1.0}"

# 扫描配置
SEVERITY_THRESHOLD="${SEVERITY_THRESHOLD:-HIGH,CRITICAL}"
IGNORE_UNFIXED="${IGNORE_UNFIXED:-false}"
EXIT_CODE_ON_VULN=1

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
log_scan() { echo -e "${BLUE}[SCAN]${NC} $1"; }

# ==========================================
# Functions
# ==========================================

check_prerequisites() {
    log_info "检查扫描环境..."
    
    # 检查 Trivy
    if ! command -v trivy &> /dev/null; then
        log_error "Trivy 未安装"
        log_info "安装方法: https://aquasecurity.github.io/trivy/latest/getting-started/installation/"
        exit 1
    fi
    
    # 创建报告目录
    mkdir -p "${REPORTS_DIR}"
    mkdir -p "${REPORTS_DIR}/json"
    mkdir -p "${REPORTS_DIR}/html"
    
    log_info "环境检查通过"
    log_info "Trivy 版本: $(trivy --version | head -1)"
}

scan_image() {
    local image="$1"
    local name="$2"
    local json_report="${REPORTS_DIR}/json/${name}-scan.json"
    local html_report="${REPORTS_DIR}/html/${name}-scan.html"
    local summary_report="${REPORTS_DIR}/${name}-summary.txt"
    
    log_scan "扫描镜像: ${image}"
    
    # 运行 Trivy 扫描
    trivy image \
        --severity ${SEVERITY_THRESHOLD} \
        --ignore-unfixed=${IGNORE_UNFIXED} \
        --format json \
        --output "${json_report}" \
        "${image}" || true
    
    # 生成 HTML 报告
    trivy image \
        --severity ${SEVERITY_THRESHOLD} \
        --ignore-unfixed=${IGNORE_UNFIXED} \
        --format template \
        --template "@${SCRIPT_DIR}/../configs/trivy-html.tpl" \
        --output "${html_report}" \
        "${image}" || true
    
    # 统计漏洞数量
    local total=$(cat "${json_report}" | jq '[.Results[]?.Vulnerabilities | length] | add // 0')
    local critical=$(cat "${json_report}" | jq '[.Results[]?.Vulnerabilities[] | select(.Severity=="CRITICAL")] | length // 0')
    local high=$(cat "${json_report}" | jq '[.Results[]?.Vulnerabilities[] | select(.Severity=="HIGH")] | length // 0')
    local medium=$(cat "${json_report}" | jq '[.Results[]?.Vulnerabilities[] | select(.Severity=="MEDIUM")] | length // 0')
    local low=$(cat "${json_report}" | jq '[.Results[]?.Vulnerabilities[] | select(.Severity=="LOW")] | length // 0')
    
    # 生成摘要报告
    cat > "${summary_report}" <<EOF
========================================
安全扫描报告 - ${name}
========================================
镜像: ${image}
扫描时间: $(date)
扫描器: Trivy $(trivy --version | head -1 | awk '{print $2}')

漏洞统计:
  - 总计: ${total}
  - CRITICAL: ${critical}
  - HIGH: ${high}
  - MEDIUM: ${medium}
  - LOW: ${low}

详细报告:
  - JSON: ${json_report}
  - HTML: ${html_report}
EOF
    
    echo ""
    echo "  漏洞统计:"
    echo "  ┌─────────────────────────────┐"
    echo "  │ 总计:      ${total} 个漏洞"
    echo "  │ CRITICAL:  ${critical} 个"
    echo "  │ HIGH:      ${high} 个"
    echo "  │ MEDIUM:    ${medium} 个"
    echo "  │ LOW:       ${low} 个"
    echo "  └─────────────────────────────┘"
    echo ""
    
    # 返回漏洞数量
    echo "${critical}:${high}:${total}"
}

generate_summary_report() {
    local report="${REPORTS_DIR}/security-scan-report.txt"
    
    cat > "${report}" <<EOF
========================================
Doris 安全加固镜像扫描报告
========================================
生成时间: $(date)
基础镜像: Ubuntu 22.04 LTS

扫描结果摘要
========================================

$(cat "${REPORTS_DIR}"/*-summary.txt 2>/dev/null || echo "暂无扫描结果")

详细报告位置
========================================
- JSON 报告: ${REPORTS_DIR}/json/
- HTML 报告: ${REPORTS_DIR}/html/

漏洞修复指南
========================================
请参考: docs/VULNERABILITY-FIXES.md
EOF
    
    log_info "总报告已生成: ${report}"
}

# ==========================================
# Main
# ==========================================

main() {
    local target="${1:-all}"
    
    echo "=========================================="
    echo " Doris 镜像安全扫描"
    echo "=========================================="
    echo ""
    
    check_prerequisites
    echo ""
    
    local has_vulnerabilities=0
    local results=()
    
    case "$target" in
        fe)
            result=$(scan_image "${NEXUS_URL}/${NEXUS_REPO}/fe:${DORIS_VERSION}-secure" "fe")
            results+=("fe:${result}")
            ;;
        be)
            result=$(scan_image "${NEXUS_URL}/${NEXUS_REPO}/be:${DORIS_VERSION}-secure" "be")
            results+=("be:${result}")
            ;;
        fdb)
            result=$(scan_image "${NEXUS_URL}/foundationdb:${FDB_VERSION}-secure" "fdb")
            results+=("fdb:${result}")
            ;;
        operator)
            result=$(scan_image "${NEXUS_URL}/doris-operator:${OPERATOR_VERSION}-secure" "operator")
            results+=("operator:${result}")
            ;;
        all)
            result=$(scan_image "${NEXUS_URL}/${NEXUS_REPO}/fe:${DORIS_VERSION}-secure" "fe")
            results+=("fe:${result}")
            echo ""
            
            result=$(scan_image "${NEXUS_URL}/${NEXUS_REPO}/be:${DORIS_VERSION}-secure" "be")
            results+=("be:${result}")
            echo ""
            
            result=$(scan_image "${NEXUS_URL}/foundationdb:${FDB_VERSION}-secure" "fdb")
            results+=("fdb:${result}")
            echo ""
            
            result=$(scan_image "${NEXUS_URL}/doris-operator:${OPERATOR_VERSION}-secure" "operator")
            results+=("operator:${result}")
            echo ""
            ;;
        *)
            echo "用法: $0 {all|fe|be|fdb|operator}"
            exit 1
            ;;
    esac
    
    # 生成总报告
    generate_summary_report
    
    # 检查是否有高危漏洞
    echo ""
    echo "=========================================="
    echo " 扫描结果汇总"
    echo "=========================================="
    
    for r in "${results[@]}"; do
        local name=$(echo $r | cut -d':' -f1)
        local critical=$(echo $r | cut -d':' -f2)
        local high=$(echo $r | cut -d':' -f3)
        local total=$(echo $r | cut -d':' -f4)
        
        if [ "$critical" -gt 0 ] || [ "$high" -gt 0 ]; then
            log_error "${name}: 发现 ${critical} 个 CRITICAL, ${high} 个 HIGH 漏洞"
            has_vulnerabilities=1
        else
            log_info "${name}: 通过安全检查 (${total} 个低危漏洞)"
        fi
    done
    
    echo ""
    
    if [ $has_vulnerabilities -eq 1 ]; then
        log_error "发现高危漏洞，请修复后再部署!"
        log_info "运行 ./scripts/fix-vulnerabilities.sh 查看修复建议"
        exit $EXIT_CODE_ON_VULN
    else
        log_info "所有镜像通过安全检查!"
    fi
}

main "$@"
