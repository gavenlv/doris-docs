-- =====================================================
-- 第10章：数据导出与ETL
-- 演示 OUTFILE/Export/外部表/Hive/Iceberg/Hudi
-- 所需权限：SELECT_PRIV ON tutorial
-- =====================================================

USE tutorial;

-- =====================================================
-- 1. SELECT INTO OUTFILE（查询结果导出）
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_export_source (
    id INT NOT NULL,
    name VARCHAR(50),
    age INT,
    city VARCHAR(50),
    salary DECIMAL(10, 2)
) ENGINE=OLAP
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_export_source VALUES
(1, '张三', 28, '北京', 15000.00),
(2, '李四', 35, '上海', 18000.00),
(3, '王五', 30, '广州', 12000.00),
(4, '赵六', 25, '深圳', 16000.00),
(5, '钱七', 40, '杭州', 20000.00);

SELECT * FROM demo_export_source ORDER BY id;

-- 导出为 CSV 文件
-- SELECT * FROM demo_export_source
-- INTO OUTFILE "file:///tmp/export/demo_export_"
-- FORMAT AS CSV
-- PROPERTIES
-- (
--     "column_separator" = ",",
--     "line_delimiter" = "\n",
--     "max_file_size" = "100MB"
-- );

-- 导出为 Parquet 文件
-- SELECT * FROM demo_export_source
-- INTO OUTFILE "hdfs://namenode:8020/export/demo_export_"
-- FORMAT AS PARQUET
-- PROPERTIES
-- (
--     "schema" = "required,int32,id; required,byte_array,name; required,int32,age; required,byte_array,city; required,double,salary"
-- );

-- 导出为 JSON 文件
-- SELECT * FROM demo_export_source
-- INTO OUTFILE "s3://bucket/export/demo_export_"
-- FORMAT AS JSON
-- PROPERTIES
-- (
--     "AWS_ACCESS_KEY" = "your_access_key",
--     "AWS_SECRET_KEY" = "your_secret_key",
--     "AWS_ENDPOINT" = "s3.amazonaws.com"
-- );

-- =====================================================
-- 2. EXPORT 命令（表数据导出）
-- =====================================================

-- 导出整个表
-- EXPORT TABLE demo_export_source TO "hdfs://namenode:8020/export/demo_export/"
-- PROPERTIES
-- (
--     "column_separator" = ",",
--     "line_delimiter" = "\n",
--     "label" = "export_demo_1"
-- )
-- WITH BROKER "broker_name"
-- (
--     "username" = "hdfs_user",
--     "password" = "hdfs_password"
-- );

-- 查看导出任务状态
-- SHOW EXPORT;

-- 查看指定导出任务
-- SHOW EXPORT WHERE LABEL = 'export_demo_1';

-- 导出部分分区
-- EXPORT TABLE demo_export_source PARTITION (p202401, p202402)
-- TO "hdfs://namenode:8020/export/demo_export/"
-- PROPERTIES
-- (
--     "column_separator" = ","
-- );

-- =====================================================
-- 3. 外部表 - Hive
-- =====================================================

-- 创建 Hive Catalog
-- CREATE CATALOG hive_catalog PROPERTIES
-- (
--     "type" = "hms",
--     "hive.metastore.uris" = "thrift://metastore:9083"
-- );

-- 查询 Hive 表
-- SELECT * FROM hive_catalog.db_name.table_name LIMIT 10;

-- 从 Hive 导入数据到 Doris
-- INSERT INTO demo_export_source
-- SELECT * FROM hive_catalog.db_name.source_table;

-- 从 Doris 导出到 Hive
-- INSERT INTO hive_catalog.db_name.target_table
-- SELECT * FROM demo_export_source;

-- =====================================================
-- 4. 外部表 - Iceberg
-- =====================================================

-- 创建 Iceberg Catalog
-- CREATE CATALOG iceberg_catalog PROPERTIES
-- (
--     "type" = "iceberg",
--     "iceberg.catalog.type" = "hms",
--     "hive.metastore.uris" = "thrift://metastore:9083"
-- );

-- 查询 Iceberg 表
-- SELECT * FROM iceberg_catalog.db_name.table_name LIMIT 10;

-- 从 Iceberg 导入数据
-- INSERT INTO demo_export_source
-- SELECT * FROM iceberg_catalog.db_name.source_table;

-- =====================================================
-- 5. 外部表 - Hudi
-- =====================================================

-- 创建 Hudi Catalog
-- CREATE CATALOG hudi_catalog PROPERTIES
-- (
--     "type" = "hms",
--     "hive.metastore.uris" = "thrift://metastore:9083"
-- );

-- 查询 Hudi 表
-- SELECT * FROM hudi_catalog.db_name.table_name LIMIT 10;

