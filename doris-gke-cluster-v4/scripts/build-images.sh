#!/bin/bash
# =============================================================================
# Doris 镜像构建脚本
# =============================================================================
#
# 用途说明：
#   构建 Doris 集群所需的 Docker 镜像
#
# 支持构建的镜像：
#   1. FE (Frontend) 镜像
#   2. BE (Backend) 镜像
#   3. FoundationDB 镜像（可选）
#   4. Doris Operator 镜像
#
# 构建模式：
#   1. local - 本地离线构建（使用预下载的安装包）
#   2. nexus - 从 Nexus 代理仓库下载构建
#   3. gcs - 从 GCS 下载构建
#
# 为什么需要离线构建？
#   - 内网环境无法访问外网
#   - 构建过程可控
#   - 构建速度更快
#
# 使用前提：
#   1. Docker 已安装并运行
#   2. 离线包已准备（local 模式）
#   3. 有足够的磁盘空间
#
# =============================================================================

# ==========================================
# 版本和配置
# ==========================================
# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 项目根目录
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# Docker 相关文件目录
DOCKER_DIR="${PROJECT_DIR}/docker"
# 配置文件目录
CONFIG_DIR="${PROJECT_DIR}/configs"
# 离线包目录
OFFLINE_DIR="${PROJECT_DIR}/offline-packages"

# 镜像配置
# 为什么使用环境变量默认值？
#   - 方便 CI/CD 集成
#   - 支持不同环境使用不同配置
NEXUS_URL="${NEXUS_URL:-nexus.company.com:8082}"  # 镜像仓库地址
NEXUS_REPO="${NEXUS_REPO:-doris}"                  # 镜像仓库路径
DORIS_VERSION="${DORIS_VERSION:-4.0.4}"            # Doris 版本
FDB_VERSION="${FDB_VERSION:-7.1.37}"               # FoundationDB 版本
OPERATOR_VERSION="${OPERATOR_VERSION:-1.4.0}"     # Operator 版本

# 构建模式
# local: 使用本地离线包
# nexus: 从 Nexus 下载
# gcs: 从 GCS 下载
BUILD_MODE="${BUILD_MODE:-local}"

# ==========================================
# 颜色输出定义
# ==========================================
# 为什么使用颜色？
#   - 便于区分信息类型
#   - 快速定位关键信息
#   - 提升可读性
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'  # No Color

# 日志函数
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ==========================================
# 前置检查函数
# ==========================================
check_prerequisites() {
    log_info "检查构建环境..."

    # 检查 Docker 是否安装
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装或不在 PATH 中"
        exit 1
    fi

    # 检查 Docker 是否运行
    if ! docker info &> /dev/null; then
        log_error "Docker 未运行或无权限访问"
        exit 1
    fi

    # 检查 BuildKit 支持
    # BuildKit 提供更好的构建性能
    # 支持 --secret 等高级功能
    if ! docker version | grep -q "BuildKit"; then
        log_warn "推荐启用 BuildKit 以支持 --secret 功能"
        log_info "启用方式: export DOCKER_BUILDKIT=1"
    fi

    log_info "环境检查通过"
}

# ==========================================
# 离线构建准备
# ==========================================
prepare_offline_context() {
    # local 模式需要检查离线包目录
    if [ "$BUILD_MODE" = "local" ]; then
        if [ -d "${OFFLINE_DIR}" ]; then
            log_info "使用本地离线包: ${OFFLINE_DIR}"
            return 0
        else
            log_error "离线包目录不存在: ${OFFLINE_DIR}"
            log_info "请运行: ./scripts/prepare-offline.sh download"
            exit 1
        fi
    fi
}

