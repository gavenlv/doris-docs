#!/bin/bash
#
# build-tools/build-all.sh
# 完整构建流程：从下载包 → 构建镜像 → 推送 Nexus → 验证
#
# 用法:
#   ./build-all.sh                    # 交互模式
#   ./build-all.sh --local-only       # 仅本地构建，不推 Nexus
#   ./build-all.sh -- Doris-4.0.4     # 指定版本
#   ./build-all.sh --skip-build       # 仅推送已构建的镜像
#

set -euo pipefail

# =============================================================================
# 配置
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 默认配置
DORIS_VERSION="${DORIS_VERSION:-4.0.4}"
OPERATOR_VERSION="${OPERATOR_VERSION:-1.4.0}"
FDB_VERSION="${FDB_VERSION:-7.1.37}"

NEXUS_HOST="${NEXUS_HOST:-localhost:5000}"
NEXUS_URL="http://${NEXUS_HOST}"

REGISTRY_PREFIX="${NEXUS_HOST}/doris"
FE_IMAGE="${REGISTRY_PREFIX}/fe:${DORIS_VERSION}"
BE_IMAGE="${REGISTRY_PREFIX}/be:${DORIS_VERSION}"
OPERATOR_IMAGE="${REGISTRY_PREFIX}/operator:${OPERATOR_VERSION}"
FDB_IMAGE="${REGISTRY_PREFIX}/fdb:${FDB_VERSION}"

# 本地包目录（用户预先放置下载的 Doris 二进制包）
SOURCE_PACKAGE_DIR="${SOURCE_PACKAGE_DIR:-${PROJECT_ROOT}/source-packages}"
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
                # 第一个非选项参数是版本号
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

    for cmd in docker buildx curl jq tar gzip; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "缺少必要工具: ${missing[*]}"
        exit 1
    fi

    # 检查 Docker buildx 是否可用
    if ! docker buildx version &> /dev/null; then
        log_error "Docker buildx 未启用。请运行: docker buildx install"
        exit 1
    fi

    # 检查源码包
    if [[ "$SKIP_BUILD" == "false" ]]; then
        if [[ ! -d "$SOURCE_PACKAGE_DIR" ]]; then
            log_warn "源码包目录不存在: $SOURCE_PACKAGE_DIR"
            log_warn "将在当前目录创建，请将 Apache Doris 二进制包放入其中"
            mkdir -p "$SOURCE_PACKAGE_DIR"
        fi

        local fe_pkg=$(find "$SOURCE_PACKAGE_DIR" -name "*doris*fe*.tar.xz" -o -name "*doris*fe*.tar.gz" 2>/dev/null | head -1)
        local be_pkg=$(find "$SOURCE_PACKAGE_DIR" -name "*doris*be*.tar.xz" -o -name "*doris*be*.tar.gz" 2>/dev/null | head -1)

        if [[ -z "$fe_pkg" ]] || [[ -z "$be_pkg" ]]; then
            log_error "未找到 Doris FE/BE 源码包。"
            log_error "请从 https://doris.apache.org/zh-CN/download/ 下载 Apache Doris 4.0.4 并放入:"
            log_error "  $SOURCE_PACKAGE_DIR"
            log_error "需要包含: apache-doris-fe-*.tar.gz 和 apache-doris-be-*.tar.gz"
            exit 1
        fi

        log_ok "源码包检查通过"
        log_info "  FE: $(basename "$fe_pkg")"
        log_info "  BE: $(basename "$be_pkg")"
    fi
}

# =============================================================================
# 启动 Nexus（docker-compose）
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

    # 启动 Nexus
    docker compose -f "$nexus_compose" up -d

    # 等待 Nexus 就绪
    log_info "等待 Nexus 启动就绪..."
    local max_wait=60
    local count=0
    while [[ $count -lt $max_wait ]]; do
        if curl -s "${NEXUS_URL}/repository/doris-docker/" &> /dev/null || \
           curl -s -o /dev/null -w "%{http_code}" "${NEXUS_URL}/" | grep -q "200\|401"; then
            log_ok "Nexus 已就绪"
            return
        fi
        sleep 2
        count=$((count + 2))
        echo -n "."
    done

    log_error "Nexus 启动超时"
    exit 1
}

