#!/bin/bash
# =============================================================================
# Doris 存算分离架构 部署脚本
# =============================================================================
# 作用: 一键部署本地 Doris 集群 (存算分离模式)
# 适用: Docker Desktop Kubernetes、Minikube
#
# 部署模式: 存算分离 (Storage-Compute Separation)
#   - FE: SQL 查询协调
#   - BECN: 计算节点 (不存储数据)
#   - MetaService: 元数据服务
#   - MinIO: S3 兼容对象存储
#   - FoundationDB: 元数据存储
#
# 自动扩容: HPA 支持
#
# 前置条件:
#   - Docker Desktop 已启用 Kubernetes
#   - kubectl 已配置
#   - metrics-server 已安装
#   - 资源: 16核CPU + 32GB内存
#   - 本地镜像已加载:
#     - fdb-kubernetes-operator:1.12.0
#     - foundationdb/foundationdb:7.1.37
#     - apache/doris:fe-3.1.4
#     - apache/doris:be-3.1.4
#     - apache/doris:operator-1.4.0
#     - minio/minio:latest
#
# 使用方法:
#   ./deploy.sh
#
# 部署顺序:
#   1. 检查环境
#   2. 部署 FDB CRD
#   3. 部署 FDB Operator
#   4. 部署 FDB 集群
#   5. 部署 MinIO
#   6. 部署 Doris Operator
#   7. 部署 Doris CRD
#   8. 部署 DorisDisaggregatedCluster
#   9. 部署 HPA
#   10. 验证
# =============================================================================

set -e

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# 配置
# =============================================================================

# 镜像配置
FDB_OPERATOR_IMAGE="${FDB_OPERATOR_IMAGE:-fdb-kubernetes-operator:1.12.0}"
FDB_IMAGE="${FDB_IMAGE:-foundationdb/foundationdb:7.1.37}"
DORIS_FE_IMAGE="${DORIS_FE_IMAGE:-apache/doris:fe-3.1.4}"
DORIS_BE_IMAGE="${DORIS_BE_IMAGE:-apache/doris:be-3.1.4}"
OPERATOR_IMAGE="${OPERATOR_IMAGE:-apache/doris:operator-1.4.0}"
MINIO_IMAGE="${MINIO_IMAGE:-minio/minio:latest}"

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

    # 检查 metrics-server
    if ! kubectl get pods -n kube-system -l k8s-app=metrics-server 2>/dev/null | grep -q Running; then
        log_warn "metrics-server 未运行，HPA 可能无法工作"
        log_warn "安装命令: kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
    fi

    log_info "环境检查完成"
}

# =============================================================================
# 1. 部署 FDB CRD
# =============================================================================
deploy_fdb_crd() {
    log_info "[1/10] 部署 FoundationDB CRD..."

    kubectl apply -f "${SCRIPT_DIR}/fdb-crd.yaml"

    # 等待 CRD 创建完成
    kubectl wait --for=condition=established crd foundationdbclusters.apps.foundationdb.org --timeout=60s || true

    log_info "FDB CRD 部署完成"
}

# =============================================================================
# 2. 部署 FDB Operator
# =============================================================================
deploy_fdb_operator() {
    log_info "[2/10] 部署 FoundationDB Operator..."

    kubectl apply -f "${SCRIPT_DIR}/namespace.yaml"
    kubectl apply -f "${SCRIPT_DIR}/fdb-operator.yaml"

    log_info "等待 FDB Operator 就绪..."
    kubectl wait --for=condition=Ready pods -n foundationdb \
        -l app.kubernetes.io/name=foundationdb,app.kubernetes.io/component=operator --timeout=180s || {
        log_warn "FDB Operator 启动超时，查看状态..."
        kubectl get pods -n foundationdb
        kubectl logs -n foundationdb -l app.kubernetes.io/name=foundationdb,app.kubernetes.io/component=operator --tail=30 || true
    }

    log_info "FDB Operator 部署完成"
}

# =============================================================================
# 3. 部署 FDB 集群
# =============================================================================
deploy_fdb_cluster() {
    log_info "[3/10] 部署 FoundationDB 集群..."

    kubectl apply -f "${SCRIPT_DIR}/fdbcluster.yaml"

    log_info "等待 FDB 集群就绪..."
    # FDB 集群需要较长时间初始化
    kubectl wait --for=condition=Ready pods -n foundationdb \
        -l app.kubernetes.io/name=foundationdb,app.kubernetes.io/component=database --timeout=600s || {
        log_warn "FDB 集群启动超时，查看状态..."
        kubectl get pods -n foundationdb
        kubectl logs -n foundationdb -l app.kubernetes.io/name=foundationdb,app.kubernetes.io/component=database --tail=50 || true
    }

    log_info "FDB 集群部署完成"
}

# =============================================================================
# 4. 部署 MinIO
# =============================================================================
deploy_minio() {
    log_info "[4/10] 部署 MinIO..."

    kubectl apply -f "${SCRIPT_DIR}/minio.yaml"

    log_info "等待 MinIO 就绪..."
    kubectl wait --for=condition=Ready pods -n foundationdb \
        -l app.kubernetes.io/name=minio --timeout=300s || {
        log_warn "MinIO 启动超时，查看状态..."
        kubectl get pods -n foundationdb
        kubectl logs -n foundationdb -l app.kubernetes.io/name=minio --tail=50 || true
    }

    # 等待 MinIO 完全启动
    sleep 5

    log_info "MinIO 部署完成"
}

