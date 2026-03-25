#!/bin/bash
# =============================================================================
# Doris 存算分离架构 卸载脚本
# =============================================================================
# 作用: 清理本地 Doris 集群的所有资源
# 适用: Docker Desktop Kubernetes、Minikube
#
# 卸载内容:
#   - namespace: doris, foundationdb, doris-operator-system
#   - CRD: foundationdbclusters, dorisclusters, dorisdisaggregatedclusters
#   - 所有相关资源
#
# 使用方法:
#   ./undeploy.sh
# =============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# =============================================================================
# 主函数
# =============================================================================
main() {
    echo ""
    log_info "=========================================="
    log_info "  Doris 存算分离架构 卸载脚本"
    log_info "=========================================="
    echo ""

    # 删除 DorisDisaggregatedCluster (CR)
    log_info "删除 DorisDisaggregatedCluster..."
    kubectl delete -n doris dorisdisaggregatedcluster doris-disagg-cluster --ignore-not-found=true 2>/dev/null || true

    # 删除 HPA
    log_info "删除 HPA..."
    kubectl delete -n doris hpa doris-fe-hpa doris-becn-hpa doris-metaservice-hpa --ignore-not-found=true 2>/dev/null || true

    # 删除 namespaces
    log_info "删除 namespaces..."
    kubectl delete namespace doris --ignore-not-found=true 2>/dev/null || true
    kubectl delete namespace foundationdb --ignore-not-found=true 2>/dev/null || true
    kubectl delete namespace doris-operator-system --ignore-not-found=true 2>/dev/null || true

    # 删除 CRDs
    log_info "删除 CRDs..."
    kubectl delete crd foundationdbclusters.apps.foundationdb.org --ignore-not-found=true 2>/dev/null || true
    kubectl delete crd foundationdbbackups.apps.foundationdb.org --ignore-not-found=true 2>/dev/null || true
    kubectl delete crd foundationdbrestores.apps.foundationdb.org --ignore-not-found=true 2>/dev/null || true
    kubectl delete crd dorisclusters.doris.apache.com --ignore-not-found=true 2>/dev/null || true
    kubectl delete crd dorisdisaggregatedclusters.doris.apache.com --ignore-not-found=true 2>/dev/null || true

    # 确认删除
    echo ""
    log_info "=========================================="
    log_info "     卸载完成！"
    log_info "=========================================="
    echo ""
    log_info "验证命令:"
    echo "  kubectl get namespaces"
    echo "  kubectl get crd"
    echo ""
}

# 执行
main "$@"