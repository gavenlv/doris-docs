#!/bin/bash
# =============================================================================
# Doris GKE 生产部署脚本 (存储计算分离架构 + 离线 Operator)
# =============================================================================
# 作用: 一键部署 GKE 生产 Doris 集群
# 适用: Google Kubernetes Engine
#
# 部署模式:
#   - 存储计算分离: BE 数据存储在 GCS
#   - 高可用: 3FE (Leader/Follower) + 3BE
#   - 离线 Operator: 从本地包安装，不依赖外部网络
#
# 前置条件:
#   - GCP 项目已创建
#   - GKE 集群已创建 (1.28+)
#   - gcloud CLI 已配置
#   - kubectl 已配置
#   - Service Account 密钥已下载 (如果使用密钥认证)
#   - Doris Operator 离线包已准备
#
# 使用方法:
#   export PROJECT_ID="your-project-id"
#   export CLUSTER_NAME="doris-cluster"
#   export REGION="us-central1"
#   ./deploy.sh
# =============================================================================

set -e

# =============================================================================
# 配置
# =============================================================================

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

# =============================================================================
# 配置检查
# =============================================================================

# 检查必要的环境变量
check_config() {
    log_info "检查配置..."

    if [ -z "$PROJECT_ID" ]; then
        log_error "未设置 PROJECT_ID"
        echo "请设置: export PROJECT_ID=\"your-project-id\""
        exit 1
    fi

    if [ -z "$CLUSTER_NAME" ]; then
        log_error "未设置 CLUSTER_NAME"
        echo "请设置: export CLUSTER_NAME=\"doris-cluster\""
        exit 1
    fi

    if [ -z "$REGION" ]; then
        log_error "未设置 REGION"
        echo "请设置: export REGION=\"us-central1\""
        exit 1
    fi

    log_info "PROJECT_ID: $PROJECT_ID"
    log_info "CLUSTER_NAME: $CLUSTER_NAME"
    log_info "REGION: $REGION"
}

# 检查工具
check_tools() {
    log_info "检查必要工具..."

    local tools=("kubectl" "gcloud")

    for tool in "${tools[@]}"; do
        if ! command -v $tool &> /dev/null; then
            log_error "$tool 未安装"
            exit 1
        fi
    done

    # 检查 kubectl 配置
    if ! kubectl cluster-info &> /dev/null; then
        log_error "kubectl 未配置或无法连接到集群"
        exit 1
    fi

    # 检查当前集群
    local context=$(kubectl config current-context 2>/dev/null || echo "unknown")
    log_info "当前 Context: $context"
}

# =============================================================================
# GCS Bucket 配置
# =============================================================================

# 创建 GCS Bucket
create_gcs_bucket() {
    log_info "检查/创建 GCS Bucket..."

    local bucket_name="${PROJECT_ID}-doris-data"

    # 检查 Bucket 是否存在
    if gsutil ls -b "gs://${bucket_name}" &> /dev/null; then
        log_info "Bucket ${bucket_name} 已存在"
    else
        log_info "创建 Bucket ${bucket_name}..."
        gsutil mb -p $PROJECT_ID -l $REGION "gs://${bucket_name}"

        # 设置生命周期
        gsutil lifecycle set lifecycle-config.json "gs://${bucket_name}" 2>/dev/null || true

        log_info "Bucket ${bucket_name} 创建完成"
    fi
}

# 配置 Workload Identity
configure_workload_identity() {
    log_info "配置 Workload Identity..."

    # GCP Service Account 名称
    local gcp_sa_name="doris-gcs-sa"
    local gcp_sa_email="${gcp_sa_name}@${PROJECT_ID}.iam.gserviceaccount.com"

    # 创建 GCP Service Account (如果不存在)
    if ! gcloud iam service-accounts describe $gcp_sa_email --project=$PROJECT_ID &> /dev/null; then
        log_info "创建 GCP Service Account: $gcp_sa_email"
        gcloud iam service-accounts create $gcp_sa_name \
            --project=$PROJECT_ID \
            --display-name="Doris GCS Access"
    fi

    # 绑定 Storage Object Admin 角色
    log_info "绑定 Storage 角色..."
    gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:${gcp_sa_email}" \
        --role="roles/storage.objectAdmin" \
        --condition=None

    # 创建 K8s Service Account (如果不存在)
    kubectl create serviceaccount doris-gcs-sa -n doris --dry-run=client -o yaml | kubectl apply -f -

    # 绑定 GCP Service Account
    log_info "绑定 Workload Identity..."
    gcloud iam service-accounts add-iam-policy-binding $gcp_sa_email \
        --project=$PROJECT_ID \
        --member="serviceAccount:${PROJECT_ID}.svc.id.goog[doris/doris-gcs-sa]" \
        --role="roles/iam.workloadIdentityUser"

    # 更新 K8s Service Account 添加注解
    kubectl annotate serviceaccount doris-gcs-sa -n doris \
        iam.gke.io/gcp-service-account=${gcp_sa_email} \
        --overwrite

    log_info "Workload Identity 配置完成"
}

