#!/bin/bash
# =============================================================================
# Doris Local K8s 卸载脚本
# =============================================================================
# 作用: 卸载本地 Doris 集群及相关资源
# 使用: ./undeploy.sh
#
# 卸载顺序:
#   1. 删除 HPA (如果存在)
#   2. 删除 DorisCluster
#   3. 删除 ConfigMap 和 Secret
#   4. 删除命名空间和 RBAC
#   5. 删除 Doris Operator (可选)
# =============================================================================

set -e

NAMESPACE="doris"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "=========================================="
echo "   Doris Local K8s 卸载脚本"
echo "=========================================="
echo ""
echo "Namespace: $NAMESPACE"
echo ""

# 1. 删除 HPA
echo "[1/5] 删除 HPA 自动扩缩容..."
kubectl delete -f "${SCRIPT_DIR}/hpa.yaml" --ignore-not-found=true
echo "HPA 已删除"

# 2. 删除 DorisCluster
echo ""
echo "[2/5] 删除 DorisCluster..."
kubectl delete -f "${SCRIPT_DIR}/doriscluster.yaml" --ignore-not-found=true
echo "DorisCluster 已删除"

# 3. 删除 ConfigMap
echo ""
echo "[3/5] 删除 ConfigMap..."
kubectl delete -f "${SCRIPT_DIR}/configmap.yaml" --ignore-not-found=true
echo "ConfigMap 已删除"

# 4. 删除命名空间和存储
echo ""
echo "[4/5] 删除命名空间和存储..."
kubectl delete -f "${SCRIPT_DIR}/00-namespace.yaml" --ignore-not-found=true
echo "命名空间已删除"

# 5. 删除 Doris Operator (可选)
echo ""
echo "[5/5] 删除 Doris Operator..."
read -p "是否删除 Doris Operator 和 CRD? (y/N): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    kubectl delete -f "${SCRIPT_DIR}/operator.yaml" --ignore-not-found=true
    echo "Doris Operator 已删除"
else
    echo "保留 Doris Operator"
fi

echo ""
echo "=========================================="
echo "   卸载完成"
echo "=========================================="
echo ""
echo "提示:"
echo "  - 如需彻底清理，运行: kubectl delete namespace doris"
echo "  - 如需彻底清理 Operator，运行: kubectl delete -f operator.yaml"
echo ""