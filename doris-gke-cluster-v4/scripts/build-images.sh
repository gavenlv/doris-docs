#!/bin/bash

# ==========================================
# Doris 2.1.7 Security Image Build Script
# Supports offline build mode
# ==========================================
# Version: 2.1.7

set -e

# ==========================================
# Configuration
# ==========================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DOCKER_DIR="${PROJECT_DIR}/docker"
CONFIG_DIR="${PROJECT_DIR}/configs"
OFFLINE_DIR="${PROJECT_DIR}/offline-packages"

# Image configuration
NEXUS_URL="${NEXUS_URL:-nexus.company.com:8082}"
NEXUS_REPO="${NEXUS_REPO:-doris}"
DORIS_VERSION="${DORIS_VERSION:-2.1.7}"
FDB_VERSION="${FDB_VERSION:-7.1.37}"
OPERATOR_VERSION="${OPERATOR_VERSION:-v1.1.0}"

# Build mode
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
    log_info "Checking build environment..."

    if ! command -v docker &> /dev/null; then
        log_error "Docker not installed"
        exit 1
    fi

    if ! docker info &> /dev/null; then
        log_error "Docker not running"
        exit 1
    fi

    # Check BuildKit
    if ! docker version | grep -q "BuildKit"; then
        log_warn "BuildKit recommended for --secret support"
        log_info "Enable: export DOCKER_BUILDKIT=1"
    fi

    log_info "Environment check passed"
}

prepare_offline_context() {
    if [ "$BUILD_MODE" = "local" ]; then
        if [ -d "${OFFLINE_DIR}" ]; then
            log_info "Using local offline packages: ${OFFLINE_DIR}"
            return 0
        else
            log_error "Offline package directory not found: ${OFFLINE_DIR}"
            log_info "Please run: ./scripts/prepare-offline.sh download"
            exit 1
        fi
    fi
}

build_fe() {
    log_info "Building Doris FE image..."

    local image="${NEXUS_URL}/${NEXUS_REPO}/fe:${DORIS_VERSION}-secure"

    if [ "$BUILD_MODE" = "local" ]; then
        # Build with offline packages
        docker build \
            --build-arg DORIS_VERSION=${DORIS_VERSION} \
            --build-arg OFFLINE_PATH=/offline-packages \
            -f "${DOCKER_DIR}/fe/Dockerfile" \
            -t "${image}" \
            --no-cache \
            .
    else
        # Nexus or GCS mode
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

    log_info "FE image built: ${image}"
}

build_be() {
    log_info "Building Doris BE image..."

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

    log_info "BE image built: ${image}"
}

build_fdb() {
    log_info "Building FoundationDB image..."

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

    log_info "FoundationDB image built: ${image}"
}

build_operator() {
    log_info "Building Doris Operator image..."
    log_warn "Operator requires Go toolchain, online build only"

    local image="${NEXUS_URL}/doris-operator:${OPERATOR_VERSION}-secure"

    docker build \
        --build-arg OPERATOR_VERSION=${OPERATOR_VERSION} \
        -f "${DOCKER_DIR}/operator/Dockerfile" \
        -t "${image}" \
        --no-cache \
        .

    log_info "Operator image built: ${image}"
}

build_all() {
    log_info "Building all images... (mode: ${BUILD_MODE})"
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

    log_info "All images built!"
    echo ""
    docker images | grep -E "(doris|foundationdb)" | grep "${NEXUS_URL}"
}

# ==========================================
# Main
# ==========================================

main() {
    local target="${1:-all}"

    echo "=========================================="
    echo " Doris 2.1.7 Security Image Build"
    echo "  Mode: ${BUILD_MODE}"
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
            echo "Usage: $0 {all|fe|be|fdb|operator}"
            echo ""
            echo "Environment variables:"
            echo "  BUILD_MODE=local|nexus   Build mode (default: local)"
            echo "  NEXUS_URL               Nexus address"
            echo "  NEXUS_USER              Nexus username"
            echo "  NEXUS_PASS              Nexus password"
            echo "  DORIS_VERSION           Doris version (default: 2.1.7)"
            echo ""
            echo "Examples:"
            echo "  # Local offline build"
            echo "  ./scripts/build-images.sh all"
            echo ""
            echo "  # Nexus build"
            echo "  BUILD_MODE=nexus NEXUS_PASS=xxx ./scripts/build-images.sh all"
            exit 1
            ;;
    esac
}

main "$@"
