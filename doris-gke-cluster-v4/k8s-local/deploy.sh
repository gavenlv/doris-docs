#!/bin/bash
# =============================================================================
# Doris Local Kubernetes 部署脚本 (存储计算分离架构)
# =============================================================================
# 作用: 一键部署本地 Doris 集群
# 适用: Docker Desktop Kubernetes、Minikube
#
# 部署组件:
#   1. MinIO (S3 兼容对象存储)
#   2. Doris Operator
#   3. DorisCluster (3FE + 3BE)
#
# 前置条件:
#   - Docker Desktop 已启用 Kubernetes
#   - kubectl 已配置
#   - 资源: 4核CPU + 16GB内存 + 100GB磁盘
#
# 使用方法:
#   ./deploy.sh
#
# 部署顺序:
#   1. 部署 MinIO
#   2. 等待 MinIO 就绪
#   3. 部署 Doris 配置
#   4. 部署 Doris Operator
#   5. 部署 DorisCluster
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

# 部署 MinIO
deploy_minio() {
    log_info "部署 MinIO 对象存储..."

    # 创建 minio namespace 和资源
    kubectl apply -f 00-namespace.yaml

    # 等待 namespace 创建
    kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=minio -n minio --timeout=120s 2>/dev/null || {
        log_warn "MinIO 启动中，继续等待..."
        sleep 30
    }

    # 检查 MinIO 状态
    local minio_pods=$(kubectl get pods -n minio -l app.kubernetes.io/name=minio -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
    log_info "MinIO Pod 状态: ${minio_pods}"

    if [ "$minio_pods" != "Running" ]; then
        log_warn "MinIO 可能未就绪，继续部署..."
    fi

    log_info "MinIO 部署完成"
}

# 部署 Doris 配置
deploy_config() {
    log_info "部署 Doris 配置..."

    # 创建 namespace (如果不存在)
    kubectl create namespace doris --dry-run=client -o yaml | kubectl apply -f -

    # 部署配置
    kubectl apply -f configmap.yaml

    log_info "配置部署完成"
}

# 部署 Doris Operator
deploy_operator() {
    log_info "部署 Doris Operator..."

    # 部署 CRD
    log_info "部署 DorisCluster CRD..."
    kubectl apply -f https://raw.githubusercontent.com/apache/doris-operator/25.8.0/config/crd/bases/doris.apache.com_dorisclusters.yaml

    # 部署 Operator
    log_info "部署 Operator..."
    kubectl apply -f https://raw.githubusercontent.com/apache/doris-operator/25.8.0/config/operator/operator.yaml

    # 等待 Operator 就绪
    log_info "等待 Operator 启动..."
    kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=doris-operator -n doris --timeout=180s || {
        log_error "Operator 启动超时"
        kubectl get pods -n doris
        exit 1
    }

    log_info "Doris Operator 部署完成"
}

# 部署 DorisCluster
deploy_doriscluster() {
    log_info "部署 DorisCluster..."

    # 部署 DorisCluster
    kubectl apply -f doriscluster.yaml

    # 等待 FE 就绪
    log_info "等待 FE 启动 (可能需要 5-10 分钟)..."
    kubectl wait --for=condition=Ready pods -l app.kubernetes.io/component=fe -n doris --timeout=600s || {
        log_error "FE 启动超时"
        kubectl get pods -n doris
        kubectl logs -l app.kubernetes.io/component=fe -n doris --tail=100
        exit 1
    }

    # 等待 BE 就绪
    log_info "等待 BE 启动..."
    kubectl wait --for=condition=Ready pods -l app.kubernetes.io/component=be -n doris --timeout=600s || {
        log_error "BE 启动超时"
        kubectl get pods -n doris
        kubectl logs -l app.kubernetes.io/component=be -n doris --tail=100
        exit 1
    }

    log_info "DorisCluster 部署完成"
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
    log_info "MinIO Service:"
    kubectl get svc -n minio

    echo ""
    log_info "=========================================="
    log_info "          访问信息"
    log_info "=========================================="
    echo ""
    log_info "Doris FE (MySQL):"
    echo "   端口转发: kubectl port-forward -n doris svc/doriscluster-local-fe-service 9030:9030"
    echo "   直接访问: mysql -h127.0.0.1 -P9030 -uroot"
    echo ""
    log_info "Doris FE (Web UI):"
    echo "   http://localhost:8030"
    echo ""
    log_info "MinIO Console:"
    echo "   kubectl port-forward -n minio svc/minio 9001:9001"
    echo "   http://localhost:9001"
    echo "   账号: minioadmin"
    echo "   密码: minioadmin"
    echo ""
    log_info "=========================================="
    log_info "          验证集群状态"
    log_info "=========================================="
    echo ""
    echo "   # 端口转发"
    echo "   kubectl port-forward -n doris svc/doriscluster-local-fe-service 9030:9030"
    echo ""
    echo "   # 连接 Doris"
    echo "   mysql -h127.0.0.1 -P9030 -uroot"
    echo ""
    echo "   # 执行验证 SQL"
    echo "   SHOW FRONTENDS;"
    echo "   SHOW BACKENDS;"
    echo "   SHOW PROC '/frontends';"
    echo "   SHOW PROC '/backends';"
    echo ""
}

# 主函数
main() {
    echo ""
    log_info "=========================================="
    log_info "   Doris Local Kubernetes 部署脚本"
    log_info "   (存储计算分离 + MinIO)"
    log_info "=========================================="
    echo ""

    # 检查环境
    check_environment

    # 部署
    deploy_minio
    deploy_config
    deploy_operator
    deploy_doriscluster

    # 显示状态
    show_status
}

# 执行
main "$@"