# =============================================================================
# 登录 Nexus
# =============================================================================

nexus_login() {
    log_info "登录 Nexus..."

    local admin_password="${NEXUS_PASSWORD:-admin123}"

    # 尝试登录
    if docker login "${NEXUS_HOST}" -u admin -p "$admin_password" &> /dev/null; then
        log_ok "Nexus 登录成功"
    else
        log_warn "Nexus 登录失败，尝试匿名推送..."
    fi
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

    # 创建输出目录
    mkdir -p "$BUILD_OUTPUT_DIR"

    # 确保 buildx builder 可用
    docker buildx use default 2>/dev/null || docker buildx create --name mybuilder --use 2>/dev/null || true
    docker buildx inspect --bootstrap &> /dev/null || true

    local fe_pkg be_pkg
    fe_pkg=$(find "$SOURCE_PACKAGE_DIR" -name "*doris*fe*.tar.xz" -o -name "*doris*fe*.tar.gz" 2>/dev/null | head -1)
    be_pkg=$(find "$SOURCE_PACKAGE_DIR" -name "*doris*be*.tar.xz" -o -name "*doris*be*.tar.gz" 2>/dev/null | head -1)

    # --- 构建 FE 镜像 ---
    log_info "构建 FE 镜像: ${FE_IMAGE}"
    docker build \
        --build-arg DORIS_VERSION="$DORIS_VERSION" \
        --build-arg SOURCE_TAR="$fe_pkg" \
        -t "${FE_IMAGE}" \
        -f "${PROJECT_ROOT}/docker/fe/Dockerfile" \
        "${PROJECT_ROOT}" \
        --progress=plain

    log_ok "FE 镜像构建完成: ${FE_IMAGE}"

    # --- 构建 BE 镜像 ---
    log_info "构建 BE 镜像: ${BE_IMAGE}"
    docker build \
        --build-arg DORIS_VERSION="$DORIS_VERSION" \
        --build-arg SOURCE_TAR="$be_pkg" \
        -t "${BE_IMAGE}" \
        -f "${PROJECT_ROOT}/docker/be/Dockerfile" \
        "${PROJECT_ROOT}" \
        --progress=plain

    log_ok "BE 镜像构建完成: ${BE_IMAGE}"

    # --- 构建 FDB 镜像 ---
    log_info "构建 FDB 镜像: ${FDB_IMAGE}"
    docker build \
        --build-arg FDB_VERSION="$FDB_VERSION" \
        -t "${FDB_IMAGE}" \
        -f "${PROJECT_ROOT}/docker/fdb/Dockerfile" \
        "${PROJECT_ROOT}" \
        --progress=plain

    log_ok "FDB 镜像构建完成: ${FDB_IMAGE}"

    # --- 构建 Operator 镜像 ---
    log_info "构建 Operator 镜像: ${OPERATOR_IMAGE}"
    build_operator_image

    log_ok "所有镜像构建完成！"
    echo ""
    echo "镜像列表:"
    echo "  FE       -> ${FE_IMAGE}"
    echo "  BE       -> ${BE_IMAGE}"
    echo "  FDB      -> ${FDB_IMAGE}"
    echo "  Operator -> ${OPERATOR_IMAGE}"
}

# =============================================================================
# 构建 Operator 镜像（从离线包）
# =============================================================================

