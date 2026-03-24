#!/bin/bash
#
# build-tools/pre-build.sh
# 离线构建前置准备：下载 Doris 二进制包、FoundationDB DEB 包
#
# 用法:
#   ./pre-build.sh                    # 交互模式（检查+显示说明）
#   ./pre-build.sh --download-only    # 仅下载，不检查
#
# 离线包目录结构:
#   offline-packages/
#   ├── apache-doris-4.0.4-bin-x64.tar.gz    # Doris 统一包 (FE+BE)
#   └── foundationdb/                           # FDB DEB 包目录
#       ├── foundationdb-clients_7.1.37_amd64.deb
#       └── foundationdb-server_7.1.37_amd64.deb
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OFFLINE_PACKAGES_DIR="${OFFLINE_PACKAGES_DIR:-${PROJECT_ROOT}/offline-packages}"

DORIS_VERSION="${DORIS_VERSION:-4.0.4}"
OPERATOR_VERSION="${OPERATOR_VERSION:-1.4.0}"
FDB_VERSION="${FDB_VERSION:-7.1.37}"

# Apache Doris 下载源
DORIS_MIRROR="${DORIS_MIRROR:-https://apache-doris/releases}"
DORIS_DOWNLOAD_URL="${DORIS_MIRROR}/apache-doris-${DORIS_VERSION}-bin-x64.tar.gz"

# FoundationDB 下载源
FDB_DOWNLOAD_BASE="https://www.foundationdb.org/downloads/${FDB_VERSION}/ubuntu20.04"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# =============================================================================
# 下载 Apache Doris 4.0.x (统一包)
# =============================================================================

download_doris() {
    log_info "下载 Apache Doris ${DORIS_VERSION}..."

    mkdir -p "$OFFLINE_PACKAGES_DIR"

    local doris_tar="${OFFLINE_PACKAGES_DIR}/apache-doris-${DORIS_VERSION}-bin-x64.tar.gz"

    if [[ -f "$doris_tar" ]]; then
        log_ok "Doris 包已存在: $(basename "$doris_tar")"
        log_info "文件大小: $(du -h "$doris_tar" | cut -f1)"
    else
        log_info "下载 Doris 统一包..."
        curl -L "$DORIS_DOWNLOAD_URL" \
            -o "$doris_tar" \
            --progress-bar \
            --timeout 600

        log_ok "Doris 下载完成"
    fi
}

# =============================================================================
# 下载 FoundationDB DEB 包 (用于离线构建 FDB 镜像)
# =============================================================================

download_fdb() {
    log_info "下载 FoundationDB ${FDB_VERSION}..."

    local fdb_dir="${OFFLINE_PACKAGES_DIR}/foundationdb"
    mkdir -p "$fdb_dir"

    local client_deb="${fdb_dir}/foundationdb-clients_${FDB_VERSION}_amd64.deb"
    local server_deb="${fdb_dir}/foundationdb-server_${FDB_VERSION}_amd64.deb"

    # 下载 Clients DEB
    if [[ -f "$client_deb" ]]; then
        log_ok "FDB Clients 已存在"
    else
        log_info "下载 FDB Clients..."
        curl -L "${FDB_DOWNLOAD_BASE}/foundationdb-clients_${FDB_VERSION}_amd64.deb" \
            -o "$client_deb" \
            --progress-bar \
            --timeout 120
    fi

    # 下载 Server DEB
    if [[ -f "$server_deb" ]]; then
        log_ok "FDB Server 已存在"
    else
        log_info "下载 FDB Server..."
        curl -L "${FDB_DOWNLOAD_BASE}/foundationdb-server_${FDB_VERSION}_amd64.deb" \
            -o "$server_deb" \
            --progress-bar \
            --timeout 120
    fi

    log_ok "FoundationDB 下载完成"
}

# =============================================================================
# 下载 Doris Operator Bundle (可选，离线部署用)
# =============================================================================

download_operator() {
    log_info "下载 Doris Operator ${OPERATOR_VERSION}..."

    local op_bundle="${OFFLINE_PACKAGES_DIR}/doris-operator-bundle-${OPERATOR_VERSION}.tar.gz"
    local op_url="https://github.com/apache/doris-operator/releases/download/${OPERATOR_VERSION}/doris-operator-bundle-${OPERATOR_VERSION}.tar.gz"

    mkdir -p "$OFFLINE_PACKAGES_DIR"

    if [[ -f "$op_bundle" ]]; then
        log_ok "Operator Bundle 已存在"
    else
        log_info "下载 Operator Bundle..."
        curl -L "$op_url" \
            -o "$op_bundle" \
            --progress-bar \
            --timeout 300
        log_ok "Operator Bundle 下载完成"
    fi
}

# =============================================================================
# 验证包完整性
# =============================================================================

verify_packages() {
    log_info "验证离线包..."

    local missing=()
    local doris_tar="${OFFLINE_PACKAGES_DIR}/apache-doris-${DORIS_VERSION}-bin-x64.tar.gz"

    if [[ ! -f "$doris_tar" ]]; then
        missing+=("Doris 包 (apache-doris-${DORIS_VERSION}-bin-x64.tar.gz)")
    else
        log_ok "Doris: $(basename "$doris_tar") ($(du -h "$doris_tar" | cut -f1))"
    fi

    # FDB DEB 验证
    local fdb_dir="${OFFLINE_PACKAGES_DIR}/foundationdb"
    if [[ -d "$fdb_dir" ]] && [[ -n "$(ls -A "$fdb_dir"/*.deb 2>/dev/null)" ]]; then
        log_ok "FoundationDB: $(ls "$fdb_dir"/*.deb | xargs -n1 basename | tr '\n' ' ')"
    else
        missing+=("FoundationDB DEB packages")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "缺少包: ${missing[*]}"
        return 1
    fi

    log_ok "所有离线包验证通过"
}

# =============================================================================
# 显示完成说明
# =============================================================================

show_instructions() {
    echo ""
    echo "========================================"
    echo "  离线包准备完成"
    echo "========================================"
    echo ""
    echo "包目录: $OFFLINE_PACKAGES_DIR"
    echo ""
    echo "文件列表:"
    echo "  Doris:"
    ls -lh "${OFFLINE_PACKAGES_DIR}"/apache-doris-*.tar.gz 2>/dev/null | awk '{print "    " $NF " (" $5 ")"}' || echo "    (未找到)"
    echo "  FoundationDB:"
    ls -lh "${OFFLINE_PACKAGES_DIR}"/foundationdb/*.deb 2>/dev/null | awk '{print "    " $NF " (" $5 ")"}' || echo "    (未找到)"
    echo ""
    echo "下一步: 运行 ./build-all.sh 开始构建镜像并推送到 Nexus"
    echo ""
}

# =============================================================================
# 主流程
# =============================================================================

main() {
    echo ""
    echo "=========================================="
    echo "  Doris 离线构建前置准备"
    echo "  Doris: ${DORIS_VERSION}"
    echo "  FDB:   ${FDB_VERSION}"
    echo "=========================================="
    echo ""

    local download_only=false
    if [[ "${1:-}" == "--download-only" ]]; then
        download_only=true
    fi

    mkdir -p "$OFFLINE_PACKAGES_DIR"

    # 如果包已存在，直接验证
    if verify_packages 2>/dev/null; then
        log_ok "离线包已完整，准备构建"
    else
        log_warn "离线包不完整，开始下载..."
        download_doris
        download_fdb
    fi

    verify_packages

    if [[ "$download_only" == "false" ]]; then
        show_instructions
    fi
}

main "$@"
