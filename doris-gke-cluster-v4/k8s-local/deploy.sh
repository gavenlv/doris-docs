#!/bin/bash
# =============================================================================
# Doris 本地 Kubernetes 部署脚本 - 简化版
# =============================================================================
# 作用: 一键部署本地 Doris 集群（传统架构）
# 适用: Docker Desktop Kubernetes、Minikube
#
# 部署模式: 传统架构 (FE + BE)
#   - 不需要 FDB Operator（使用单节点 FDB）
#   - 不需要 Doris Operator（使用传统 Deployment）
#
# 部署组件:
#   1. FoundationDB 单节点 (foundationdb) - 用于测试
#   2. Doris FE (doris) - SQL 查询协调
#   3. Doris BE (doris) - 数据存储和计算
#
# 前置条件:
#   - Docker Desktop 已启用 Kubernetes
#   - kubectl 已配置
#   - 资源: 4核CPU + 8GB内存
#
# 使用方法:
#   ./deploy.sh
#
# 部署顺序:
#   1. 检查环境
#   2. 部署 FDB CRD
#   3. 部署 FDB 单节点
#   4. 部署 Doris (FE + BE)
#   5. 等待就绪
#   6. 验证
# =============================================================================

set -e

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# 配置
# =============================================================================

# 镜像配置
DORIS_FE_IMAGE="${DORIS_FE_IMAGE:-apache/doris:fe-3.1.4}"
DORIS_BE_IMAGE="${DORIS_BE_IMAGE:-apache/doris:be-3.1.4}"
FDB_IMAGE="${FDB_IMAGE:-foundationdb/foundationdb:7.1.37}"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查环境
check_environment() {
    log_info "检查部署环境..."

    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl 未安装或不在 PATH 中"
        exit 1
    fi

    if ! kubectl cluster-info &> /dev/null; then
        log_error "kubectl 未配置或无法连接到 Kubernetes 集群"
        exit 1
    fi

    local context=$(kubectl config current-context 2>/dev/null || echo "unknown")
    log_info "当前 Kubernetes Context: ${context}"

    local cpu=$(kubectl get nodes -o jsonpath='{.items[0].status.capacity.cpu}' 2>/dev/null || echo "unknown")
    local memory=$(kubectl get nodes -o jsonpath='{.items[0].status.capacity.memory}' 2>/dev/null || echo "unknown")
    log_info "集群 CPU: ${cpu}, Memory: ${memory}"

    log_info "环境检查完成"
}

# =============================================================================
# 1. 部署 FDB CRD
# =============================================================================
deploy_fdb_crd() {
    log_info "[1/5] 部署 FoundationDB CRD..."

    kubectl apply -f "${SCRIPT_DIR}/fdb-crd.yaml"

    log_info "FDB CRD 部署完成"
}

# =============================================================================
# 2. 部署 FDB 单节点
# =============================================================================
deploy_fdb_single() {
    log_info "[2/5] 部署 FoundationDB 单节点..."

    kubectl apply -f "${SCRIPT_DIR}/fdb-single.yaml"

    log_info "等待 FDB 单节点就绪..."
    kubectl wait --for=condition=Ready pods -n foundationdb \
        -l app=fdb-single --timeout=120s || {
        log_warn "FDB 单节点启动超时，查看状态..."
        kubectl get pods -n foundationdb
        kubectl logs -n foundationdb fdb-single --tail=20 || true
    }

    log_info "FDB 单节点部署完成"
}

# =============================================================================
# 3. 部署 Doris (FE + BE)
# =============================================================================
deploy_doris() {
    log_info "[3/5] 部署 Doris (FE + BE)..."

    kubectl apply -f "${SCRIPT_DIR}/00-namespace.yaml"
    kubectl apply -f "${SCRIPT_DIR}/doris-traditional.yaml"

    log_info "等待 Doris FE 就绪..."
    kubectl wait --for=condition=Ready pods -n doris \
        -l app=doris,component=fe --timeout=180s || {
        log_warn "Doris FE 启动超时，查看状态..."
        kubectl get pods -n doris
        kubectl logs -n doris -l app=doris,component=fe --tail=20 || true
    }

    log_info "等待 Doris BE 就绪..."
    kubectl wait --for=condition=Ready pods -n doris \
        -l app=doris,component=be --timeout=180s || {
        log_warn "Doris BE 启动超时，查看状态..."
        kubectl get pods -n doris
        kubectl logs -n doris -l app=doris,component=be --tail=20 || true
    }

    log_info "Doris 部署完成"
}

# =============================================================================
# 4. 验证集群
# =============================================================================
verify_cluster() {
    log_info "[4/5] 验证集群状态..."

    echo ""
    log_info "=== 集群资源状态 ==="

    echo ""
    log_info "FoundationDB Pods:"
    kubectl get pods -n foundationdb

    echo ""
    log_info "Doris Pods:"
    kubectl get pods -n doris

    echo ""
    log_info "Doris Services:"
    kubectl get svc -n doris
}

# =============================================================================
# 5. 显示访问信息
# =============================================================================
show_access_info() {
    log_info "[5/5] 显示访问信息..."

    # 获取节点 IP
    local node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "localhost")

    # 获取 FE NodePort
    local fe_query_port=$(kubectl get svc -n doris doris-fe-service -o jsonpath='{.spec.ports[?(@.name=="fe-query")].nodePort}' 2>/dev/null || echo "32036")
    local fe_http_port=$(kubectl get svc -n doris doris-fe-service -o jsonpath='{.spec.ports[?(@.name=="fe-http")].nodePort}' 2>/dev/null || echo "31993")

    echo ""
    log_info "=========================================="
    log_info "     Doris 集群部署完成！"
    log_info "     (传统架构: FE + BE)"
    log_info "=========================================="
    echo ""
    log_info "访问信息:"
    echo "  - FE MySQL:  ${node_ip}:${fe_query_port}"
    echo "  - FE HTTP:   http://${node_ip}:${fe_http_port}"
    echo ""
    log_info "连接命令:"
    echo "  mysql -h ${node_ip} -P ${fe_query_port} -u root"
    echo ""
    log_info "验证 SQL:"
    echo "  SHOW FRONTENDS;"
    echo "  SHOW BACKENDS;"
    echo "  SHOW PROC '/frontends';"
    echo "  SHOW PROC '/backends';"
    echo ""
}

# =============================================================================
# 主函数
# =============================================================================
main() {
    echo ""
    log_info "=========================================="
    log_info "  Doris 本地 Kubernetes 部署脚本"
    log_info "  (传统架构: FE + BE)"
    log_info "=========================================="
    echo ""

    # 检查环境
    check_environment

    # 部署
    deploy_fdb_crd
    deploy_fdb_single
    deploy_doris
    verify_cluster
    show_access_info

    echo ""
    log_info "部署成功！"
}

# 执行
main "$@"