#!/bin/bash
# Doris GKE 卸载脚本 - 生产环境

set -e

NAMESPACE="doris"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Doris GKE 卸载脚本 ==="
echo "Namespace: $NAMESPACE"

# 确认操作
read -p "警告: 此操作将删除所有 Doris 数据! 继续? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "取消卸载"
    exit 0
fi

# 1. 删除可选组件
echo "[1/5] 删除可选组件..."
kubectl delete -f "${SCRIPT_DIR}/hpa.yaml" --ignore-not-found=true
kubectl delete -f "${SCRIPT_DIR}/backup.yaml" --ignore-not-found=true
kubectl delete -f "${SCRIPT_DIR}/monitoring.yaml" --ignore-not-found=true
kubectl delete -f "${SCRIPT_DIR}/network-policy.yaml" --ignore-not-found=true
kubectl delete -f "${SCRIPT_DIR}/services.yaml" --ignore-not-found=true

# 2. 删除 DorisCluster
echo "[2/5] 删除 DorisCluster..."
kubectl delete -f "${SCRIPT_DIR}/doriscluster.yaml" --ignore-not-found=true

# 3. 删除 ConfigMap
echo "[3/5] 删除 ConfigMap..."
kubectl delete -f "${SCRIPT_DIR}/configmap.yaml" --ignore-not-found=true
kubectl delete -f "${SCRIPT_DIR}/configmap-be.yaml" --ignore-not-found=true

# 4. 删除 Secret
echo "[4/5] 删除 Secret..."
kubectl delete -f "${SCRIPT_DIR}/secret.yaml" --ignore-not-found=true

# 5. 删除命名空间和存储
echo "[5/5] 删除命名空间和存储..."
kubectl delete -f "${SCRIPT_DIR}/00-namespace.yaml" --ignore-not-found=true

# 6. 删除 Doris Operator (可选)
read -p "是否删除 Doris Operator 和 CRD? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    kubectl delete -f https://raw.githubusercontent.com/apache/doris-operator/25.8.0/config/operator/operator.yaml --ignore-not-found=true
    kubectl delete -f https://raw.githubusercontent.com/apache/doris-operator/25.8.0/config/crd/bases/doris.apache.com_dorisclusters.yaml --ignore-not-found=true
    echo "Doris Operator 已删除"
fi

echo ""
echo "=== 卸载完成 ==="
echo ""
echo "注意: PVC (PersistentVolumeClaims) 可能需要手动删除以释放云存储资源"
echo "请在 GKE Console 或使用以下命令检查:"
echo "kubectl get pvc -n doris"
