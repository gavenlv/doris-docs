-- =====================================================
-- 第08章：数据导入全解
-- 演示 Stream/Broker/Routine/Insert/Flink/Spark/S3 导入方式
-- 所需权限：INSERT_PRIV ON tutorial
-- =====================================================

USE tutorial;

-- =====================================================
-- 1. INSERT 导入（最简单的方式）
-- 适合小批量数据导入
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_insert_table (
    id INT NOT NULL,
    name VARCHAR(50),
    age INT,
    city VARCHAR(50)
) ENGINE=OLAP
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_insert_table VALUES
(1, '张三', 28, '北京'),
(2, '李四', 35, '上海'),
(3, '王五', 30, '广州');

SELECT * FROM demo_insert_table;

INSERT INTO demo_insert_table (id, name, age, city) VALUES
(4, '赵六', 25, '深圳'),
(5, '钱七', 40, '杭州');

SELECT * FROM demo_insert_table ORDER BY id;

CREATE TABLE IF NOT EXISTS demo_insert_source (
    id INT,
    name VARCHAR(50),
    age INT,
    city VARCHAR(50)
) ENGINE=OLAP
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 1
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_insert_source VALUES
(6, '孙八', 32, '成都'),
(7, '周九', 28, '武汉');

INSERT INTO demo_insert_table SELECT * FROM demo_insert_source;

SELECT * FROM demo_insert_table ORDER BY id;

-- =====================================================
-- 2. Stream Load（HTTP流式导入）
-- 适合本地文件、程序导入
-- =====================================================

-- Stream Load 需要通过 HTTP 接口调用，这里演示命令
-- 实际使用时需要在命令行执行：

-- echo '8,测试用户1,25,北京
-- 9,测试用户2,30,上海' | curl --location-trusted -u root: -H "column_separator:," -H "label:stream_load_test_1" -T - http://127.0.0.1:8030/api/tutorial/demo_insert_table/_stream_load

-- 导入 JSON 格式数据：
-- echo '{"id":10,"name":"JSON用户1","age":28,"city":"广州"}
-- {"id":11,"name":"JSON用户2","age":35,"city":"深圳"}' | curl --location-trusted -u root: -H "format:json" -H "strip_outer_array:true" -H "label:stream_load_json_1" -T - http://127.0.0.1:8030/api/tutorial/demo_insert_table/_stream_load

-- =====================================================
-- 3. Broker Load（通过Broker导入外部存储）
-- 适合大规模数据导入，支持HDFS、S3等
-- =====================================================

-- Broker Load 需要先配置 Broker，这里演示语法

-- LOAD LABEL tutorial.broker_load_test_1
-- (
--     DATA INFILE("hdfs://namenode:8020/data/users.csv")
--     INTO TABLE demo_insert_table
--     COLUMNS TERMINATED BY ","
--     (id, name, age, city)
-- )
-- WITH BROKER "broker_name"
-- (
--     "username" = "hdfs_user",
--     "password" = "hdfs_password"
-- );

-- 从 S3 导入：
-- LOAD LABEL tutorial.s3_load_test_1
-- (
--     DATA INFILE("s3://bucket/data/users.csv")
--     INTO TABLE demo_insert_table
--     COLUMNS TERMINATED BY ","
--     (id, name, age, city)
-- )
-- WITH BROKER "broker_name"
-- (
--     "AWS_ENDPOINT" = "s3.amazonaws.com",
--     "AWS_ACCESS_KEY" = "your_access_key",
--     "AWS_SECRET_KEY" = "your_secret_key"
-- );

-- SHOW LOAD WHERE LABEL = 'broker_load_test_1';

-- =====================================================
-- 4. Routine Load（持续导入）
-- 适合从Kafka持续导入数据
-- =====================================================

-- Routine Load 需要Kafka环境，这里演示语法

