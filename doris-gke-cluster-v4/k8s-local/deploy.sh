#!/bin/bash
# =============================================================================
# Doris Local Kubernetes 部署脚本
# =============================================================================
# 作用: 一键部署本地 Doris 集群
# 适用: Docker Desktop Kubernetes、Minikube
#
# 部署组件:
#   1. Doris Operator
#   2. DorisCluster (1FE + 1BE) - 开发环境配置
#   3. HPA (可选) - 自动扩缩容
#
# 前置条件:
#   - Docker Desktop 已启用 Kubernetes
#   - kubectl 已配置
#   - 资源: 4核CPU + 16GB内存
#
# 使用方法:
#   ./deploy.sh
#
# 部署顺序:
#   1. 检查环境
#   2. 部署 Doris Operator
#   3. 创建命名空间和 RBAC
#   4. 部署 DorisCluster
#   5. 部署 HPA (可选)
#   6. 等待集群就绪
# =============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

    # 检查 kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl 未安装或不在 PATH 中"
        exit 1
    fi

    # 检查 kubectl 配置
    if ! kubectl cluster-info &> /dev/null; then
        log_error "kubectl 未配置或无法连接到 Kubernetes 集群"
        exit 1
    fi

    # 检查 Docker Desktop Kubernetes
    local context=$(kubectl config current-context 2>/dev/null || echo "unknown")
    log_info "当前 Kubernetes Context: ${context}"

    # 检查资源
    log_info "检查集群资源..."
    local cpu=$(kubectl get nodes -o jsonpath='{.items[0].status.capacity.cpu}' 2>/dev/null || echo "unknown")
    local memory=$(kubectl get nodes -o jsonpath='{.items[0].status.capacity.memory}' 2>/dev/null || echo "unknown")
    log_info "集群 CPU: ${cpu}, Memory: ${memory}"

    log_info "环境检查完成"
}

# 部署 Doris Operator
deploy_operator() {
    log_info "部署 Doris Operator..."

    # 部署 CRD 和 Operator (使用本地配置)
    log_info "部署 DorisCluster CRD..."
    kubectl apply -f operator.yaml

    # 等待 Operator 就绪
    log_info "等待 Operator 启动..."
    kubectl wait --for=condition=Ready pods -n doris-operator-system -l app.kubernetes.io/name=doris-operator --timeout=180s || {
        log_error "Operator 启动超时"
        kubectl get pods -n doris-operator-system
        exit 1
    }

    log_info "Doris Operator 部署完成"
}

# 部署命名空间和 RBAC
deploy_namespace() {
    log_info "部署命名空间和 RBAC..."

    kubectl apply -f 00-namespace.yaml

    log_info "命名空间部署完成"
}

# 部署 DorisCluster
deploy_doriscluster() {
    log_info "部署 DorisCluster..."

    # 部署 DorisCluster
    kubectl apply -f doriscluster.yaml

    # 等待 FE 就绪
    log_info "等待 FE 启动 (可能需要 3-5 分钟)..."
    kubectl wait --for=condition=Ready pods -n doris -l app.doris.cluster/doriscluster-local --timeout=600s || {
        log_warn "FE 启动超时，查看状态..."
        kubectl get pods -n doris
        kubectl logs -n doris -l app.doris.cluster/doriscluster-local --tail=50 || true
    }

    # 等待 BE 就绪
    log_info "等待 BE 启动..."
    kubectl wait --for=condition=Ready pods -n doris -l app.doris.cluster/doriscluster-local --timeout=600s || {
        log_warn "BE 启动超时，查看状态..."
        kubectl get pods -n doris
    }

    log_info "DorisCluster 部署完成"
}

# 部署 HPA (可选)
deploy_hpa() {
    log_info "部署 HPA 自动扩缩容..."

    # 检查 metrics-server 是否可用
    if kubectl get pods -n kube-system -l k8s-app=metrics-server 2>/dev/null | grep -q Running; then
        kubectl apply -f hpa.yaml
        log_info "HPA 部署完成"
    else
        log_warn "metrics-server 未运行，HPA 可能无法正常工作"
        log_warn "如需 HPA，请先安装 metrics-server:"
        log_warn "  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
    fi
}

# 显示部署状态
show_status() {
    log_info "=========================================="
    log_info "       Doris 集群部署完成！"
    log_info "=========================================="

    echo ""
    log_info "Pod 状态:"
    kubectl get pods -n doris -o wide

    echo ""
    log_info "Service 状态:"
    kubectl get svc -n doris

    echo ""
    log_info "HPA 状态 (如有):"
    kubectl get hpa -n doris 2>/dev/null || echo "  HPA 未部署"

    echo ""
    log_info "=========================================="
    log_info "          访问信息"
    log_info "=========================================="
    echo ""

    # 获取节点 IP
    local node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "localhost")

    log_info "Doris FE (MySQL):"
    echo "   地址: ${node_ip}"
    echo "   端口: 30632 (NodePort)"
    echo "   命令: mysql -h ${node_ip} -P 30632 -u root"
    echo ""
    log_info "Doris FE (Web UI):"
    echo "   地址: http://${node_ip}:30389"
    echo ""
    log_info "=========================================="
    log_info "          验证集群状态"
    log_info "=========================================="
    echo ""
    echo "   # 连接 Doris"
    echo "   docker run --rm mysql:8 bash -c \"mysql -h ${node_ip} -P 30632 -u root -e 'SHOW FRONTENDS'\""
    echo ""
    echo "   # 执行验证 SQL"
    echo "   SHOW FRONTENDS;"
    echo "   SHOW BACKENDS;"
    echo ""
    echo "   # 查看 HPA (如已部署)"
    echo "   kubectl get hpa -n doris"
    echo "   kubectl top pods -n doris"
    echo ""
}

# 主函数
main() {
    echo ""
    log_info "=========================================="
    log_info "   Doris Local Kubernetes 部署脚本"
    log_info "   (开发环境配置)"
    log_info "=========================================="
    echo ""

    # 检查环境
    check_environment

    # 部署
    deploy_operator
    deploy_namespace
    deploy_doriscluster

    # 询问是否部署 HPA
    echo ""
    read -p "是否部署 HPA 自动扩缩容? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        deploy_hpa
    fi

    # 显示状态
    show_status
}

# 执行
main "$@"