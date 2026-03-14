#!/bin/bash

# ==========================================
# Doris GKE Cluster - Vulnerability Fix Script
# ==========================================
# Purpose: 分析并提供漏洞修复建议
# Version: 1.0

set -e

# ==========================================
# Configuration
# ==========================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPORTS_DIR="${PROJECT_DIR}/reports"
DOCS_DIR="${PROJECT_DIR}/docs"

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
log_fix() { echo -e "${CYAN}[FIX]${NC} $1"; }

# ==========================================
# Functions
# ==========================================

analyze_vulnerabilities() {
    local json_report="$1"
    local name="$2"
    
    if [ ! -f "$json_report" ]; then
        log_warn "未找到 ${name} 的扫描报告"
        return
    fi
    
    echo ""
    echo "=========================================="
    echo " ${name} 漏洞分析和修复建议"
    echo "=========================================="
    
    # 提取高危和严重漏洞
    local vulns=$(cat "${json_report}" | jq -r '.Results[]?.Vulnerabilities[] | select(.Severity=="CRITICAL" or .Severity=="HIGH") | @base64' 2>/dev/null || true)
    
    if [ -z "$vulns" ]; then
        log_info "${name} 无高危漏洞"
        return
    fi
    
    local count=0
    for vuln in $vulns; do
        ((count++))
        local data=$(echo "$vuln" | base64 -d)
        local vuln_id=$(echo "$data" | jq -r '.VulnerabilityID')
        local pkg_name=$(echo "$data" | jq -r '.PkgName')
        local severity=$(echo "$data" | jq -r '.Severity')
        local installed=$(echo "$data" | jq -r '.InstalledVersion')
        local fixed=$(echo "$data" | jq -r '.FixedVersion // "无修复版本"')
        local title=$(echo "$data" | jq -r '.Title')
        local description=$(echo "$data" | jq -r '.Description' | head -c 200)
        
        echo ""
        echo "--- 漏洞 #${count} ---"
        echo "ID: ${vuln_id}"
        echo "严重级别: ${severity}"
        echo "影响包: ${pkg_name}"
        echo "当前版本: ${installed}"
        echo "修复版本: ${fixed}"
        echo "描述: ${title}"
        
        # 提供修复建议
        echo ""
        echo "修复建议:"
        if [ "$fixed" != "无修复版本" ]; then
            echo "  1. 更新 ${pkg_name} 到版本 ${fixed}"
            echo "  2. 在 Dockerfile 中添加:"
            echo "     RUN apt-get update && apt-get install -y ${pkg_name}=${fixed}"
        else
            echo "  该漏洞暂无官方修复版本，建议:"
            echo "  1. 关注官方安全公告"
            echo "  2. 评估是否可以移除该依赖"
            echo "  3. 使用其他替代方案"
        fi
    done
}

generate_fix_report() {
    local report="${DOCS_DIR}/VULNERABILITY-FIXES.md"
    
    cat > "${report}" <<'EOF'
# 漏洞修复记录

本文档记录所有发现的安全漏洞及其修复状态。

## 修复策略

### 优先级

1. **CRITICAL**: 必须在部署前修复
2. **HIGH**: 强烈建议修复
3. **MEDIUM**: 建议修复
4. **LOW**: 可接受风险

### 修复方法

1. **升级软件包**: 更新到修复了漏洞的版本
2. **移除依赖**: 如果不需要，移除有漏洞的包
3. **配置缓解**: 通过配置降低风险
4. **等待修复**: 跟踪官方修复进度

## 常见漏洞修复

### OpenSSL 漏洞

```dockerfile
# 在 Dockerfile 中添加
RUN apt-get update && apt-get install -y --only-upgrade openssl libssl3
```

### Glibc 漏洞

```dockerfile
# 在 Dockerfile 中添加
RUN apt-get update && apt-get install -y --only-upgrade libc6
```

### Curl 漏洞

```dockerfile
# 在 Dockerfile 中添加
RUN apt-get update && apt-get install -y --only-upgrade curl libcurl4
```

## 修复记录

| 日期 | 镜像 | CVE | 严重级别 | 状态 | 修复方法 |
|------|------|-----|---------|------|---------|
| - | - | - | - | 待扫描 | - |

## 扫描历史

EOF

    # 添加扫描历史
    for json in "${REPORTS_DIR}"/json/*-scan.json; do
        if [ -f "$json" ]; then
            local name=$(basename "$json" -scan.json)
            local date=$(date -r "$json" "+%Y-%m-%d %H:%M")
            local total=$(cat "$json" | jq '[.Results[]?.Vulnerabilities | length] | add // 0')
            local critical=$(cat "$json" | jq '[.Results[]?.Vulnerabilities[] | select(.Severity=="CRITICAL")] | length // 0')
            local high=$(cat "$json" | jq '[.Results[]?.Vulnerabilities[] | select(.Severity=="HIGH")] | length // 0')
            
            echo "### ${name} (${date})" >> "${report}"
            echo "" >> "${report}"
            echo "- 总漏洞数: ${total}" >> "${report}"
            echo "- CRITICAL: ${critical}" >> "${report}"
            echo "- HIGH: ${high}" >> "${report}"
            echo "" >> "${report}"
        fi
    done
    
    log_info "漏洞修复报告已生成: ${report}"
}

# ==========================================
# Main
# ==========================================

main() {
    echo "=========================================="
    echo " 漏洞分析和修复建议"
    echo "=========================================="
    echo ""
    
    # 检查是否有扫描报告
    if [ ! -d "${REPORTS_DIR}/json" ]; then
        log_warn "未找到扫描报告，请先运行 scan-images.sh"
        log_info "运行: ./scripts/scan-images.sh all"
        exit 1
    fi
    
    # 分析每个镜像
    for json in "${REPORTS_DIR}"/json/*-scan.json; do
        if [ -f "$json" ]; then
            local name=$(basename "$json" -scan.json)
            analyze_vulnerabilities "$json" "$name"
        fi
    done
    
    # 生成修复报告
    echo ""
    generate_fix_report
    
    echo ""
    log_info "修复流程:"
    echo "  1. 查看 docs/VULNERABILITY-FIXES.md 了解详情"
    echo "  2. 根据建议修改 docker/*/Dockerfile"
    echo "  3. 运行 ./scripts/build-images.sh 重新构建"
    echo "  4. 运行 ./scripts/scan-images.sh 验证修复"
    echo "  5. 重复直到无高危漏洞"
}

main "$@"