# =============================================================================
# 存储配置
# =============================================================================

# 创建 GKE StorageClass
create_storageclass() {
    log_info "创建 GKE StorageClass..."

    kubectl apply -f 00-namespace.yaml

    log_info "StorageClass 创建完成"
}

# =============================================================================
# Doris Operator 部署 (离线)
# =============================================================================

# 部署离线 Operator
deploy_offline_operator() {
    log_info "部署 Doris Operator (离线模式)..."

    # 检查是否有离线包
    local operator_version="25.8.0"
    local offline_bundle="doris-operator-${operator_version}.tar.gz"

    if [ -f "$offline_bundle" ]; then
        log_info "使用离线包: $offline_bundle"

        # 解压离线包
        tar -xzf $offline_bundle

        # 部署 CRD
        kubectl apply -f ./doris-operator/config/crd/bases/

        # 部署 Operator
        kubectl apply -f ./doris-operator/config/operator/

        # 清理
        rm -rf ./doris-operator

        log_info "离线 Operator 部署完成"
    else
        log_warn "未找到离线包: $offline_bundle"
        log_info "尝试从 GitHub 下载..."

        # 下载 CRD
        kubectl apply -f "https://raw.githubusercontent.com/apache/doris-operator/${operator_version}/config/crd/bases/doris.apache.com_dorisclusters.yaml"

        # 下载 Operator
        kubectl apply -f "https://raw.githubusercontent.com/apache/doris-operator/${operator_version}/config/operator/operator.yaml"

        log_info "Operator 部署完成 (在线模式)"
    fi

    # 等待 Operator 就绪
    log_info "等待 Operator 启动..."
    kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=doris-operator -n doris --timeout=180s || {
        log_error "Operator 启动超时"
        kubectl get pods -n doris
        exit 1
    }

    log_info "Doris Operator 部署完成"
}

# =============================================================================
# DorisCluster 部署
# =============================================================================

# 部署 DorisCluster
deploy_doriscluster() {
    log_info "部署 DorisCluster..."

    # 更新 GCS bucket 名称
    sed "s/doris-data-production/${PROJECT_ID}-doris-data/g" doriscluster.yaml | kubectl apply -f -

    log_info "DorisCluster 部署完成"
}

# 等待集群就绪
wait_for_cluster() {
    log_info "等待集群就绪 (这可能需要 10-20 分钟)..."

    # 等待 FE 就绪
    log_info "等待 FE 启动..."
    kubectl wait --for=condition=Ready pods -l app.kubernetes.io/component=fe -n doris --timeout=1200s || {
        log_error "FE 启动超时"
        kubectl get pods -n doris
        kubectl logs -l app.kubernetes.io/component=fe -n doris --tail=100
        exit 1
    }

    # 等待 BE 就绪
    log_info "等待 BE 启动..."
    kubectl wait --for=condition=Ready pods -l app.kubernetes.io/component=be -n doris --timeout=1200s || {
        log_error "BE 启动超时"
        kubectl get pods -n doris
        kubectl logs -l app.kubernetes.io/component=be -n doris --tail=100
        exit 1
    }

    log_info "集群就绪"
}

# =============================================================================
# 验证
# =============================================================================

# 验证集群
verify_cluster() {
    log_info "验证集群状态..."

    # 检查 pods
    kubectl get pods -n doris

    # 检查 services
    kubectl get svc -n doris

    # 获取 FE IP
    local fe_svc=$(kubectl get svc -n doris -l app.kubernetes.io/component=fe -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")

    echo ""
    log_info "=========================================="
    log_info "       GKE Doris 集群部署完成！"
    log_info "=========================================="
    echo ""
    log_info "FE LoadBalancer: $fe_svc"
    log_info "FE MySQL 端口: 9030"
    log_info "FE HTTP 端口: 8030"
    echo ""
    log_info "连接命令:"
    echo "   mysql -h${fe_svc} -P9030 -uroot"
    echo ""
    log_info "GCS Bucket: gs://${PROJECT_ID}-doris-data"
    echo ""
}

# =============================================================================
# 主函数
# =============================================================================

main() {
    echo ""
    log_info "=========================================="
    log_info "   Doris GKE 生产部署脚本"
    log_info "   (存储计算分离 + 离线 Operator)"
    log_info "=========================================="
    echo ""

    # 检查
    check_config
    check_tools

    # 部署
    create_gcs_bucket
    configure_workload_identity
    create_storageclass
    deploy_offline_operator
    deploy_doriscluster
    wait_for_cluster

    # 验证
    verify_cluster
}

# 执行
main "$@"
