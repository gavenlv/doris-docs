#!/bin/bash
# =============================================================================
# Doris Local K8s 卸载脚本 - 存算分离架构
# =============================================================================
# 作用: 卸载本地 Doris 集群及相关资源
# 使用: ./undeploy.sh
#
# 卸载顺序 (按依赖关系倒序):
#   1. 删除 DorisDisaggregatedCluster
#   2. 删除 MinIO (StatefulSet + Service + PVC)
#   3. 删除 FoundationDB 集群
#   4. 删除 FoundationDB Operator
#   5. 删除 Doris Operator
#   6. 删除 Doris namespace 和 RBAC
#   7. 删除 foundationdb namespace
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "=========================================="
echo "   Doris Local K8s 卸载脚本"
echo "   (存算分离架构)"
echo "=========================================="
echo ""

# 确认操作
read -p "警告: 此操作将删除所有 Doris 数据! 继续? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "取消卸载"
    exit 0
fi

# =============================================================================
# 1. 删除 DorisDisaggregatedCluster
# =============================================================================
echo ""
echo "[1/8] 删除 DorisDisaggregatedCluster..."
kubectl delete -f "${SCRIPT_DIR}/doris-disaggregated-cluster.yaml" --ignore-not-found=true
echo "DorisDisaggregatedCluster 已删除"

# =============================================================================
# 2. 删除 MinIO
# =============================================================================
echo ""
echo "[2/8] 删除 MinIO..."
kubectl delete -f "${SCRIPT_DIR}/minio-statefulset.yaml" --ignore-not-found=true
echo "MinIO 已删除"

# 删除 MinIO 的 PVC (如有)
echo "删除 MinIO PVC..."
kubectl delete pvc -n foundationdb -l app.kubernetes.io/name=minio --ignore-not-found=true
echo "MinIO PVC 已删除"

# =============================================================================
# 3. 删除 FoundationDB 集群
# =============================================================================
echo ""
echo "[3/8] 删除 FoundationDB 集群..."
kubectl delete -f "${SCRIPT_DIR}/fdbcluster.yaml" --ignore-not-found=true
echo "FoundationDB 集群已删除"

# 删除 FDB 的 PVC (如有)
echo "删除 FDB PVC..."
kubectl delete pvc -n foundationdb -l app.kubernetes.io/name=foundationdb --ignore-not-found=true
echo "FDB PVC 已删除"

# =============================================================================
# 4. 删除 FoundationDB Operator
# =============================================================================
echo ""
echo "[4/8] 删除 FoundationDB Operator..."
kubectl delete -f "${SCRIPT_DIR}/fdb-operator.yaml" --ignore-not-found=true
echo "FoundationDB Operator 已删除"

# =============================================================================
# 5. 删除 Doris Operator
# =============================================================================
echo ""
echo "[5/8] 删除 Doris Operator..."
kubectl delete -f "${SCRIPT_DIR}/operator.yaml" --ignore-not-found=true
echo "Doris Operator 已删除"

# =============================================================================
# 6. 删除 Doris namespace 和 RBAC
# =============================================================================
echo ""
echo "[6/8] 删除 Doris namespace..."
kubectl delete namespace doris --ignore-not-found=true
echo "Doris namespace 已删除"

# =============================================================================
# 7. 删除 foundationdb namespace
# =============================================================================
echo ""
echo "[7/8] 删除 foundationdb namespace..."
kubectl delete namespace foundationdb --ignore-not-found=true
echo "foundationdb namespace 已删除"

# =============================================================================
# 8. 清理集群级别资源
# =============================================================================
echo ""
echo "[8/8] 清理集群级别资源 (StorageClass, CRD)..."
kubectl delete -f "${SCRIPT_DIR}/00-namespace.yaml" --ignore-not-found=true
kubectl delete -f "${SCRIPT_DIR}/operator.yaml" --ignore-not-found=true
echo "集群级别资源已清理"

# =============================================================================
# 完成
# =============================================================================
echo ""
echo "=========================================="
echo "   卸载完成"
echo "=========================================="
echo ""
echo "已清理的资源:"
echo "  - DorisDisaggregatedCluster (FE + BECN + MetaService)"
echo "  - MinIO (StatefulSet + Service + PVC)"
echo "  - FoundationDB 集群 (Cluster + PVC)"
echo "  - FoundationDB Operator"
echo "  - Doris Operator"
echo "  - namespace doris"
echo "  - namespace foundationdb"
echo "  - StorageClass (doris-fe-storage, doris-be-storage)"
echo "  - CRD (dorisclusters, dorisdisaggregatedclusters)"
echo ""
echo "如需完全清理残留 PVC，请运行:"
echo "  kubectl delete pvc --all -A"
echo ""
