#!/bin/bash
set -e

echo "========================================"
echo "Testing Doris Cluster"
echo "========================================"

MYSQL_CMD="mysql -h 127.0.0.1 -P 9030 -u root"

echo "1. Creating test database..."
$MYSQL_CMD -e "CREATE DATABASE IF NOT EXISTS test_local;"
$MYSQL_CMD -e "USE test_local;"

echo "2. Creating test table..."
$MYSQL_CMD <<EOF
CREATE TABLE IF NOT EXISTS test_local.test_table (
    id INT,
    name VARCHAR(100),
    age INT,
    created_at DATETIME
) ENGINE=OLAP
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);
EOF

echo "3. Inserting test data..."
$MYSQL_CMD <<EOF
INSERT INTO test_local.test_table VALUES
(1, 'Alice', 25, '2024-01-01 10:00:00'),
(2, 'Bob', 30, '2024-01-02 11:00:00'),
(3, 'Charlie', 35, '2024-01-03 12:00:00');
EOF

echo "4. Querying test data..."
$MYSQL_CMD -e "SELECT * FROM test_local.test_table ORDER BY id;"

echo "5. Checking table distribution..."
$MYSQL_CMD -e "SHOW PARTITIONS FROM test_local.test_table;"

echo ""
echo "========================================"
echo "Test Completed Successfully!"
echo "========================================"
echo ""
echo "Cluster is working properly!"
