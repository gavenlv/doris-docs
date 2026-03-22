#!/bin/bash
# Doris Local K8s 卸载脚本

set -e

NAMESPACE="doris"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Doris Local K8s 卸载脚本 ==="
echo "Namespace: $NAMESPACE"

# 1. 删除 DorisCluster
echo "[1/3] 删除 DorisCluster..."
kubectl delete -f "${SCRIPT_DIR}/doriscluster.yaml" --ignore-not-found=true

# 2. 删除 ConfigMap
echo "[2/3] 删除 ConfigMap..."
kubectl delete -f "${SCRIPT_DIR}/configmap.yaml" --ignore-not-found=true

# 3. 删除命名空间和存储
echo "[3/3] 删除命名空间和存储..."
kubectl delete -f "${SCRIPT_DIR}/00-namespace.yaml" --ignore-not-found=true

# 4. 删除 Doris Operator (可选)
read -p "是否删除 Doris Operator 和 CRD? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    kubectl delete -f https://raw.githubusercontent.com/apache/doris-operator/25.8.0/config/operator/operator.yaml --ignore-not-found=true
    kubectl delete -f https://raw.githubusercontent.com/apache/doris-operator/25.8.0/config/crd/bases/doris.apache.com_dorisclusters.yaml --ignore-not-found=true
    echo "Doris Operator 已删除"
fi

echo ""
echo "=== 卸载完成 ==="
