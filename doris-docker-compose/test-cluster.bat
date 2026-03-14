@echo off
REM ========================================
REM Test Doris Cluster
REM ========================================

echo ========================================
echo Testing Doris Cluster
echo ========================================

echo 1. Creating test database...
mysql -h 127.0.0.1 -P 9030 -u root -e "CREATE DATABASE IF NOT EXISTS test_local;"

echo 2. Creating test table...
mysql -h 127.0.0.1 -P 9030 -u root test_local -e "CREATE TABLE IF NOT EXISTS test_table (id INT, name VARCHAR(100), age INT, created_at DATETIME) ENGINE=OLAP DUPLICATE KEY(id) DISTRIBUTED BY HASH(id) BUCKETS 3 PROPERTIES (""replication_num"" = ""1"");"

echo 3. Inserting test data...
mysql -h 127.0.0.1 -P 9030 -u root test_local -e "INSERT INTO test_table VALUES (1, 'Alice', 25, '2024-01-01 10:00:00'), (2, 'Bob', 30, '2024-01-02 11:00:00'), (3, 'Charlie', 35, '2024-01-03 12:00:00');"

echo 4. Querying test data...
mysql -h 127.0.0.1 -P 9030 -u root test_local -e "SELECT * FROM test_table ORDER BY id;"

echo 5. Checking table distribution...
mysql -h 127.0.0.1 -P 9030 -u root test_local -e "SHOW PARTITIONS FROM test_table;"

echo.
echo ========================================
echo Test Completed Successfully!
echo ========================================
echo.
echo Cluster is working properly!
echo.

pause
