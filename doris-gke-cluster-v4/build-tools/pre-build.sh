#!/bin/bash
#
# build-tools/pre-build.sh
# 构建前置准备：下载 Doris 二进制包、下载 Operator 包
#
# 用法:
#   ./pre-build.sh                    # 交互模式
#   ./pre-build.sh --download-only    # 仅下载，不检查
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE_PACKAGE_DIR="${SOURCE_PACKAGE_DIR:-${PROJECT_ROOT}/source-packages}"

DORIS_VERSION="${DORIS_VERSION:-4.0.4}"
OPERATOR_VERSION="${OPERATOR_VERSION:-1.4.0}"
FDB_VERSION="${FDB_VERSION:-7.1.37}"

DORIS_MIRROR="${DORIS_MIRROR:-https://dlcdn.apache.org/doris}"

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
# 下载 Apache Doris 4.0.4
# =============================================================================

download_doris() {
    log_info "下载 Apache Doris ${DORIS_VERSION}..."

    local fe_url="${DORIS_MIRROR}/apache-doris-${DORIS_VERSION}-fe.tar.gz"
    local be_url="${DORIS_MIRROR}/apache-doris-${DORIS_VERSION}-be.tar.gz"

    mkdir -p "$SOURCE_PACKAGE_DIR"

    # 下载 FE
    log_info "下载 FE: $(basename "$fe_url")"
    if [[ -f "${SOURCE_PACKAGE_DIR}/apache-doris-${DORIS_VERSION}-fe.tar.gz" ]]; then
        log_ok "FE 已存在，跳过下载"
    else
        curl -L "$fe_url" -o "${SOURCE_PACKAGE_DIR}/apache-doris-${DORIS_VERSION}-fe.tar.gz" --progress-bar
    fi

    # 下载 BE
    log_info "下载 BE: $(basename "$be_url")"
    if [[ -f "${SOURCE_PACKAGE_DIR}/apache-doris-${DORIS_VERSION}-be.tar.gz" ]]; then
        log_ok "BE 已存在，跳过下载"
    else
        curl -L "$be_url" -o "${SOURCE_PACKAGE_DIR}/apache-doris-${DORIS_VERSION}-be.tar.gz" --progress-bar
    fi

    log_ok "Doris 下载完成"
}

# =============================================================================
# 下载 Doris Operator
# =============================================================================

download_operator() {
    log_info "下载 Doris Operator ${OPERATOR_VERSION}..."

    local operator_url="https://github.com/selectdb/doris-operator/releases/download/${OPERATOR_VERSION}/doris-operator-${OPERATOR_VERSION}.tar.gz"
    local output="${SOURCE_PACKAGE_DIR}/doris-operator-bundle-${OPERATOR_VERSION}.tar.gz"

    mkdir -p "$SOURCE_PACKAGE_DIR"

    if [[ -f "$output" ]]; then
        log_ok "Operator 已存在，跳过下载"
    else
        curl -L "$operator_url" -o "$output" --progress-bar
        log_ok "Operator 下载完成: $(basename "$output")"
    fi
}

# =============================================================================
# 下载 FoundationDB
# =============================================================================

download_fdb() {
    log_info "下载 FoundationDB ${FDB_VERSION}..."

    local fdb_url="https://www.foundationdb.org/downloads/${FDB_VERSION}/docker/sles15/artifacts.broadcast.tid"
    local output="${SOURCE_PACKAGE_DIR}/foundationdb-${FDB_VERSION}.docker.tar.gz"

    mkdir -p "$SOURCE_PACKAGE_DIR"

    # FoundationDB 镜像会通过 Dockerfile 直接 pull，这里不做额外下载
    log_info "FoundationDB 将通过 DockerHub 直接拉取（fdb:7.1.37）"
}

# =============================================================================
# 验证包完整性
# =============================================================================

verify_packages() {
    log_info "验证包完整性..."

    local missing=()

    local fe_pkg=$(find "$SOURCE_PACKAGE_DIR" -name "*doris*fe*.tar.gz" 2>/dev/null | head -1)
    local be_pkg=$(find "$SOURCE_PACKAGE_DIR" -name "*doris*be*.tar.gz" 2>/dev/null | head -1)
    local op_pkg=$(find "$SOURCE_PACKAGE_DIR" -name "*operator*.tar.gz" 2>/dev/null | head -1)

    if [[ -z "$fe_pkg" ]]; then
        missing+=("FE 包 (apache-doris-${DORIS_VERSION}-fe.tar.gz)")
    else
        log_ok "  FE: $(basename "$fe_pkg")"
    fi

    if [[ -z "$be_pkg" ]]; then
        missing+=("BE 包 (apache-doris-${DORIS_VERSION}-be.tar.gz)")
    else
        log_ok "  BE: $(basename "$be_pkg")"
    fi

    if [[ -z "$op_pkg" ]]; then
        log_warn "  Operator 包未找到 (可选，将在线下载)"
    else
        log_ok "  Operator: $(basename "$op_pkg")"
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "缺少包: ${missing[*]}"
        return 1
    fi

    log_ok "所有包验证通过"
}

# =============================================================================
# 创建源码包目录并显示说明
# =============================================================================

show_instructions() {
    echo ""
    echo "========================================"
    echo "  源码包准备完成"
    echo "========================================"
    echo ""
    echo "包目录: $SOURCE_PACKAGE_DIR"
    echo ""
    echo "文件列表:"
    ls -lh "$SOURCE_PACKAGE_DIR" 2>/dev/null | grep -v "^total" | awk '{print "  " $NF " (" $5 ")"}' || echo "  (空)"
    echo ""
    echo "下一步: 运行 ./build-all.sh 开始构建镜像"
    echo ""
}

# =============================================================================
# 主流程
# =============================================================================

main() {
    echo ""
    echo "=========================================="
    echo "  Doris 构建前置准备"
    echo "  版本: ${DORIS_VERSION}"
    echo "=========================================="
    echo ""

    local download_only=false
    if [[ "${1:-}" == "--download-only" ]]; then
        download_only=true
    fi

    mkdir -p "$SOURCE_PACKAGE_DIR"

    # 如果包已存在，直接验证
    if verify_packages 2>/dev/null; then
        log_ok "包已完整，准备构建"
    else
        log_warn "包不完整，开始下载..."
        download_doris
        download_operator
    fi

    verify_packages

    if [[ "$download_only" == "false" ]]; then
        show_instructions
    fi
}

main "$@"