# ==========================================
# 构建 FE 镜像
# ==========================================
build_fe() {
    log_info "构建 Doris FE 镜像..."

    # 镜像完整名称
    local image="${NEXUS_URL}/${NEXUS_REPO}/fe:${DORIS_VERSION}-secure"

    # 根据构建模式选择构建方式
    if [ "$BUILD_MODE" = "local" ]; then
        # 本地离线构建
        # 为什么使用 --build-arg OFFLINE_PATH？
        #   - 指定离线包路径
        #   - Dockerfile 会复制到镜像中
        docker build \
            --build-arg DORIS_VERSION=${DORIS_VERSION} \
            --build-arg OFFLINE_PATH=/offline-packages \
            -f "${DOCKER_DIR}/fe/Dockerfile" \
            -t "${image}" \
            --no-cache \
            .
    else
        # 在线构建（从 nexus 或 gcs 下载）
        docker build \
            --build-arg DORIS_VERSION=${DORIS_VERSION} \
            --build-arg OFFLINE_PATH=/offline-packages \
            --build-arg DOWNLOAD_SOURCE=${BUILD_MODE} \
            --build-arg NEXUS_URL=${NEXUS_URL} \
            -f "${DOCKER_DIR}/fe/Dockerfile" \
            -t "${image}" \
            --no-cache \
            .
    fi

    log_info "FE 镜像构建完成: ${image}"
}

# ==========================================
# 构建 BE 镜像
# ==========================================
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
        docker build \
            --build-arg DORIS_VERSION=${DORIS_VERSION} \
            --build-arg OFFLINE_PATH=/offline-packages \
            --build-arg DOWNLOAD_SOURCE=${BUILD_MODE} \
            --build-arg NEXUS_URL=${NEXUS_URL} \
            -f "${DOCKER_DIR}/be/Dockerfile" \
            -t "${image}" \
            --no-cache \
            .
    fi

    log_info "BE 镜像构建完成: ${image}"
}

# ==========================================
# 构建 FoundationDB 镜像
# ==========================================
# FoundationDB 是什么？
#   - 分布式数据库
#   - Doris 部分高级特性依赖它
#   - 普通部署不需要
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
        docker build \
            --build-arg FDB_VERSION=${FDB_VERSION} \
            --build-arg OFFLINE_PATH=/offline-packages \
            --build-arg DOWNLOAD_SOURCE=${BUILD_MODE} \
            -f "${DOCKER_DIR}/fdb/Dockerfile" \
            -t "${image}" \
            --no-cache \
            .
    fi

    log_info "FoundationDB 镜像构建完成: ${image}"
}

# ==========================================
# 构建 Operator 镜像
# ==========================================
# 为什么 Operator 需要特殊处理？
#   - 需要 Go 工具链编译
#   - 源码构建复杂
#   - 通常使用预编译版本
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

# ==========================================
# 构建所有镜像
# ==========================================
build_all() {
    log_info "开始构建所有镜像... (模式: ${BUILD_MODE})"
    echo ""

    # local 模式需要准备离线包
    if [ "$BUILD_MODE" = "local" ]; then
        prepare_offline_context
    fi

    # 按顺序构建各组件
    build_fe
    echo ""

    build_be
    echo ""

    build_fdb
    echo ""

    build_operator
    echo ""

    log_info "所有镜像构建完成！"
    echo ""
    # 显示构建的镜像
    docker images | grep -E "(doris|foundationdb)" | grep "${NEXUS_URL}"
}

# ==========================================
# 主函数
# ==========================================
main() {
    # 默认构建所有镜像
    local target="${1:-all}"

    echo "=========================================="
    echo " Doris ${DORIS_VERSION} 安全镜像构建"
    echo "  模式: ${BUILD_MODE}"
    echo "=========================================="
    echo ""

    # 前置检查
    check_prerequisites
    echo ""

    # 根据目标执行构建
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
            echo "  BUILD_MODE=local|nexus|gcs   构建模式 (默认: local)"
            echo "  NEXUS_URL               镜像仓库地址"
            echo "  NEXUS_USER              镜像仓库用户名"
            echo "  NEXUS_PASS              镜像仓库密码"
            echo "  DORIS_VERSION           Doris 版本 (默认: 2.1.7)"
            echo ""
            echo "示例:"
            echo "  # 本地离线构建"
            echo "  ./scripts/build-images.sh all"
            echo ""
            echo "  # Nexus 在线构建"
            echo "  BUILD_MODE=nexus NEXUS_PASS=xxx ./scripts/build-images.sh all"
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"