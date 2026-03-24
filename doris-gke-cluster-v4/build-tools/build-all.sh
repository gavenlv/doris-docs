#!/bin/bash
#
# build-tools/build-all.sh
# 完整构建流程：从本地包 → 构建镜像 → 推送 Nexus → 验证
#
# 使用场景：
#   1. 用户已下载 Doris 包到 offline-packages/ 目录
#   2. 基于本地包构建 Docker 镜像
#   3. 推送镜像到本地 Nexus
#   4. 部署到 K8s (本地或 GKE)
#
# 环境要求：
#   - Docker with buildx
#   - docker-compose (for Nexus)
#
# 用法:
#   ./build-all.sh                        # 交互模式，使用本地包
#   ./build-all.sh --local-only          # 仅本地构建，不推 Nexus
#   ./build-all.sh -- Doris-4.0.4        # 指定版本
#   ./build-all.sh --skip-build          # 仅推送已构建的镜像
#

set -euo pipefail

# =============================================================================
# 配置
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Doris 版本 - 统一使用 4.0.4
DORIS_VERSION="${DORIS_VERSION:-4.0.4}"
OPERATOR_VERSION="${OPERATOR_VERSION:-1.4.0}"
FDB_VERSION="${FDB_VERSION:-7.1.37}"

# Nexus 配置 (默认本地)
NEXUS_HOST="${NEXUS_HOST:-localhost:5000}"
NEXUS_URL="http://${NEXUS_HOST}"

# 镜像标签
REGISTRY_PREFIX="${NEXUS_HOST}/doris"
FE_IMAGE="${REGISTRY_PREFIX}/fe:${DORIS_VERSION}"
BE_IMAGE="${REGISTRY_PREFIX}/be:${DORIS_VERSION}"
OPERATOR_IMAGE="${REGISTRY_PREFIX}/operator:${OPERATOR_VERSION}"
FDB_IMAGE="${REGISTRY_PREFIX}/fdb:${FDB_VERSION}"

# 本地包目录
OFFLINE_PACKAGE_DIR="${OFFLINE_PACKAGE_DIR:-${PROJECT_ROOT}/offline-packages}"
BUILD_OUTPUT_DIR="${BUILD_OUTPUT_DIR:-${PROJECT_ROOT}/build-output}"

# 动作标志
LOCAL_ONLY=false
SKIP_BUILD=false
SKIP_PUSH=false
SKIP_NEXUS_START=false

# =============================================================================
# 颜色输出
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}   $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# =============================================================================
# 解析参数
# =============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --local-only)
                LOCAL_ONLY=true
                SKIP_PUSH=true
                shift
                ;;
            --skip-build)
                SKIP_BUILD=true
                shift
                ;;
            --skip-push)
                SKIP_PUSH=true
                shift
                ;;
            --skip-nexus-start)
                SKIP_NEXUS_START=true
                shift
                ;;
            --nexus-host)
                NEXUS_HOST="$2"
                shift 2
                ;;
            --*)
                log_error "Unknown option: $1"
                exit 1
                ;;
            *)
                if [[ -z "${DORIS_VERSION:-}" ]] || [[ "$1" =~ ^[0-9]+\.[0-9]+ ]]; then
                    DORIS_VERSION="$1"
                    FE_IMAGE="${REGISTRY_PREFIX}/fe:${DORIS_VERSION}"
                    BE_IMAGE="${REGISTRY_PREFIX}/be:${DORIS_VERSION}"
                fi
                shift
                ;;
        esac
    done
}

# =============================================================================
# 前置检查
# =============================================================================

check_prerequisites() {
    log_info "检查前置条件..."

    local missing=()
    for cmd in docker buildx curl tar gzip; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "缺少必要工具: ${missing[*]}"
        exit 1
    fi

    if ! docker buildx version &> /dev/null; then
        log_error "Docker buildx 未启用。请运行: docker buildx install"
        exit 1
    fi

    if [[ "$SKIP_BUILD" == "false" ]]; then
        check_local_packages
    fi
}

# =============================================================================
# 检查本地包
# =============================================================================

