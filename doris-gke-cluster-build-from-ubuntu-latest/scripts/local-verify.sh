#!/bin/bash

# ==========================================
# Doris 安全镜像 - 本地验证脚本
# ==========================================
# Purpose: 在本地验证完整的镜像构建流程
# Version: 1.0

set -e

# ==========================================
# Configuration
# ==========================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Nexus 配置
NEXUS_URL="localhost:8082"
NEXUS_UI_URL="localhost:8081"
NEXUS_USER="admin"
NEXUS_PASS="admin123"
NEXUS_REPO_DOCKER="doris-docker"
NEXUS_REPO_RAW="doris-packages"

# 版本配置
DORIS_VERSION="3.1.4"
FDB_VERSION="7.1.37"

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
log_phase() { echo -e "${CYAN}[PHASE]${NC} $1"; }

# ==========================================
# Functions
# ==========================================

check_docker() {
    log_info "检查 Docker 环境..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        log_error "Docker 未运行"
        exit 1
    fi
    
    # 检查 docker-compose
    if ! command -v docker-compose &> /dev/null; then
        log_warn "docker-compose 未安装，将使用 docker compose"
    fi
    
    log_info "Docker 环境正常"
}

start_nexus() {
    log_phase "启动 Nexus..."
    
    # 检查 Nexus 是否已运行
    if docker ps | grep -q doris-nexus; then
        log_info "Nexus 已在运行"
    else
        log_info "启动 Nexus 容器..."
        cd "${PROJECT_DIR}"
        
        # 启动 Nexus
        docker-compose up -d nexus
        
        # 等待 Nexus 启动
        log_info "等待 Nexus 启动..."
        local max_attempts=60
        local attempt=0
        
        while [ $attempt -lt $max_attempts ]; do
            if curl -sf "${NEXUS_UI_URL}/service/metrics/ping" > /dev/null 2>&1; then
                log_info "Nexus 已启动"
                break
            fi
            attempt=$((attempt + 1))
            echo -n "."
            sleep 2
        done
        echo ""
        
        if [ $attempt -eq $max_attempts ]; then
            log_error "Nexus 启动超时"
            exit 1
        fi
    fi
    
    # 等待 admin 密码生成
    sleep 10
    
    log_info "Nexus 已就绪: ${NEXUS_UI_URL}"
    log_info "默认账号: admin / admin123"
}

