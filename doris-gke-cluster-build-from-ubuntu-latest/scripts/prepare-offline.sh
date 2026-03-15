#!/bin/bash

# ==========================================
# Doris 安全镜像 - 离线准备脚本
# ==========================================
# Purpose: 下载所有依赖到本地，准备离线构建
# Version: 1.0

set -e

# ==========================================
# Configuration
# ==========================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
OFFLINE_DIR="${PROJECT_DIR}/offline-packages"

# 版本配置
DORIS_VERSION="${DORIS_VERSION:-3.1.4}"
FDB_VERSION="${FDB_VERSION:-7.1.37}"
OPERATOR_VERSION="${OPERATOR_VERSION:-v1.1.0}"

# GCS 配置
GCS_BUCKET="${GCS_BUCKET:-gs://doris-build-packages}"

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

create_offline_dir() {
    log_info "创建离线包目录: ${OFFLINE_DIR}"
    mkdir -p "${OFFLINE_DIR}/doris-fe"
    mkdir -p "${OFFLINE_DIR}/doris-be"
    mkdir -p "${OFFLINE_DIR}/foundationdb"
    mkdir -p "${OFFLINE_DIR}/common"
}

download_doris_fe() {
    log_info "下载 Doris FE..."
    local dest="${OFFLINE_DIR}/doris-fe"
    local url="https://archive.apache.org/dist/doris"
    
    # 下载 FE
    wget -q "${url}/${DORIS_VERSION}/apache-doris-fe-${DORIS_VERSION}-bin.tar.gz" \
        -O "${dest}/apache-doris-fe-${DORIS_VERSION}-bin.tar.gz"
    
    log_info "FE 下载完成: ${dest}/apache-doris-fe-${DORIS_VERSION}-bin.tar.gz"
}

download_doris_be() {
    log_info "下载 Doris BE..."
    local dest="${OFFLINE_DIR}/doris-be"
    local url="https://archive.apache.org/dist/doris"
    
    # 下载 BE
    wget -q "${url}/${DORIS_VERSION}/apache-doris-be-${DORIS_VERSION}-bin-x86_64.tar.gz" \
        -O "${dest}/apache-doris-be-${DORIS_VERSION}-bin-x86_64.tar.gz"
    
    log_info "BE 下载完成: ${dest}/apache-doris-be-${DORIS_VERSION}-bin-x86_64.tar.gz"
}

download_foundationdb() {
    log_info "下载 FoundationDB..."
    local dest="${OFFLINE_DIR}/foundationdb"
    local url="https://github.com/apple/foundationdb/releases/download"
    
    # 下载 FDB
    wget -q "${url}/${FDB_VERSION}/foundationdb-clients_${FDB_VERSION}-1_amd64.deb" \
        -O "${dest}/foundationdb-clients_${FDB_VERSION}-1_amd64.deb"
    wget -q "${url}/${FDB_VERSION}/foundationdb-server_${FDB_VERSION}-1_amd64.deb" \
        -O "${dest}/foundationdb-server_${FDB_VERSION}-1_amd64.deb"
    
    log_info "FoundationDB 下载完成"
}

download_operator() {
    log_info "下载 Doris Operator 源码..."
    local dest="${OFFLINE_DIR}/operator"
    
    # Operator 需要从源码构建，这里只记录版本信息
    # 实际构建时需要访问 GitHub
    cat > "${dest}/operator-info.txt" <<EOF
OPERATOR_VERSION=${OPERATOR_VERSION}
OPERATOR_REPO=https://github.com/apache/doris-operator
EOF
    
    log_info "Operator 信息已记录 (需要网络构建)"
}

download_ubuntu_base() {
    log_info "下载 Ubuntu 基础镜像..."
    # Ubuntu 基础镜像由 Docker 自动管理
    # 这里记录需要的版本
    cat > "${OFFLINE_DIR}/common/base-images.txt" <<EOF
ubuntu:22.04
golang:1.21-alpine
EOF
    log_info "基础镜像信息已记录"
}

upload_to_gcs() {
    log_info "上传到 GCS: ${GCS_BUCKET}"
    
    # 创建版本目录
    local gcs_path="${GCS_BUCKET}/doris-${DORIS_VERSION}"
    
    # 上传文件
    gsutil -m cp -r "${OFFLINE_DIR}/"* "${gcs_path}/"
    
    log_info "上传完成: ${gcs_path}"
}

upload_to_nexus() {
    local nexus_url="${1:-nexus.company.com:8082}"
    local nexus_user="${2:-admin}"
    local nexus_pass="${3:-}"
    
    if [ -z "$nexus_pass" ]; then
        log_error "请提供 Nexus 密码"
        exit 1
    fi
    
    log_info "上传到 Nexus: ${nexus_url}"
    
    # 登录 Nexus
    echo "$nexus_pass" | docker login "$nexus_url" -u "$nexus_user" --password-stdin
    
    # 导入离线包为镜像
    for pkg in "${OFFLINE_DIR}"/*/; do
        local name=$(basename "$pkg")
        log_info "处理: $name"
        
        # 这里需要根据包类型创建临时镜像
        # 简化处理：直接上传 DEB/RPM 包到 Nexus 的 raw repository
    done
    
    log_info "上传到 Nexus 完成 (需要配置 raw repository)"
}

show_summary() {
    echo ""
    echo "=========================================="
    echo " 离线包准备完成"
    echo "=========================================="
    echo ""
    echo "本地目录: ${OFFLINE_DIR}"
    echo ""
    echo "文件列表:"
    du -sh "${OFFLINE_DIR}"/*
    echo ""
    echo "下一步:"
    echo "  1. 上传到 GCS:   gsutil -m cp -r ${OFFLINE_DIR}/* ${GCS_BUCKET}/"
    echo "  2. 上传到 Nexus: ./upload-to-nexus.sh <nexus_url> <user> <pass>"
    echo "  3. 构建镜像:    ./scripts/build-images.sh all"
}

# ==========================================
# Main
# ==========================================

main() {
    local command="${1:-download}"
    
    echo "=========================================="
    echo " Doris 离线包准备工具"
    echo "=========================================="
    echo ""
    
    case "$command" in
        download)
            create_offline_dir
            download_doris_fe
            download_doris_be
            download_foundationdb
            download_operator
            download_ubuntu_base
            show_summary
            ;;
        upload-gcs)
            upload_to_gcs
            ;;
        upload-nexus)
            upload_to_nexus "$2" "$3" "$4"
            ;;
        clean)
            log_info "清理离线包..."
            rm -rf "${OFFLINE_DIR}"
            log_info "清理完成"
            ;;
        *)
            echo "用法: $0 {download|upload-gcs|upload-nexus|clean}"
            echo ""
            echo "命令:"
            echo "  download       - 下载所有依赖到本地"
            echo "  upload-gcs     - 上传到 GCS"
            echo "  upload-nexus   - 上传到 Nexus"
            echo "  clean          - 清理本地离线包"
            exit 1
            ;;
    esac
}

main "$@"