check_local_packages() {
    log_info "检查本地包目录: $OFFLINE_PACKAGE_DIR"

    if [[ ! -d "$OFFLINE_PACKAGE_DIR" ]]; then
        mkdir -p "$OFFLINE_PACKAGE_DIR"
        log_warn "已创建离线包目录: $OFFLINE_PACKAGE_DIR"
        log_warn "请将 Apache Doris 4.0.4 包放入此目录"
    fi

    local package_name="apache-doris-${DORIS_VERSION}-bin-x64.tar.gz"
    local package_path="${OFFLINE_PACKAGE_DIR}/${package_name}"

    if [[ -f "$package_path" ]]; then
        log_ok "找到本地包: $package_name"
        SOURCE_TAR="$package_path"
    else
        log_error "未找到本地包: $package_path"
        log_error "请从 https://doris.apache.org/zh-CN/download/ 下载 Apache Doris ${DORIS_VERSION}"
        log_error "并重命名为: $package_name"
        log_error "放入目录: $OFFLINE_PACKAGE_DIR"
        exit 1
    fi

    log_info "使用本地包: $(basename "$SOURCE_TAR")"
}

# =============================================================================
# 启动 Nexus (docker-compose)
# =============================================================================

start_nexus() {
    if [[ "$SKIP_NEXUS_START" == "true" ]]; then
        log_info "跳过 Nexus 启动（--skip-nexus-start）"
        return
    fi

    log_info "启动本地 Nexus..."

    local nexus_compose="${SCRIPT_DIR}/nexus-docker-compose.yaml"

    if [[ ! -f "$nexus_compose" ]]; then
        log_error "Nexus docker-compose 文件不存在: $nexus_compose"
        exit 1
    fi

    docker compose -f "$nexus_compose" up -d

    log_info "等待 Nexus 启动就绪..."
    local max_wait=120
    local count=0
    while [[ $count -lt $max_wait ]]; do
        if curl -s -o /dev/null -w "%{http_code}" "${NEXUS_URL}/" | grep -q "200\|401"; then
            log_ok "Nexus 已就绪 (${NEXUS_URL})"
            return
        fi
        sleep 3
        count=$((count + 3))
        echo -n "."
    done

    log_error "Nexus 启动超时"
    exit 1
}

# =============================================================================
# 配置 Nexus Docker Registry
# =============================================================================

configure_nexus_docker() {
    log_info "配置 Nexus Docker Registry..."

    local admin_password="${NEXUS_PASSWORD:-admin123}"

    sleep 5

    docker login "${NEXUS_HOST}" -u admin -p "$admin_password" 2>/dev/null || true
}

# =============================================================================
# 构建镜像
# =============================================================================

build_images() {
    if [[ "$SKIP_BUILD" == "true" ]]; then
        log_info "跳过镜像构建（--skip-build）"
        return
    fi

    log_info "开始构建镜像 (Doris ${DORIS_VERSION})..."
    log_info "使用本地包: $SOURCE_TAR"

    mkdir -p "$BUILD_OUTPUT_DIR"

    docker buildx use default 2>/dev/null || \
        docker buildx create --name mybuilder --use 2>/dev/null || true
    docker buildx inspect --bootstrap &> /dev/null || true

    # --- 构建 FE 镜像 ---
    log_info "构建 FE 镜像: ${FE_IMAGE}"
    docker buildx build \
        --build-arg DORIS_VERSION="$DORIS_VERSION" \
        --build-arg SOURCE_TAR="$SOURCE_TAR" \
        -t "${FE_IMAGE}" \
        -f "${PROJECT_ROOT}/docker/fe/Dockerfile" \
        "${PROJECT_ROOT}" \
        --progress=plain \
        --load

    log_ok "FE 镜像构建完成: ${FE_IMAGE}"

    # --- 构建 BE 镜像 ---
    log_info "构建 BE 镜像: ${BE_IMAGE}"
    docker buildx build \
        --build-arg DORIS_VERSION="$DORIS_VERSION" \
        --build-arg SOURCE_TAR="$SOURCE_TAR" \
        -t "${BE_IMAGE}" \
        -f "${PROJECT_ROOT}/docker/be/Dockerfile" \
        "${PROJECT_ROOT}" \
        --progress=plain \
        --load

    log_ok "BE 镜像构建完成: ${BE_IMAGE}"

    # --- 构建 FDB 镜像 ---
    log_info "构建 FDB 镜像: ${FDB_IMAGE}"
    docker buildx build \
        --build-arg FDB_VERSION="$FDB_VERSION" \
        --build-arg OFFLINE_PATH="$OFFLINE_PACKAGE_DIR" \
        -t "${FDB_IMAGE}" \
        -f "${PROJECT_ROOT}/docker/fdb/Dockerfile" \
        "${PROJECT_ROOT}" \
        --progress=plain \
        --load

    log_ok "FDB 镜像构建完成: ${FDB_IMAGE}"

    log_ok "所有镜像构建完成！"
    echo ""
    echo "镜像列表:"
    echo "  FE -> ${FE_IMAGE}"
    echo "  BE -> ${BE_IMAGE}"
    echo "  FDB -> ${FDB_IMAGE}"
}