-- CREATE ROUTINE LOAD tutorial.routine_load_test ON demo_insert_table
-- COLUMNS TERMINATED BY ",",
-- COLUMNS (id, name, age, city)
-- PROPERTIES
-- (
--     "desired_concurrent_number" = "3",
--     "max_batch_interval" = "20"
-- )
-- FROM KAFKA
-- (
--     "kafka_broker_list" = "kafka:9092",
--     "kafka_topic" = "user_topic",
--     "kafka_group_id" = "doris_group"
-- );

-- SHOW ROUTINE LOAD FOR routine_load_test;

-- PAUSE ROUTINE LOAD FOR routine_load_test;

-- RESUME ROUTINE LOAD FOR routine_load_test;

-- STOP ROUTINE LOAD FOR routine_load_test;

-- =====================================================
-- 5. Insert Into Files（从文件导入）
-- =====================================================

-- 从本地文件导入（需要先上传文件）
-- INSERT INTO demo_insert_table FROM FILE('file:///path/to/users.csv')
-- PROPERTIES
-- (
--     "format" = "csv",
--     "column_separator" = ","
-- );

-- =====================================================
-- 6. 外部表导入
-- =====================================================

-- 创建外部表（以MySQL为例）
-- CREATE EXTERNAL TABLE demo_mysql_external (
--     id INT,
--     name VARCHAR(50),
--     age INT,
--     city VARCHAR(50)
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

-- 从外部表导入
-- INSERT INTO demo_insert_table SELECT * FROM demo_mysql_external;

-- =====================================================
-- 7. 导入性能优化参数
-- =====================================================

-- Stream Load 性能参数示例
-- curl --location-trusted -u root: \
-- -H "column_separator:," \
-- -H "line_delimiter:\n" \
-- -H "max_filter_ratio:0.1" \
-- -H "timeout:600" \
-- -H "strict_mode:false" \
-- -H "timezone:Asia/Shanghai" \
-- -H "load_to_single_tablet:true" \
-- -T data.csv \
-- http://127.0.0.1:8030/api/tutorial/demo_insert_table/_stream_load

-- =====================================================
-- 8. 导入错误处理
-- =====================================================

-- 创建允许错误率的导入
-- LOAD LABEL tutorial.error_tolerance_load
-- (
--     DATA INFILE("hdfs://namenode:8020/data/users.csv")
--     INTO TABLE demo_insert_table
--     COLUMNS TERMINATED BY ","
--     (id, name, age, city)
-- )
-- WITH BROKER "broker_name"
-- PROPERTIES
-- (
--     "max_filter_ratio" = "0.1"
-- );

-- 查看导入错误详情
-- SHOW LOAD WARNINGS WHERE LABEL = 'error_tolerance_load';

-- =====================================================
-- 9. 导入事务管理
-- =====================================================

-- 查看导入任务
SHOW LOAD;

-- 取消导入任务
-- CANCEL LOAD WHERE LABEL = 'stream_load_test_1';

-- =====================================================
-- 10. 导入方式对比
-- =====================================================

SELECT 
    'INSERT' AS import_type,
    '小批量数据、测试' AS best_for,
    '简单易用' AS advantage,
    '性能较低' AS disadvantage
UNION ALL
SELECT 
    'Stream Load',
    '本地文件、程序导入',
    '实时性好、支持HTTP',
    '需要编程或curl'
UNION ALL
SELECT 
    'Broker Load',
    '大规模数据、HDFS/S3',
    '支持大文件、断点续传',
    '需要Broker配置'
UNION ALL
SELECT 
    'Routine Load',
    'Kafka持续导入',
    '自动化、持续导入',
    '依赖Kafka'
UNION ALL
SELECT 
    '外部表',
    '异构数据源',
    '直接查询外部数据',
    '性能依赖外部系统';

-- =====================================================
-- 11. 清理演示表
-- =====================================================

DROP TABLE IF EXISTS demo_insert_table;
DROP TABLE IF EXISTS demo_insert_source;