build_operator_image() {
    local offline_bundle="${SOURCE_PACKAGE_DIR}/doris-operator-bundle-${OPERATOR_VERSION}.tar.gz"

    if [[ -f "$offline_bundle" ]]; then
        tar -xzf "$offline_bundle" -C "$BUILD_OUTPUT_DIR"
        local operator_path="${BUILD_OUTPUT_DIR}/doris-operator"
    else
        log_warn "未找到 Operator 离线包，将使用在线构建"
        # 从 GitHub 下载 operator
        local operator_url="https://github.com/selectdb/doris-operator/releases/download/${OPERATOR_VERSION}/doris-operator-${OPERATOR_VERSION}.tar.gz"
        log_info "下载 Doris Operator: $operator_url"

        mkdir -p "${BUILD_OUTPUT_DIR}/doris-operator"
        if curl -L "$operator_url" -o "${BUILD_OUTPUT_DIR}/operator.tar.gz" 2>/dev/null; then
            tar -xzf "${BUILD_OUTPUT_DIR}/operator.tar.gz" -C "${BUILD_OUTPUT_DIR}/doris-operator"
            local operator_path="${BUILD_OUTPUT_DIR}/doris-operator"
        else
            log_error "无法下载 Operator"
            return 1
        fi
    fi

    if [[ -d "$operator_path" ]]; then
        docker build \
            -t "${OPERATOR_IMAGE}" \
            -f "${operator_path}/docker/Dockerfile" \
            "${operator_path}" \
            --progress=plain
    fi
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

    # 标记镜像为多架构
    for img in "${FE_IMAGE}" "${BE_IMAGE}" "${FDB_IMAGE}" "${OPERATOR_IMAGE}"; do
        log_info "推送: $img"

        if docker tag "$(docker images -q $img)" "${NEXUS_HOST}/$(basename $img)"; then
            docker push "$img" --all-tags
        else
            docker push "$img"
        fi
    done

    log_ok "所有镜像推送完成！"
}

# =============================================================================
# 验证镜像
# =============================================================================

verify_images() {
    log_info "验证镜像..."

    local images=("$FE_IMAGE" "$BE_IMAGE" "$FDB_IMAGE" "$OPERATOR_IMAGE")
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
# 生成镜像配置（供部署脚本使用）
# =============================================================================

generate_image_config() {
    local output="${BUILD_OUTPUT_DIR}/image-config.env"

    cat > "$output" << EOF
# 自动生成的镜像配置
# 由 build-tools/build-all.sh 生成
# 时间: $(date -u '+%Y-%m-%dT%H:%M:%SZ')

DORIS_VERSION=${DORIS_VERSION}
OPERATOR_VERSION=${OPERATOR_VERSION}
FDB_VERSION=${FDB_VERSION}

NEXUS_HOST=${NEXUS_HOST}
NEXUS_URL=${NEXUS_URL}
REGISTRY_PREFIX=${REGISTRY_PREFIX}

FE_IMAGE=${FE_IMAGE}
BE_IMAGE=${BE_IMAGE}
OPERATOR_IMAGE=${OPERATOR_IMAGE}
FDB_IMAGE=${FDB_IMAGE}

# K8s 部署使用的镜像（从 Nexus 拉取）
# 用于 k8s-local 和 k8s-gke 的 imagePullSecrets
K8S_IMAGE_PULL_SECRET=doris-registry
EOF

    log_ok "镜像配置已生成: $output"
    echo ""
    echo "部署时请设置环境变量或在 Kubernetes Secret 中配置 Nexus 凭证"
    echo "  export NEXUS_HOST=${NEXUS_HOST}"
    echo "  export NEXUS_PASSWORD=admin123"
}

# =============================================================================
# 主流程
# =============================================================================

main() {
    echo ""
    echo "=========================================="
    echo "  Doris 镜像构建工具 (build-all.sh)"
    echo "  版本: ${DORIS_VERSION}"
    echo "  Nexus: ${NEXUS_URL}"
    echo "=========================================="
    echo ""

    parse_args "$@"
    check_prerequisites
    start_nexus
    nexus_login
    build_images
    push_images
    verify_images
    generate_image_config

    echo ""
    echo "=========================================="
    log_ok "构建完成！"
    echo "=========================================="
}

main "$@"