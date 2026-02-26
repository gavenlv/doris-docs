#!/bin/bash

# ==========================================
# Doris GKE Cluster - Load Testing Script
# ==========================================
# Test performance for 50 billion rows ingestion in 2 minutes

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ==========================================
# Configuration
# ==========================================
FE_HOST="${FE_HOST:-localhost}"
FE_PORT="${FE_PORT:-9030}"
DB_NAME="${DB_NAME:-test_db}"
TABLE_NAME="${TABLE_NAME:-test_table}"

# ==========================================
# Functions
# ==========================================

create_test_table() {
    log_info "Creating test table..."
    
    mysql -h "$FE_HOST" -P "$FE_PORT" -u root <<EOF
CREATE DATABASE IF NOT EXISTS $DB_NAME;
USE $DB_NAME;

DROP TABLE IF EXISTS $TABLE_NAME;

CREATE TABLE $TABLE_NAME (
    id BIGINT,
    user_id INT,
    event_time DATETIME,
    dim1 INT,
    dim2 VARCHAR(100),
    dim3 INT,
    metric1 DOUBLE,
    metric2 DOUBLE,
    -- Add more columns to reach 90 columns
    col4 INT, col5 INT, col6 INT, col7 INT, col8 INT, col9 INT, col10 INT,
    col11 VARCHAR(100), col12 VARCHAR(100), col13 VARCHAR(100),
    col14 DOUBLE, col15 DOUBLE, col16 DOUBLE, col17 DOUBLE, col18 DOUBLE,
    col19 INT, col20 INT, col21 INT, col22 INT, col23 INT, col24 INT, col25 INT,
    col26 VARCHAR(100), col27 VARCHAR(100), col28 VARCHAR(100),
    col29 DOUBLE, col30 DOUBLE, col31 DOUBLE, col32 DOUBLE, col33 DOUBLE,
    col34 INT, col35 INT, col36 INT, col37 INT, col38 INT, col39 INT, col40 INT,
    col41 VARCHAR(100), col42 VARCHAR(100), col43 VARCHAR(100),
    col44 DOUBLE, col45 DOUBLE, col46 DOUBLE, col47 DOUBLE, col48 DOUBLE,
    col49 INT, col50 INT, col51 INT, col52 INT, col53 INT, col54 INT, col55 INT,
    col56 VARCHAR(100), col57 VARCHAR(100), col58 VARCHAR(100),
    col59 DOUBLE, col60 DOUBLE, col61 DOUBLE, col62 DOUBLE, col63 DOUBLE,
    col64 INT, col65 INT, col66 INT, col67 INT, col68 INT, col69 INT, col70 INT,
    col71 VARCHAR(100), col72 VARCHAR(100), col73 VARCHAR(100),
    col74 DOUBLE, col75 DOUBLE, col76 DOUBLE, col77 DOUBLE, col78 DOUBLE,
    col79 INT, col80 INT, col81 INT, col82 INT, col83 INT, col84 INT, col85 INT,
    col86 VARCHAR(100), col87 VARCHAR(100), col88 VARCHAR(100),
    col89 DOUBLE, col90 DOUBLE
)
DUPLICATE KEY(id)
PARTITION BY RANGE(event_time) (
    PARTITION p202602 VALUES [('2026-02-01'), ('2026-03-01'))
)
DISTRIBUTED BY HASH(user_id) BUCKETS 128
PROPERTIES (
    "replication_num" = "2",
    "storage_policy" = "hot_to_cold",
    "storage_cooldown_time" = "3 DAY"
);
EOF
    
    log_info "Test table created."
}

generate_test_data() {
    log_info "Generating test data..."
    log_warn "Note: This is a simplified test. For production testing, use realistic data generators."
    
    # Generate CSV with 10M rows as sample
    local rows=${1:-10000000}
    local file="/tmp/test_data_${rows}.csv"
    
    log_info "Generating $rows rows to $file..."
    
    # Simple data generator (replace with your actual data generator)
    for i in $(seq 1 $rows); do
        echo "$i,$((i % 1000000)),2026-02-26 00:00:00,$((i % 1000)),val$((i % 100)),$((i % 500)),$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM,$RANDOM"
    done > "$file"
    
    log_info "Test data generated: $file"
    echo "$file"
}

