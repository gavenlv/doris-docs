#!/bin/bash

# ==========================================
# Doris GKE Cluster - Image Build Script
# ==========================================
# Purpose: 构建安全加固的 Docker 镜像
# Version: 1.0

set -e

# ==========================================
# Configuration
# ==========================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DOCKER_DIR="${PROJECT_DIR}/docker"
CONFIG_DIR="${PROJECT_DIR}/configs"
REPORTS_DIR="${PROJECT_DIR}/reports"

# 镜像配置
NEXUS_URL="${NEXUS_URL:-nexus.company.com:8082}"
NEXUS_REPO="${NEXUS_REPO:-doris}"
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
log_build() { echo -e "${BLUE}[BUILD]${NC} $1"; }

# ==========================================
# Functions
# ==========================================

check_prerequisites() {
    log_info "检查构建环境..."
    
    # 检查 Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装"
        exit 1
    fi
    
    # 检查 Docker 是否运行
    if ! docker info &> /dev/null; then
        log_error "Docker 未运行"
        exit 1
    fi
    
    # 创建报告目录
    mkdir -p "${REPORTS_DIR}"
    
    log_info "环境检查通过"
}

build_fe() {
    log_build "构建 Doris FE 镜像..."
    
    cd "${DOCKER_DIR}/fe"
    
    docker build \
        --build-arg DORIS_VERSION=${DORIS_VERSION} \
        --tag ${NEXUS_URL}/${NEXUS_REPO}/fe:${DORIS_VERSION}-secure \
        --tag ${NEXUS_URL}/${NEXUS_REPO}/fe:latest \
        --no-cache \
        --platform linux/amd64 \
        .
    
    log_info "FE 镜像构建完成: ${NEXUS_URL}/${NEXUS_REPO}/fe:${DORIS_VERSION}-secure"
}

build_be() {
    log_build "构建 Doris BE 镜像..."
    
    cd "${DOCKER_DIR}/be"
    
    docker build \
        --build-arg DORIS_VERSION=${DORIS_VERSION} \
        --tag ${NEXUS_URL}/${NEXUS_REPO}/be:${DORIS_VERSION}-secure \
        --tag ${NEXUS_URL}/${NEXUS_REPO}/be:latest \
        --no-cache \
        --platform linux/amd64 \
        .
    
    log_info "BE 镜像构建完成: ${NEXUS_URL}/${NEXUS_REPO}/be:${DORIS_VERSION}-secure"
}

build_fdb() {
    log_build "构建 FoundationDB 镜像..."
    
    cd "${DOCKER_DIR}/fdb"
    
    docker build \
        --build-arg FDB_VERSION=${FDB_VERSION} \
        --tag ${NEXUS_URL}/foundationdb:${FDB_VERSION}-secure \
        --tag ${NEXUS_URL}/foundationdb:latest \
        --no-cache \
        --platform linux/amd64 \
        .
    
    log_info "FoundationDB 镜像构建完成: ${NEXUS_URL}/foundationdb:${FDB_VERSION}-secure"
}

build_operator() {
    log_build "构建 Doris Operator 镜像..."
    
    cd "${DOCKER_DIR}/operator"
    
    docker build \
        --build-arg OPERATOR_VERSION=${OPERATOR_VERSION} \
        --tag ${NEXUS_URL}/doris-operator:${OPERATOR_VERSION}-secure \
        --tag ${NEXUS_URL}/doris-operator:latest \
        --no-cache \
        --platform linux/amd64 \
        .
    
    log_info "Operator 镜像构建完成: ${NEXUS_URL}/doris-operator:${OPERATOR_VERSION}-secure"
}

build_all() {
    log_info "开始构建所有镜像..."
    echo ""
    
    build_fe
    echo ""
    
    build_be
    echo ""
    
    build_fdb
    echo ""
    
    build_operator
    echo ""
    
    log_info "所有镜像构建完成!"
    echo ""
    docker images | grep -E "(doris|foundationdb)" | grep "${NEXUS_URL}"
}

# ==========================================
# Main
# ==========================================

main() {
    local target="${1:-all}"
    
    echo "=========================================="
    echo " Doris 安全加固镜像构建"
    echo "=========================================="
    echo ""
    
    check_prerequisites
    echo ""
    
    case "$target" in
        fe)
            build_fe
            ;;
        be)
            build_be
            ;;
        fdb)
            build_fdb
            ;;
        operator)
            build_operator
            ;;
        all)
            build_all
            ;;
        *)
            echo "用法: $0 {all|fe|be|fdb|operator}"
            echo ""
            echo "目标:"
            echo "  all      - 构建所有镜像"
            echo "  fe       - 仅构建 FE 镜像"
            echo "  be       - 仅构建 BE 镜像"
            echo "  fdb      - 仅构建 FoundationDB 镜像"
            echo "  operator - 仅构建 Operator 镜像"
            exit 1
            ;;
    esac
}

main "$@"
