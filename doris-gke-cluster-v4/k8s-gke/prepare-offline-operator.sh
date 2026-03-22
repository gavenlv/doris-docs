#!/bin/bash
# =============================================================================
# Doris Operator 离线安装包制作脚本
# =============================================================================
# 作用: 下载并打包 Doris Operator 用于离线部署
# 适用: 无法访问 GitHub 的私有环境
#
# 使用方法:
#   ./prepare-offline-operator.sh [版本号]
#   示例: ./prepare-offline-operator.sh 25.8.0
#
# 输出:
#   doris-operator-{版本号}.tar.gz
# =============================================================================

set -e

# 默认版本
VERSION="${1:-25.8.0}"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 下载 Operator
download_operator() {
    log_info "下载 Doris Operator ${VERSION}..."

    local output_dir="doris-operator-${VERSION}"
    local output_tar="${output_dir}.tar.gz"

    # 创建临时目录
    mkdir -p "$output_dir"

    # 下载 CRD
    log_info "下载 CRD..."
    mkdir -p "${output_dir}/config/crd/bases"
    curl -sL "https://raw.githubusercontent.com/apache/doris-operator/${VERSION}/config/crd/bases/doris.apache.com_dorisclusters.yaml" \
        -o "${output_dir}/config/crd/bases/doris.apache.com_dorisclusters.yaml"

    # 下载 Operator deployment
    log_info "下载 Operator 配置..."
    mkdir -p "${output_dir}/config/operator"
    curl -sL "https://raw.githubusercontent.com/apache/doris-operator/${VERSION}/config/operator/operator.yaml" \
        -o "${output_dir}/config/operator/operator.yaml"

    # 下载 RBAC
    log_info "下载 RBAC 配置..."
    mkdir -p "${output_dir}/config/rbac"
    curl -sL "https://raw.githubusercontent.com/apache/doris-operator/${VERSION}/config/rbac/role.yaml" \
        -o "${output_dir}/config/rbac/role.yaml"

    # 下载 webhook (如果存在)
    mkdir -p "${output_dir}/config/webhook"
    curl -sL "https://raw.githubusercontent.com/apache/doris-operator/${VERSION}/config/webhook/webhook.yaml" \
        -o "${output_dir}/config/webhook/webhook.yaml" 2>/dev/null || true

    # 下载示例
    log_info "下载示例配置..."
    mkdir -p "${output_dir}/doc/examples"
    curl -sL "https://raw.githubusercontent.com/apache/doris-operator/${VERSION}/doc/examples/doriscluster-sample.yaml" \
        -o "${output_dir}/doc/examples/doriscluster-sample.yaml"

    # 下载 README
    curl -sL "https://raw.githubusercontent.com/apache/doris-operator/${VERSION}/README.md" \
        -o "${output_dir}/README.md"

    # 打包
    log_info "打包..."
    tar -czf "$output_tar" "$output_dir"

    # 清理临时目录
    rm -rf "$output_dir"

    log_info "离线包已创建: $output_tar"
    log_info "大小: $(du -h $output_tar | cut -f1)"
}

# 主函数
main() {
    echo ""
    log_info "=========================================="
    log_info "  Doris Operator 离线包制作脚本"
    log_info "=========================================="
    echo ""

    download_operator

    echo ""
    log_info "=========================================="
    log_info "  离线包使用说明"
    log_info "=========================================="
    echo ""
    echo "1. 将 tar.gz 包复制到目标机器"
    echo ""
    echo "2. 解压:"
    echo "   tar -xzf doris-operator-${VERSION}.tar.gz"
    echo ""
    echo "3. 部署:"
    echo "   kubectl apply -f ./doris-operator/config/crd/bases/"
    echo "   kubectl apply -f ./doris-operator/config/operator/"
    echo ""
    echo "4. 验证:"
    echo "   kubectl get pods -n doris"
    echo ""
}

main "$@"
