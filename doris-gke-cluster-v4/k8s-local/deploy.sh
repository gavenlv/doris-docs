#!/bin/bash
# =============================================================================
# Doris Local Kubernetes 部署脚本 - 存算分离架构
# =============================================================================
# 作用: 一键部署本地 Doris 集群 (存算分离模式)
# 适用: Docker Desktop Kubernetes、Minikube
#
# 部署模式: 存算分离 (Storage-Compute Separation)
#   - 与 GKE 生产架构保持一致
#   - 仅存储后端不同: GCS → MinIO
#
# 部署组件:
#   1. Doris Operator (doris-operator-system)
#   2. FoundationDB Operator (foundationdb)
#   3. FoundationDB 集群 (foundationdb) - MetaService 元数据存储
#   4. MinIO (foundationdb) - S3 兼容对象存储
#   5. DorisDisaggregatedCluster (doris)
#      - FE (1 副本)
#      - BECN (1 副本)
#      - MetaService (1 副本)
#
# 前置条件:
#   - Docker Desktop 已启用 Kubernetes
#   - kubectl 已配置
#   - 资源: 8核CPU + 16GB内存
#
# 使用方法:
#   ./deploy.sh
#
# 部署顺序:
#   1. 检查环境
#   2. 部署 Doris Operator
#   3. 部署 FoundationDB Operator
#   4. 部署 FoundationDB 集群
#   5. 部署 MinIO
#   6. 部署 DorisDisaggregatedCluster
#   7. 等待集群就绪
#   8. 验证
# =============================================================================

set -e

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# 配置
# =============================================================================

# 镜像仓库配置 (默认本地 Nexus)
NEXUS_REGISTRY="${NEXUS_REGISTRY:-localhost:5000/doris}"
NEXUS_PASSWORD="${NEXUS_PASSWORD:-admin123}"
NEXUS_USERNAME="${NEXUS_USERNAME:-admin}"

# Doris 版本
DORIS_VERSION="${DORIS_VERSION:-4.0.4}"

# Operator 版本
OPERATOR_VERSION="${OPERATOR_VERSION:-1.4.0}"

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
# 1. 部署 Doris Operator
# =============================================================================
deploy_doris_operator() {
    log_info "[1/7] 部署 Doris Operator (版本 ${OPERATOR_VERSION})..."

    # 部署 Operator (CRD + Deployment)
    kubectl apply -f "${SCRIPT_DIR}/operator.yaml"

    log_info "等待 Doris Operator 就绪..."
    kubectl wait --for=condition=Ready pods -n doris-operator-system \
        -l app.kubernetes.io/name=doris-operator --timeout=180s || {
        log_error "Doris Operator 启动超时"
        kubectl get pods -n doris-operator-system
        exit 1
    }

    log_info "Doris Operator 部署完成"
}

# =============================================================================
# 1.5. 创建 imagePullSecrets (Nexus 认证)
# =============================================================================
create_image_pull_secret() {
    log_info "[1.5/7] 创建 imagePullSecret..."

    # 创建 Kubernetes Secret 用于镜像拉取认证
    kubectl create secret docker-registry doris-registry \
        --namespace=doris \
        --docker-server="${NEXUS_REGISTRY}" \
        --docker-username="${NEXUS_USERNAME}" \
        --docker-password="${NEXUS_PASSWORD}" \
        --dry-run=client -o yaml | kubectl apply -f -

    log_info "imagePullSecret 创建完成"
}

# =============================================================================
# 2. 部署 FoundationDB Operator
# =============================================================================
deploy_fdb_operator() {
    log_info "[2/7] 部署 FoundationDB Operator..."

    kubectl apply -f "${SCRIPT_DIR}/fdb-operator.yaml"

    log_info "等待 FDB Operator 就绪..."
    kubectl wait --for=condition=Ready pods -n foundationdb \
        -l app.kubernetes.io/name=foundationdb --timeout=180s || {
        log_error "FDB Operator 启动超时"
        kubectl get pods -n foundationdb
        exit 1
    }

    log_info "FoundationDB Operator 部署完成"
}

# =============================================================================
# 3. 部署 FoundationDB 集群
# =============================================================================
deploy_fdb_cluster() {
    log_info "[3/7] 部署 FoundationDB 集群..."

    # 创建 foundationdb 命名空间 (如果不存在)
    kubectl create namespace foundationdb --dry-run=client -o yaml | kubectl apply -f -

    # 部署 FDB Cluster
    kubectl apply -f "${SCRIPT_DIR}/fdbcluster.yaml"

    log_info "等待 FoundationDB 集群就绪..."
    # FDB 集群需要较长时间初始化
    kubectl wait --for=condition=Ready pods -n foundationdb \
        -l app.kubernetes.io/name=foundationdb --timeout=600s || {
        log_warn "FDB 集群启动超时，查看状态..."
        kubectl get pods -n foundationdb
        kubectl logs -n foundationdb -l app.kubernetes.io/name=foundationdb --tail=50 || true
    }

    # 等待 FDB 集群完全可用
    log_info "等待 FDB 集群数据同步..."
    sleep 10

    # 检查 FDB 集群状态
    local fdb_status=$(kubectl get fdbcluster -n foundationdb fdb-cluster \
        -o jsonpath='{.status.generation}' 2>/dev/null || echo "0")
    log_info "FDB 集群状态: generation=${fdb_status}"

    log_info "FoundationDB 集群部署完成"
}