# =============================================================================
# 5. 部署 Doris Operator
# =============================================================================
deploy_doris_operator() {
    log_info "[5/10] 部署 Doris Operator..."

    kubectl apply -f "${SCRIPT_DIR}/doris-operator.yaml"

    log_info "等待 Doris Operator 就绪..."
    kubectl wait --for=condition=Ready pods -n doris-operator-system \
        -l app.kubernetes.io/name=doris-operator --timeout=180s || {
        log_warn "Doris Operator 启动超时，查看状态..."
        kubectl get pods -n doris-operator-system
        kubectl logs -n doris-operator-system -l app.kubernetes.io/name=doris-operator --tail=30 || true
    }

    log_info "Doris Operator 部署完成"
}

# =============================================================================
# 6. 部署 Doris CRD
# =============================================================================
deploy_doris_crd() {
    log_info "[6/10] 部署 Doris CRD..."

    kubectl apply -f "${SCRIPT_DIR}/doris-crd.yaml"

    # 等待 CRD 创建完成
    kubectl wait --for=condition=established crd dorisclusters.doris.apache.com --timeout=60s || true
    kubectl wait --for=condition=established crd dorisdisaggregatedclusters.doris.apache.com --timeout=60s || true

    log_info "Doris CRD 部署完成"
}

# =============================================================================
# 7. 部署 DorisDisaggregatedCluster
# =============================================================================
deploy_doris_cluster() {
    log_info "[7/10] 部署 DorisDisaggregatedCluster..."

    # 部署 Secret 和 ConfigMap
    kubectl apply -f "${SCRIPT_DIR}/secret.yaml"
    kubectl apply -f "${SCRIPT_DIR}/configmap.yaml"

    # 部署 DorisDisaggregatedCluster
    kubectl apply -f "${SCRIPT_DIR}/doris-disaggregated-cluster.yaml"

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
# 8. 部署 HPA
# =============================================================================
deploy_hpa() {
    log_info "[8/10] 部署 HPA..."

    kubectl apply -f "${SCRIPT_DIR}/hpa.yaml"

    log_info "HPA 部署完成"
}

# =============================================================================
# 9. 验证集群
# =============================================================================
verify_cluster() {
    log_info "[9/10] 验证集群状态..."

    echo ""
    log_info "=== 集群资源状态 ==="

    echo ""
    log_info "FoundationDB Pods:"
    kubectl get pods -n foundationdb

    echo ""
    log_info "Doris Pods:"
    kubectl get pods -n doris

    echo ""
    log_info "Doris Operator Pods:"
    kubectl get pods -n doris-operator-system

    echo ""
    log_info "Services:"
    kubectl get svc -n doris
    kubectl get svc -n foundationdb

    echo ""
    log_info "HPA:"
    kubectl get hpa -n doris || true
}

# =============================================================================
# 10. 显示访问信息
# =============================================================================
show_access_info() {
    log_info "[10/10] 显示访问信息..."

    # 获取节点 IP
    local node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "localhost")

    # 获取 FE NodePort
    local fe_query_port=$(kubectl get svc -n doris doris-fe-service -o jsonpath='{.spec.ports[?(@.name=="query-port")].nodePort}' 2>/dev/null || echo "30632")
    local fe_http_port=$(kubectl get svc -n doris doris-fe-service -o jsonpath='{.spec.ports[?(@.name=="http-port")].nodePort}' 2>/dev/null || echo "30389")

    echo ""
    log_info "=========================================="
    log_info "   Doris 存算分离集群部署完成！"
    log_info "=========================================="
    echo ""
    log_info "访问信息:"
    echo "  - FE MySQL:  ${node_ip}:${fe_query_port}"
    echo "  - FE HTTP:   http://${node_ip}:${fe_http_port}"
    echo "  - MinIO API: http://${node_ip}:30000"
    echo "  - MinIO Console: http://${node_ip}:30001"
    echo ""
    log_info "连接命令:"
    echo "  mysql -h ${node_ip} -P ${fe_query_port} -u root"
    echo ""
    log_info "MinIO 凭证:"
    echo "  用户名: minioadmin"
    echo "  密码: minioadmin"
    echo ""
    log_info "验证 SQL:"
    echo "  SHOW FRONTENDS;"
    echo "  SHOW BACKENDS;"
    echo "  SHOW PROC '/frontends';"
    echo "  SHOW PROC '/backends';"
    echo ""
    log_info "HPA 状态:"
    echo "  kubectl get hpa -n doris"
    echo ""
}

# =============================================================================
# 主函数
# =============================================================================
main() {
    echo ""
    log_info "=========================================="
    log_info "  Doris 存算分离架构 部署脚本"
    log_info "  (FE + BECN + MetaService + MinIO + FDB)"
    log_info "=========================================="
    echo ""

    # 检查环境
    check_environment

    # 部署
    deploy_fdb_crd
    deploy_fdb_operator
    deploy_fdb_cluster
    deploy_minio
    deploy_doris_operator
    deploy_doris_crd
    deploy_doris_cluster
    deploy_hpa
    verify_cluster
    show_access_info

    echo ""
    log_info "部署成功！"
}

# 执行
main "$@"