configure_nexus() {
    log_phase "配置 Nexus..."
    
    # 等待 Nexus 完全初始化
    sleep 20
    
    # 创建 Docker Hosted Repository (用于推送镜像)
    log_info "创建 Docker 仓库..."
    curl -sf -u "${NEXUS_USER}:${NEXUS_PASS}" \
        -X POST "${NEXUS_UI_URL}/service/rest/v1/repositories/docker/hosted" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "doris-docker",
            "online": true,
            "storage": {
                "blobStoreName": "default",
                "strictContentTypeValidation": true,
                "writePolicy": "ALLOW"
            },
            "docker": {
                "httpPort": 8082,
                "forceBasicAuth": false,
                "anonymousPull": false
            },
            "cleanup": {
                "policyNames": []
            }
        }' || log_warn "仓库可能已存在"
    
    # 创建 Raw Repository (用于存储离线包)
    log_info "创建 Raw 仓库..."
    curl -sf -u "${NEXUS_USER}:${NEXUS_PASS}" \
        -X POST "${NEXUS_UI_URL}/service/rest/v1/repositories/raw/hosted" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "doris-packages",
            "online": true,
            "storage": {
                "blobStoreName": "default",
                "strictContentTypeValidation": false,
                "writePolicy": "ALLOW"
            }
        }' || log_warn "仓库可能已存在"
    
    # 启用 Docker Bearer Token
    log_info "配置 Docker Bearer Token..."
    curl -sf -u "${NEXUS_USER}:${NEXUS_PASS}" \
        -X PUT "${NEXUS_UI_URL}/service/rest/v1/security/docker Bearer Token" \
        -H "Content-Type: application/json" \
        -d '{
            "enabled": true,
            "forceBasicAuth": false,
            "tokenRealm": "Nexus Authorizing Token Realm"
        }' || true
    
    # 创建 anonymous 用户访问权限
    curl -sf -u "${NEXUS_USER}:${NEXUS_PASS}" \
        -X PUT "${NEXUS_UI_URL}/service/rest/v1/security/anonymous" \
        -H "Content-Type: application/json" \
        -d '{
            "enabled": true,
            "userId": "anonymous",
            "realmName": "Nexus Authorizing LDAP Realm"
        }' || true
    
    # 为 doris-docker 仓库添加匿名访问
    curl -sf -u "${NEXUS_USER}:${NEXUS_PASS}" \
        -X POST "${NEXUS_UI_URL}/service/rest/v1/security/privileges" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "doris-docker-all",
            "description": "All privileges for doris-docker",
            "actions": ["READ", "EDIT", "DELETE", "ADD", "RUN"],
            "repository": "doris-docker",
            "format": "docker"
        }' || true
    
    # 为 doris-packages 仓库添加匿名访问
    curl -sf -u "${NEXUS_USER}:${NEXUS_PASS}" \
        -X POST "${NEXUS_UI_URL}/service/rest/v1/security/privileges" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "doris-packages-all",
            "description": "All privileges for doris-packages",
            "actions": ["READ", "EDIT", "DELETE", "ADD", "RUN"],
            "repository": "doris-packages",
            "format": "raw"
        }' || true
    
    # 创建匿名角色
    curl -sf -u "${NEXUS_USER}:${NEXUS_PASS}" \
        -X POST "${NEXUS_UI_URL}/service/rest/v1/security/roles" \
        -H "Content-Type: application/json" \
        -d '{
            "id": "dorisanon",
            "name": "Doris Anonymous",
            "description": "Anonymous access for Doris",
            "privileges": ["doris-docker-all", "doris-packages-all"],
            "roles": []
        }' || true
    
    # 为 anonymous 用户分配角色
    curl -sf -u "${NEXUS_USER}:${NEXUS_PASS}" \
        -X PUT "${NEXUS_UI_URL}/service/rest/v1/security/users/anonymous" \
        -H "Content-Type: application/json" \
        -d '{
            "userId": "anonymous",
            "firstName": "Anonymous",
            "lastName": "User",
            "email": "anonymous@example.com",
            "password": "",
            "status": "active",
            "roles": ["dorisanon"]
        }' || true
    
    log_info "Nexus 配置完成"
    echo ""
    echo "Nexus 配置信息:"
    echo "  Docker Repository: ${NEXUS_URL}"
    echo "  Raw Repository:    ${NEXUS_UI_URL}/repository/doris-packages/"
    echo "  用户名: ${NEXUS_USER}"
    echo "  密码: ${NEXUS_PASS}"
}

