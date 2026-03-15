#!/bin/bash

# ==========================================
# Doris 安全镜像构建脚本 - 支持离线模式
# ==========================================
# Version: 2.0

set -e

# ==========================================
# Configuration
# ==========================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DOCKER_DIR="${PROJECT_DIR}/docker"
CONFIG_DIR="${PROJECT_DIR}/configs"
OFFLINE_DIR="${PROJECT_DIR}/offline-packages"

# 镜像配置
NEXUS_URL="${NEXUS_URL:-nexus.company.com:8082}"
NEXUS_REPO="${NEXUS_REPO:-doris}"
DORIS_VERSION="${DORIS_VERSION:-3.1.4}"
FDB_VERSION="${FDB_VERSION:-7.1.37}"
OPERATOR_VERSION="${OPERATOR_VERSION:-v1.1.0}"

# 构建模式
BUILD_MODE="${BUILD_MODE:-local}"  # local | nexus | gcs

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

# ==========================================
# Functions
# ==========================================

check_prerequisites() {
    log_info "检查构建环境..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        log_error "Docker 未运行"
        exit 1
    fi
    
    # 检查 BuildKit 是否启用
    if ! docker version | grep -q "BuildKit"; then
        log_warn "建议启用 BuildKit 以支持 --secret 功能"
        log_info "启用方法: export DOCKER_BUILDKIT=1"
    fi
    
    log_info "环境检查通过"
}

prepare_offline_context() {
    if [ "$BUILD_MODE" = "local" ]; then
        if [ -d "${OFFLINE_DIR}" ]; then
            log_info "使用本地离线包: ${OFFLINE_DIR}"
            return 0
        else
            log_error "离线包目录不存在: ${OFFLINE_DIR}"
            log_info "请先运行: ./scripts/prepare-offline.sh download"
            exit 1
        fi
    fi
}

build_with_secret() {
    local context="$1"
    local dockerfile="$2"
    local image="$3"
    local extra_args="$4"
    
    # 构建参数
    local build_args="--build-arg DORIS_VERSION=${DORIS_VERSION}"
    build_args="${build_args} --build-arg FDB_VERSION=${FDB_VERSION}"
    build_args="${build_args} --build-arg OPERATOR_VERSION=${OPERATOR_VERSION}"
    build_args="${build_args} --build-arg DOWNLOAD_SOURCE=${BUILD_MODE}"
    build_args="${build_args} --build-arg NEXUS_URL=${NEXUS_URL}"
    build_args="${build_args} --build-arg OFFLINE_PATH=/build-context/offline-packages"
    
    # 如果是 Nexus 模式且有凭据，使用 secret
    if [ "$BUILD_MODE" = "nexus" ] && [ -n "$NEXUS_USER" ] && [ -n "$NEXUS_PASS" ]; then
        # 创建临时 secret 文件
        echo "NEXUS_USER=${NEXUS_USER}" > /tmp/nexus_env
        echo "NEXUS_PASS=${NEXUS_PASS}" >> /tmp/nexus_env
        
        docker build \
            ${build_args} \
            ${extra_args} \
            --secret id=nexus_env,src=/tmp/nexus_env \
            -f "${dockerfile}" \
            -t "${image}" \
            "${context}" \
            --no-cache
            
        rm -f /tmp/nexus_env
    else
        # 本地模式或无凭据
        docker build \
            ${build_args} \
            ${extra_args} \
            -f "${dockerfile}" \
            -t "${image}" \
            "${context}" \
            --no-cache
    fi
}

build_fe() {
    log_info "构建 Doris FE 镜像..."
    
    local image="${NEXUS_URL}/${NEXUS_REPO}/fe:${DORIS_VERSION}-secure"
    
    if [ "$BUILD_MODE" = "local" ]; then
        # 使用离线包构建
        docker build \
            --build-arg DORIS_VERSION=${DORIS_VERSION} \
            --build-arg OFFLINE_PATH=/offline-packages \
            -f "${DOCKER_DIR}/fe/Dockerfile" \
            -t "${image}" \
            --no-cache \
            .
    else
        build_with_secret "." "${DOCKER_DIR}/fe/Dockerfile" "${image}" ""
    fi
    
    log_info "FE 镜像构建完成: ${image}"
}

build_be() {
    log_info "构建 Doris BE 镜像..."
    
    local image="${NEXUS_URL}/${NEXUS_REPO}/be:${DORIS_VERSION}-secure"
    
    if [ "$BUILD_MODE" = "local" ]; then
        docker build \
            --build-arg DORIS_VERSION=${DORIS_VERSION} \
            --build-arg OFFLINE_PATH=/offline-packages \
            -f "${DOCKER_DIR}/be/Dockerfile" \
            -t "${image}" \
            --no-cache \
            .
    else
        build_with_secret "." "${DOCKER_DIR}/be/Dockerfile" "${image}" ""
    fi
    
    log_info "BE 镜像构建完成: ${image}"
}

build_fdb() {
    log_info "构建 FoundationDB 镜像..."
    
    local image="${NEXUS_URL}/foundationdb:${FDB_VERSION}-secure"
    
    if [ "$BUILD_MODE" = "local" ]; then
        docker build \
            --build-arg FDB_VERSION=${FDB_VERSION} \
            --build-arg OFFLINE_PATH=/offline-packages \
            -f "${DOCKER_DIR}/fdb/Dockerfile" \
            -t "${image}" \
            --no-cache \
            .
    else
        build_with_secret "." "${DOCKER_DIR}/fdb/Dockerfile" "${image}" ""
    fi
    
    log_info "FoundationDB 镜像构建完成: ${image}"
}

build_operator() {
    log_info "构建 Doris Operator 镜像..."
    log_warn "Operator 需要 Go 工具链，仅支持在线构建"
    
    local image="${NEXUS_URL}/doris-operator:${OPERATOR_VERSION}-secure"
    
    docker build \
        --build-arg OPERATOR_VERSION=${OPERATOR_VERSION} \
        -f "${DOCKER_DIR}/operator/Dockerfile" \
        -t "${image}" \
        --no-cache \
        .
    
    log_info "Operator 镜像构建完成: ${image}"
}

build_all() {
    log_info "开始构建所有镜像... (模式: ${BUILD_MODE})"
    echo ""
    
    if [ "$BUILD_MODE" = "local" ]; then
        prepare_offline_context
    fi
    
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
    echo " 模式: ${BUILD_MODE}"
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
            echo "环境变量:"
            echo "  BUILD_MODE=local|nexus   构建模式 (默认: local)"
            echo "  NEXUS_URL               Nexus 地址"
            echo "  NEXUS_USER              Nexus 用户名"
            echo "  NEXUS_PASS              Nexus 密码"
            echo "  DORIS_VERSION           Doris 版本"
            echo ""
            echo "示例:"
            echo "  # 本地离线构建"
            echo "  ./scripts/build-images.sh all"
            echo ""
            echo "  # Nexus 构建"
            echo "  BUILD_MODE=nexus NEXUS_PASS=xxx ./scripts/build-images.sh all"
            exit 1
            ;;
    esac
}

main "$@"