# =============================================================================
# 推送镜像到 Nexus
# =============================================================================

push_images() {
    if [[ "$SKIP_PUSH" == "true" ]]; then
        log_info "跳过镜像推送（--skip-push）"
        return
    fi

    log_info "推送镜像到 Nexus: ${NEXUS_URL}"

    for img in "${FE_IMAGE}" "${BE_IMAGE}" "${FDB_IMAGE}"; do
        log_info "推送: $img"
        docker push "$img"
    done

    log_ok "所有镜像推送完成！"
}

# =============================================================================
# 验证镜像
# =============================================================================

verify_images() {
    log_info "验证镜像..."

    local images=("${FE_IMAGE}" "${BE_IMAGE}" "${FDB_IMAGE}")
    local all_ok=true

    for img in "${images[@]}"; do
        if docker image inspect "$img" &> /dev/null; then
            log_ok "  ✓ $(basename "$img")"
        else
            log_error "  ✗ $(basename "$img") - 未找到"
            all_ok=false
        fi
    done

    if [[ "$all_ok" == "false" ]]; then
        log_error "部分镜像缺失"
        exit 1
    fi

    log_ok "所有镜像验证通过"
}

# =============================================================================
# 生成部署配置
# =============================================================================

generate_deploy_config() {
    local output="${BUILD_OUTPUT_DIR}/deploy-config.env"

    cat > "$output" << EOF
# Doris 镜像部署配置
# 由 build-tools/build-all.sh 自动生成
# 时间: $(date -u '+%Y-%m-%dT%H:%M:%SZ')

# =============================================================================
# 版本信息
# =============================================================================
DORIS_VERSION=${DORIS_VERSION}
OPERATOR_VERSION=${OPERATOR_VERSION}
FDB_VERSION=${FDB_VERSION}

# =============================================================================
# Nexus 配置
# =============================================================================
NEXUS_HOST=${NEXUS_HOST}
NEXUS_URL=${NEXUS_URL}
NEXUS_REGISTRY=${NEXUS_HOST}/doris

# =============================================================================
# 镜像地址 (从 Nexus 拉取)
# =============================================================================
FE_IMAGE=${FE_IMAGE}
BE_IMAGE=${BE_IMAGE}

# =============================================================================
# Kubernetes 部署示例
# =============================================================================
# 在 k8s-local 或 k8s-gke 部署前，设置环境变量：
#   export NEXUS_REGISTRY=${NEXUS_HOST}/doris
#
# 或在 deploy.sh 中替换 \${NEXUS_REGISTRY} 为实际地址
EOF

    log_ok "部署配置已生成: $output"
    echo ""
    echo "使用方式:"
    echo "  source $output"
    echo "  export NEXUS_REGISTRY=${NEXUS_HOST}/doris"
}

# =============================================================================
# 主流程
# =============================================================================

main() {
    echo ""
    echo "=========================================="
    echo "  Doris 镜像构建工具"
    echo "  版本: ${DORIS_VERSION}"
    echo "  本地包: ${OFFLINE_PACKAGE_DIR}"
    echo "  Nexus: ${NEXUS_URL}"
    echo "=========================================="
    echo ""

    parse_args "$@"
    check_prerequisites
    start_nexus
    configure_nexus_docker
    build_images
    push_images
    verify_images
    generate_deploy_config

    echo ""
    echo "=========================================="
    log_ok "构建完成！"
    echo "=========================================="
    echo ""
    echo "下一步:"
    echo "  1. 启动 Nexus: docker compose -f nexus-docker-compose.yaml up -d"
    echo "  2. 部署到 K8s:"
    echo "     - 本地: cd ../k8s-local && ./deploy.sh"
    echo "     - GKE:  cd ../k8s-gke && ./deploy.sh"
}

main "$@"