prepare_offline_packages() {
    log_phase "准备离线包..."
    
    local offline_dir="${PROJECT_DIR}/offline-packages"
    mkdir -p "${offline_dir}/doris-fe"
    mkdir -p "${offline_dir}/doris-be"
    mkdir -p "${offline_dir}/foundationdb"
    
    # 检查是否已有离线包
    if [ -f "${offline_dir}/doris-fe/apache-doris-fe-${DORIS_VERSION}-bin.tar.gz" ]; then
        log_info "离线包已存在，跳过下载"
        return 0
    fi
    
    log_info "下载 Doris FE..."
    wget -q "https://archive.apache.org/dist/doris/${DORIS_VERSION}/apache-doris-fe-${DORIS_VERSION}-bin.tar.gz" \
        -O "${offline_dir}/doris-fe/apache-doris-fe-${DORIS_VERSION}-bin.tar.gz" &
    
    log_info "下载 Doris BE..."
    wget -q "https://archive.apache.org/dist/doris/${DORIS_VERSION}/apache-doris-be-${DORIS_VERSION}-bin-x86_64.tar.gz" \
        -O "${offline_dir}/doris-be/apache-doris-be-${DORIS_VERSION}-bin-x86_64.tar.gz" &
    
    log_info "下载 FoundationDB..."
    wget -q "https://github.com/apple/foundationdb/releases/download/${FDB_VERSION}/foundationdb-clients_${FDB_VERSION}-1_amd64.deb" \
        -O "${offline_dir}/foundationdb/foundationdb-clients_${FDB_VERSION}-1_amd64.deb" &
    wget -q "https://github.com/apple/foundationdb/releases/download/${FDB_VERSION}/foundationdb-server_${FDB_VERSION}-1_amd64.deb" \
        -O "${offline_dir}/foundationdb/foundationdb-server_${FDB_VERSION}-1_amd64.deb" &
    
    # 等待下载完成
    wait
    
    log_info "离线包下载完成"
    ls -lh "${offline_dir}"/*/
}

build_images_local() {
    log_phase "构建镜像 (本地离线模式)..."
    
    cd "${PROJECT_DIR}"
    
    # 构建 FE
    log_info "构建 Doris FE..."
    docker build \
        --build-arg DORIS_VERSION=${DORIS_VERSION} \
        --build-arg OFFLINE_PATH=/offline-packages \
        -f docker/fe/Dockerfile \
        -t "doris-fe:${DORIS_VERSION}" \
        --no-cache \
        .
    
    # 构建 BE
    log_info "构建 Doris BE..."
    docker build \
        --build-arg DORIS_VERSION=${DORIS_VERSION} \
        --build-arg OFFLINE_PATH=/offline-packages \
        -f docker/be/Dockerfile \
        -t "doris-be:${DORIS_VERSION}" \
        --no-cache \
        .
    
    log_info "镜像构建完成"
    docker images | grep -E "doris-"
}

tag_and_push_to_nexus() {
    log_phase "推送到本地 Nexus..."
    
    # 登录 Nexus
    log_info "登录 Nexus..."
    echo "${NEXUS_PASS}" | docker login "${NEXUS_URL}" -u "${NEXUS_USER}" --password-stdin
    
    # Tag 镜像
    log_info "Tag 镜像..."
    docker tag "doris-fe:${DORIS_VERSION}" "${NEXUS_URL}/doris/fe:${DORIS_VERSION}-secure"
    docker tag "doris-be:${DORIS_VERSION}" "${NEXUS_URL}/doris/be:${DORIS_VERSION}-secure"
    
    # 推送镜像
    log_info "推送 FE..."
    docker push "${NEXUS_URL}/doris/fe:${DORIS_VERSION}-secure"
    
    log_info "推送 BE..."
    docker push "${NEXUS_URL}/doris/be:${DORIS_VERSION}-secure"
    
    log_info "推送到 Nexus 完成"
}

verify_in_nexus() {
    log_phase "验证 Nexus 中的镜像..."
    
    # 检查仓库
    log_info "检查 Docker 仓库..."
    curl -sf -u "${NEXUS_USER}:${NEXUS_PASS}" \
        "${NEXUS_UI_URL}/service/rest/v1/repositories" | jq -r '.[] | select(.name=="doris-docker") | .name'
    
    # 列出镜像
    log_info "列出镜像..."
    curl -sf -u "${NEXUS_USER}:${NEXUS_PASS}" \
        "${NEXUS_UI_URL}/v2/doris/fe/tags/list" | jq .
    
    curl -sf -u "${NEXUS_USER}:${NEXUS_PASS}" \
        "${NEXUS_UI_URL}/v2/doris/be/tags/list" | jq .
    
    log_info "Nexus 验证完成"
}

pull_from_nexus() {
    log_phase "从 Nexus 拉取镜像验证..."
    
    # 清理本地镜像
    log_info "清理本地镜像..."
    docker rmi "${NEXUS_URL}/doris/fe:${DORIS_VERSION}-secure" 2>/dev/null || true
    docker rmi "${NEXUS_URL}/doris/be:${DORIS_VERSION}-secure" 2>/dev/null || true
    
    # 拉取镜像
    log_info "从 Nexus 拉取 FE..."
    docker pull "${NEXUS_URL}/doris/fe:${DORIS_VERSION}-secure"
    
    log_info "从 Nexus 拉取 BE..."
    docker pull "${NEXUS_URL}/doris/be:${DORIS_VERSION}-secure"
    
    log_info "拉取验证完成"
    docker images | grep "${NEXUS_URL}/doris"
}

scan_images() {
    log_phase "安全扫描..."
    
    if ! command -v trivy &> /dev/null;
    then
        log_warn "Trivy 未安装，跳过扫描"
        return 0
    fi
    
    log_info "扫描 FE 镜像..."
    trivy image --severity HIGH,CRITICAL "doris-fe:${DORIS_VERSION}" || true
    
    log_info "扫描 BE 镜像..."
    trivy image --severity HIGH,CRITICAL "doris-be:${DORIS_VERSION}" || true
    
    log_info "扫描完成"
}

cleanup() {
    log_phase "清理资源..."
    
    # 停止 Nexus
    cd "${PROJECT_DIR}"
    docker-compose down
    
    # 清理镜像
    docker rmi "doris-fe:${DORIS_VERSION}" 2>/dev/null || true
    docker rmi "doris-be:${DORIS_VERSION}" 2>/dev/null || true
    docker rmi "${NEXUS_URL}/doris/fe:${DORIS_VERSION}-secure" 2>/dev/null || true
    docker rmi "${NEXUS_URL}/doris/be:${DORIS_VERSION}-secure" 2>/dev/null || true
    
    log_info "清理完成"
}

show_summary() {
    echo ""
    echo "=========================================="
    echo " 验证完成 - 汇总"
    echo "=========================================="
    echo ""
    echo "Nexus 地址:"
    echo "  Web UI: ${NEXUS_UI_URL}"
    echo "  Docker: ${NEXUS_URL}"
    echo "  用户名: ${NEXUS_USER}"
    echo "  密码: ${NEXUS_PASS}"
    echo ""
    echo "镜像:"
    echo "  ${NEXUS_URL}/doris/fe:${DORIS_VERSION}-secure"
    echo "  ${NEXUS_URL}/doris/be:${DORIS_VERSION}-secure"
    echo ""
    echo "本地测试:"
    echo "  docker run -it ${NEXUS_URL}/doris/fe:${DORIS_VERSION}-secure /bin/bash"
    echo "  docker run -it ${NEXUS_URL}/doris/be:${DORIS_VERSION}-secure /bin/bash"
    echo ""
}

# ==========================================
# Main
# ==========================================

main() {
    local command="${1:-all}"
    
    echo "=========================================="
    echo " Doris 安全镜像 - 本地验证"
    echo "=========================================="
    echo ""
    
    check_docker
    echo ""
    
    case "$command" in
        nexus)
            start_nexus
            configure_nexus
            ;;
        prepare)
            prepare_offline_packages
            ;;
        build)
            build_images_local
            ;;
        push)
            tag_and_push_to_nexus
            ;;
        verify)
            verify_in_nexus
            ;;
        pull)
            pull_from_nexus
            ;;
        scan)
            scan_images
            ;;
        clean)
            cleanup
            ;;
        all)
            # 完整流程
            start_nexus
            echo ""
            
            configure_nexus
            echo ""
            
            prepare_offline_packages
            echo ""
            
            build_images_local
            echo ""
            
            tag_and_push_to_nexus
            echo ""
            
            verify_in_nexus
            echo ""
            
            pull_from_nexus
            echo ""
            
            show_summary
            ;;
        *)
            echo "用法: $0 {all|nexus|prepare|build|push|verify|pull|scan|clean}"
            echo ""
            echo "命令:"
            echo "  all      - 完整验证流程"
            echo "  nexus    - 启动并配置 Nexus"
            echo "  prepare  - 下载离线包"
            echo "  build    - 构建镜像"
            echo "  push     - 推送到 Nexus"
            echo "  verify   - 验证 Nexus"
            echo "  pull     - 从 Nexus 拉取"
            echo "  scan     - 安全扫描"
            echo "  clean    - 清理资源"
            exit 1
            ;;
    esac
}

main "$@"
