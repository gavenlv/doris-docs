#!/bin/bash

# ==========================================
# Doris 安全镜像 - 上传到 Nexus 脚本
# ==========================================
# Purpose: 将离线包上传到公司 Nexus
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

# Nexus 配置
NEXUS_URL="${NEXUS_URL:-nexus.company.com:8082}"
NEXUS_USER="${NEXUS_USER:-admin}"
NEXUS_PASS="${NEXUS_PASS:-}"
NEXUS_REPO_DOCKER="${NEXUS_REPO_DOCKER:-docker-hosted}"
NEXUS_REPO_RAW="${NEXUS_REPO_RAW:-doris-packages}"

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
    if [ -z "$NEXUS_PASS" ]; then
        log_error "请设置 NEXUS_PASS 环境变量"
        log_info "export NEXUS_PASS=your-password"
        exit 1
    fi
    
    if ! command -v curl &> /dev/null; then
        log_error "curl 未安装"
        exit 1
    fi
    
    log_info "检查完成"
}

upload_raw_package() {
    local file="$1"
    local name="$2"
    local version="$3"
    
    log_info "上传: ${file} -> ${NEXUS_REPO_RAW}/${name}/${version}/"
    
    curl -u "${NEXUS_USER}:${NEXUS_PASS}" \
        -X PUT "${NEXUS_URL}/repository/${NEXUS_REPO_RAW}/${name}/${version}/$(basename ${file})" \
        -T "${file}"
    
    log_info "上传完成: ${name}/${version}/$(basename ${file})"
}

upload_doris_packages() {
    log_info "上传 Doris 包..."
    
    # FE
    if [ -f "${OFFLINE_DIR}/doris-fe/apache-doris-fe-${DORIS_VERSION}-bin.tar.gz" ]; then
        upload_raw_package \
            "${OFFLINE_DIR}/doris-fe/apache-doris-fe-${DORIS_VERSION}-bin.tar.gz" \
            "doris-fe" \
            "${DORIS_VERSION}"
    fi
    
    # BE
    if [ -f "${OFFLINE_DIR}/doris-be/apache-doris-be-${DORIS_VERSION}-bin-x86_64.tar.gz" ]; then
        upload_raw_package \
            "${OFFLINE_DIR}/doris-be/apache-doris-be-${DORIS_VERSION}-bin-x86_64.tar.gz" \
            "doris-be" \
            "${DORIS_VERSION}"
    fi
}

upload_fdb_packages() {
    log_info "上传 FoundationDB 包..."
    
    # FDB Clients
    if [ -f "${OFFLINE_DIR}/foundationdb/foundationdb-clients_${FDB_VERSION}-1_amd64.deb" ]; then
        upload_raw_package \
            "${OFFLINE_DIR}/foundationdb/foundationdb-clients_${FDB_VERSION}-1_amd64.deb" \
            "foundationdb-clients" \
            "${FDB_VERSION}"
    fi
    
    # FDB Server
    if [ -f "${OFFLINE_DIR}/foundationdb/foundationdb-server_${FDB_VERSION}-1_amd64.deb" ]; then
        upload_raw_package \
            "${OFFLINE_DIR}/foundationdb/foundationdb-server_${FDB_VERSION}-1_amd64.deb" \
            "foundationdb-server" \
            "${FDB_VERSION}"
    fi
}

show_nexus_config() {
    echo ""
    echo "=========================================="
    echo " Nexus 配置信息"
    echo "=========================================="
    echo ""
    echo "Docker Repository: ${NEXUS_URL}/${NEXUS_REPO_DOCKER}"
    echo "Raw Repository:    ${NEXUS_URL}/repository/${NEXUS_REPO_RAW}/"
    echo ""
    echo "包下载路径:"
    echo "  FE:  ${NEXUS_URL}/repository/${NEXUS_REPO_RAW}/doris-fe/${DORIS_VERSION}/"
    echo "  BE:  ${NEXUS_URL}/repository/${NEXUS_REPO_RAW}/doris-be/${DORIS_VERSION}/"
    echo "  FDB: ${NEXUS_URL}/repository/${NEXUS_REPO_RAW}/foundationdb-*/${FDB_VERSION}/"
    echo ""
}

# ==========================================
# Main
# ==========================================

main() {
    echo "=========================================="
    echo " 上传离线包到 Nexus"
    echo "=========================================="
    echo ""
    
    check_prerequisites
    echo ""
    
    upload_doris_packages
    echo ""
    
    upload_fdb_packages
    echo ""
    
    show_nexus_config
    
    log_info "上传完成!"
    log_info "下一步: 修改 configs/build-config.yaml 中的下载路径"
}

main "$@"