# =============================================================================
# 4. 部署 MinIO
# =============================================================================
deploy_minio() {
    log_info "[4/7] 部署 MinIO..."

    # 创建 foundationdb 命名空间 (如果不存在)
    kubectl create namespace foundationdb --dry-run=client -o yaml | kubectl apply -f -

    kubectl apply -f "${SCRIPT_DIR}/minio-statefulset.yaml"

    log_info "等待 MinIO 就绪..."
    kubectl wait --for=condition=Ready pods -n foundationdb \
        -l app.kubernetes.io/name=minio --timeout=300s || {
        log_warn "MinIO 启动超时，查看状态..."
        kubectl get pods -n foundationdb
        kubectl logs -n foundationdb minio-0 --tail=50 || true
    }

    # 等待 MinIO 完全启动
    sleep 5

    log_info "MinIO 部署完成"
}

# =============================================================================
# 5. 部署 DorisDisaggregatedCluster
# =============================================================================
deploy_doris_cluster() {
    log_info "[5/7] 部署 DorisDisaggregatedCluster..."

    # 部署命名空间和 RBAC
    kubectl apply -f "${SCRIPT_DIR}/00-namespace.yaml"

    # 部署 Secret (MinIO 凭证)
    kubectl apply -f "${SCRIPT_DIR}/secret.yaml"

    # 部署 ConfigMap (FE/BE 配置)
    kubectl apply -f "${SCRIPT_DIR}/configmap.yaml"

    # 部署 DorisDisaggregatedCluster (存算分离)
    # 替换镜像地址占位符: ${NEXUS_REGISTRY} -> actual registry
    sed -e "s|\${NEXUS_REGISTRY}|${NEXUS_REGISTRY}/|g" \
        "${SCRIPT_DIR}/doris-disaggregated-cluster.yaml" | kubectl apply -f -

    log_info "等待 DorisDisaggregatedCluster 部署..."
    log_info "(这可能需要 10-20 分钟，请耐心等待)"

    # 等待 FE 就绪
    log_info "等待 FE 启动..."
    kubectl wait --for=condition=Ready pods -n doris \
        -l app.kubernetes.io/component=fe --timeout=600s || {
        log_warn "FE 启动超时，查看状态..."
        kubectl get pods -n doris
        kubectl logs -n doris -l app.kubernetes.io/component=fe --tail=100 || true
    }

    # 等待 BECN 就绪
    log_info "等待 BECN 启动..."
    kubectl wait --for=condition=Ready pods -n doris \
        -l app.kubernetes.io/component=becn --timeout=600s || {
        log_warn "BECN 启动超时，查看状态..."
        kubectl get pods -n doris
        kubectl logs -n doris -l app.kubernetes.io/component=becn --tail=100 || true
    }

    # 等待 MetaService 就绪
    log_info "等待 MetaService 启动..."
    kubectl wait --for=condition=Ready pods -n doris \
        -l app.kubernetes.io/component=meta-service --timeout=300s || {
        log_warn "MetaService 启动超时，查看状态..."
        kubectl get pods -n doris
        kubectl logs -n doris -l app.kubernetes.io/component=meta-service --tail=100 || true
    }

    log_info "DorisDisaggregatedCluster 部署完成"
}

# =============================================================================
# 6. 验证集群
# =============================================================================
verify_cluster() {
    log_info "[6/7] 验证集群状态..."

    echo ""
    log_info "=== 集群资源状态 ==="

    echo ""
    log_info "FoundationDB Pods:"
    kubectl get pods -n foundationdb

    echo ""
    log_info "Doris Pods:"
    kubectl get pods -n doris

    echo ""
    log_info "Services:"
    kubectl get svc -n doris
    kubectl get svc -n foundationdb

    echo ""
    log_info "ConfigMaps:"
    kubectl get configmap -n doris

    echo ""
    log_info "Secrets:"
    kubectl get secret -n doris

    echo ""
    log_info "=== 集群验证 ==="

    # 获取节点 IP
    local node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "localhost")

    echo ""
    log_info "=========================================="
    log_info "     Doris 集群部署完成！"
    log_info "     (存算分离架构)"
    log_info "=========================================="
    echo ""
    log_info "访问信息:"
    echo "  - FE MySQL:  ${node_ip}:30632"
    echo "  - FE HTTP:   http://${node_ip}:30389"
    echo "  - MinIO:     http://${node_ip}:30090 (Console)"
    echo "              http://${node_ip}:30000 (API)"
    echo ""
    log_info "连接命令:"
    echo "  mysql -h ${node_ip} -P 30632 -u root"
    echo ""
    log_info "验证 SQL:"
    echo "  SHOW FRONTENDS;"
    echo "  SHOW BACKENDS;"
    echo "  SHOW PROC '/frontends';"
    echo "  SHOW PROC '/backends';"
    echo ""
    log_info "MinIO Bucket: doris-data"
    echo "MinIO 凭证: minioadmin / minioadmin"
    echo ""
}

# =============================================================================
# 主函数
# =============================================================================
main() {
    echo ""
    log_info "=========================================="
    log_info "  Doris Local Kubernetes 部署脚本"
    log_info "  (存算分离架构 - 与 GKE 一致)"
    log_info "=========================================="
    echo ""

    # 检查环境
    check_environment

    # 部署
    deploy_doris_operator
    create_image_pull_secret
    deploy_fdb_operator
    deploy_fdb_cluster
    deploy_minio
    deploy_doris_cluster
    verify_cluster

    echo ""
    log_info "部署成功！"
}

# 执行
main "$@"