-- 从 Hudi 导入数据
-- INSERT INTO demo_export_source
-- SELECT * FROM hudi_catalog.db_name.source_table;

-- =====================================================
-- 6. 外部表 - MySQL
-- =====================================================

-- 创建 MySQL 外部表
-- CREATE EXTERNAL TABLE demo_mysql_external (
--     id INT,
--     name VARCHAR(50),
--     age INT
-- ) ENGINE=MYSQL
-- PROPERTIES
-- (
--     "host" = "mysql_host",
--     "port" = "3306",
--     "user" = "root",
--     "password" = "password",
--     "database" = "source_db",
--     "table" = "source_table"
-- );

-- 查询 MySQL 外部表
-- SELECT * FROM demo_mysql_external LIMIT 10;

-- 从 MySQL 导入数据
-- INSERT INTO demo_export_source (id, name, age, city, salary)
-- SELECT id, name, age, '未知', 0.00 FROM demo_mysql_external;

-- =====================================================
-- 7. 外部表 - PostgreSQL
-- =====================================================

-- 创建 PostgreSQL 外部表
-- CREATE EXTERNAL TABLE demo_pg_external (
--     id INT,
--     name VARCHAR(50)
-- ) ENGINE=ODBC
-- PROPERTIES
-- (
--     "host" = "pg_host",
--     "port" = "5432",
--     "user" = "postgres",
--     "password" = "password",
--     "database" = "source_db",
--     "table" = "source_table",
--     "driver" = "PostgreSQL"
-- );

-- =====================================================
-- 8. 数据同步 - MySQL CDC
-- =====================================================

-- 创建 MySQL CDC 同步任务（需要配置Flink CDC）
-- CREATE ROUTINE LOAD tutorial.mysql_cdc_sync ON demo_export_source
-- COLUMNS TERMINATED BY ",",
-- COLUMNS (id, name, age, city, salary)
-- PROPERTIES
-- (
--     "desired_concurrent_number" = "3"
-- )
-- FROM KAFKA
-- (
--     "kafka_broker_list" = "kafka:9092",
--     "kafka_topic" = "mysql_cdc_topic"
-- );

-- =====================================================
-- 9. ETL 场景示例
-- =====================================================

-- 场景1：数据清洗后导出
-- SELECT 
--     id,
--     UPPER(name) AS name,
--     age,
--     city,
--     ROUND(salary / 10000, 2) AS salary_wan
-- FROM demo_export_source
-- WHERE age >= 25 AND salary > 10000
-- INTO OUTFILE "file:///tmp/export/cleaned_data_"
-- FORMAT AS CSV
-- PROPERTIES
-- (
--     "column_separator" = ","
-- );

-- 场景2：聚合后导出
-- SELECT 
--     city,
--     COUNT(*) AS user_count,
--     AVG(age) AS avg_age,
--     SUM(salary) AS total_salary,
--     AVG(salary) AS avg_salary
-- FROM demo_export_source
-- GROUP BY city
-- INTO OUTFILE "file:///tmp/export/city_stats_"
-- FORMAT AS CSV
-- PROPERTIES
-- (
--     "column_separator" = ","
-- );

-- 场景3：多表 JOIN 后导出
CREATE TABLE IF NOT EXISTS demo_export_orders (
    order_id INT,
    user_id INT,
    amount DECIMAL(10, 2)
) ENGINE=OLAP
DUPLICATE KEY(order_id)
DISTRIBUTED BY HASH(order_id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_export_orders VALUES
(1, 1, 500.00),
(2, 2, 800.00),
(3, 1, 300.00),
(4, 3, 600.00);

SELECT 
    u.id,
    u.name,
    u.city,
    COUNT(o.order_id) AS order_count,
    SUM(o.amount) AS total_amount
FROM demo_export_source u
LEFT JOIN demo_export_orders o ON u.id = o.user_id
GROUP BY u.id, u.name, u.city
ORDER BY total_amount DESC;

-- =====================================================
-- 10. 导出格式对比
-- =====================================================

SELECT 
    'CSV' AS format,
    '通用文本格式' AS description,
    '兼容性好、可读性强' AS advantage,
    '文件较大、无压缩' AS disadvantage
UNION ALL
SELECT 
    'Parquet',
    '列式存储格式',
    '压缩率高、查询快',
    '不可直接阅读'
UNION ALL
SELECT 
    'ORC',
    '列式存储格式',
    '压缩率高、支持索引',
    'Hive生态为主'
UNION ALL
SELECT 
    'JSON',
    '结构化文本格式',
    '可读性强、灵活',
    '文件较大、解析慢';

-- =====================================================
-- 11. 清理演示表
-- =====================================================

DROP TABLE IF EXISTS demo_export_source;
DROP TABLE IF EXISTS demo_export_orders;