run_stream_load_test() {
    log_info "Running Stream Load test..."
    
    local data_file=$1
    local start_time=$(date +%s)
    
    # Stream load
    curl --location-trusted -u root: \
        -T "$data_file" \
        -H "column_separator:," \
        -H "columns:id,user_id,event_time,dim1,dim2,dim3,metric1,metric2,col4,col5,col6,col7,col8,col9,col10,col11,col12,col13,col14,col15,col16,col17,col18,col19,col20,col21,col22,col23,col24,col25,col26,col27,col28,col29,col30,col31,col32,col33,col34,col35,col36,col37,col38,col39,col40,col41,col42,col43,col44,col45,col46,col47,col48,col49,col50,col51,col52,col53,col54,col55,col56,col57,col58,col59,col60,col61,col62,col63,col64,col65,col66,col67,col68,col69,col70,col71,col72,col73,col74,col75,col76,col77,col78,col79,col80,col81,col82,col83,col84,col85,col86,col87,col88,col89,col90" \
        http://$FE_HOST:8030/api/$DB_NAME/$TABLE_NAME/_stream_load
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo ""
    log_info "Stream Load completed in $duration seconds"
    
    # Check row count
    local row_count=$(mysql -h "$FE_HOST" -P "$FE_PORT" -u root -N -e "SELECT COUNT(*) FROM $DB_NAME.$TABLE_NAME")
    log_info "Total rows in table: $row_count"
}

run_query_test() {
    log_info "Running query performance test..."
    
    # Query 1: Simple count
    log_info "Query 1: COUNT(*)"
    local start=$(date +%s.%N)
    mysql -h "$FE_HOST" -P "$FE_PORT" -u root -e "SELECT COUNT(*) FROM $DB_NAME.$TABLE_NAME" 
    local end=$(date +%s.%N)
    local duration=$(echo "$end - $start" | bc)
    log_info "Duration: ${duration}s"
    
    echo ""
    
    # Query 2: Star schema join
    log_info "Query 2: Star schema query"
    start=$(date +%s.%N)
    mysql -h "$FE_HOST" -P "$FE_PORT" -u root -e "
        SELECT 
            dim1, 
            COUNT(*) as cnt,
            AVG(metric1) as avg_m1,
            SUM(metric2) as sum_m2
        FROM $DB_NAME.$TABLE_NAME
        WHERE event_time >= '2026-02-01'
        GROUP BY dim1
        ORDER BY cnt DESC
        LIMIT 10
    "
    end=$(date +%s.%N)
    duration=$(echo "$end - $start" | bc)
    log_info "Duration: ${duration}s"
}

# ==========================================
# Main
# ==========================================

main() {
    log_info "Doris GKE Cluster - Performance Test"
    log_info "=========================================="
    echo ""
    
    # Check MySQL client
    if ! command -v mysql &> /dev/null; then
        log_error "mysql client not found. Please install mysql-client."
        exit 1
    fi
    
    # Create test table
    create_test_table
    echo ""
    
    # Generate and load test data
    log_info "Note: For production test of 50B rows, use proper data generators and parallel loading"
    log_info "Running simplified test with 10M rows..."
    
    data_file=$(generate_test_data 10000000)
    echo ""
    
    run_stream_load_test "$data_file"
    echo ""
    
    run_query_test
    
    # Cleanup
    rm -f "$data_file"
    
    echo ""
    log_info "Performance test completed."
    log_info "For production validation:"
    log_info "  1. Use parallel Stream Load (10-20 concurrent connections)"
    log_info "  2. Generate realistic 50B row dataset"
    log_info "  3. Target: <2 minutes for 50B rows ingestion"
    log_info "  4. Target: <10s for queries on 100B row tables"
}

main "$@"
