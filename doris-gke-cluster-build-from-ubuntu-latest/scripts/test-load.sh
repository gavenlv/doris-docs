#!/bin/bash

# ==========================================
# Doris GKE Cluster - Load Test Script
# ==========================================
# Purpose: 测试 Doris 集群负载能力
# Version: 1.0

set -e

# ==========================================
# Configuration
# ==========================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 测试配置
TEST_DATA_SIZE="${TEST_DATA_SIZE:-10000000}"  # 1000万行
TEST_THREADS="${TEST_THREADS:-10}"
FE_HOST="${FE_HOST:-}"
FE_PORT="${FE_PORT:-9030}"

# ==========================================
# Color Output
# ==========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ==========================================
# Functions
# ==========================================

check_prerequisites() {
    log_info "检查测试环境..."
    
    if ! command -v mysql &> /dev/null; then
        log_error "MySQL 客户端未安装"
        exit 1
    fi
    
    if [ -z "$FE_HOST" ]; then
        log_error "未设置 FE_HOST"
        log_info "获取 FE IP: kubectl get svc fe-lb -n doris"
        exit 1
    fi
    
    log_info "环境检查通过"
}

create_test_table() {
    log_info "创建测试表..."
    
    mysql -h "$FE_HOST" -P "$FE_PORT" -u root <<EOF
CREATE DATABASE IF NOT EXISTS test_load;
USE test_load;

CREATE TABLE IF NOT EXISTS test_table (
    id INT,
    name VARCHAR(100),
    value DOUBLE,
    created_at DATETIME
) DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 10
PROPERTIES (
    "replication_num" = "3"
);
EOF
    
    log_info "测试表创建完成"
}

generate_test_data() {
    log_info "生成测试数据..."
    
    local data_file="/tmp/test_data.csv"
    
    # 生成 CSV 数据
    for i in $(seq 1 $TEST_DATA_SIZE); do
        echo "$i,name_$i,$((RANDOM * 100 / 32767)).$RANDOM,$(date -Iseconds)"
    done > "$data_file"
    
    log_info "测试数据生成完成: $data_file"
    log_info "数据量: $(wc -l < $data_file) 行"
    log_info "文件大小: $(du -h $data_file | cut -f1)"
    
    echo "$data_file"
}

run_stream_load() {
    local data_file="$1"
    
    log_info "执行 Stream Load..."
    
    local start_time=$(date +%s)
    
    curl -X PUT \
        -H "column_separator:," \
        -H "columns:id,name,value,created_at" \
        -T "$data_file" \
        "http://${FE_HOST}:8030/api/test_load/test_table/_stream_load" \
        -u root:
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_info "导入完成，耗时: ${duration} 秒"
    
    # 验证数据
    local count=$(mysql -h "$FE_HOST" -P "$FE_PORT" -u root -N -e "SELECT COUNT(*) FROM test_load.test_table")
    log_info "数据验证: $count 行"
}

run_query_test() {
    log_info "执行查询测试..."
    
    local queries=(
        "SELECT COUNT(*) FROM test_load.test_table"
        "SELECT AVG(value) FROM test_load.test_table"
        "SELECT * FROM test_load.test_table LIMIT 100"
        "SELECT id, SUM(value) FROM test_load.test_table GROUP BY id ORDER BY id LIMIT 10"
    )
    
    for query in "${queries[@]}"; do
        log_info "执行: $query"
        local start=$(date +%s%N)
        mysql -h "$FE_HOST" -P "$FE_PORT" -u root -e "$query"
        local end=$(date +%s%N)
        local duration=$(( (end - start) / 1000000 ))
        log_info "耗时: ${duration} ms"
        echo ""
    done
}

cleanup() {
    log_info "清理测试数据..."
    mysql -h "$FE_HOST" -P "$FE_PORT" -u root -e "DROP DATABASE IF EXISTS test_load"
    rm -f /tmp/test_data.csv
    log_info "清理完成"
}

# ==========================================
# Main
# ==========================================

main() {
    local action="${1:-all}"
    
    echo "=========================================="
    echo " Doris 负载测试"
    echo "=========================================="
    echo ""
    
    case "$action" in
        create)
            create_test_table
            ;;
        load)
            local data_file=$(generate_test_data)
            run_stream_load "$data_file"
            ;;
        query)
            run_query_test
            ;;
        cleanup)
            cleanup
            ;;
        all)
            check_prerequisites
            echo ""
            create_test_table
            echo ""
            local data_file=$(generate_test_data)
            echo ""
            run_stream_load "$data_file"
            echo ""
            run_query_test
            echo ""
            cleanup
            ;;
        *)
            echo "用法: $0 {all|create|load|query|cleanup}"
            exit 1
            ;;
    esac
    
    log_info "测试完成!"
}

main "$@"
