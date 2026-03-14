-- ========================================
-- Doris 本地环境快速入门 SQL 示例
-- ========================================

-- 1. 创建测试数据库
CREATE DATABASE IF NOT EXISTS demo;
USE demo;

-- 2. 创建简单的维度表
CREATE TABLE IF NOT EXISTS dim_users (
    user_id INT,
    username VARCHAR(50),
    email VARCHAR(100),
    age INT,
    gender VARCHAR(10),
    city VARCHAR(50),
    register_date DATE
) ENGINE=OLAP
DUPLICATE KEY(user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);

-- 3. 创建事实表
CREATE TABLE IF NOT EXISTS fact_orders (
    order_id BIGINT,
    user_id INT,
    product_id INT,
    order_date DATE,
    order_time DATETIME,
    quantity INT,
    amount DECIMAL(10, 2),
    discount DECIMAL(10, 2),
    final_amount DECIMAL(10, 2),
    status VARCHAR(20)
) ENGINE=OLAP
DUPLICATE KEY(order_id)
PARTITION BY RANGE(order_date) (
    PARTITION p202401 VALUES LESS THAN ('2024-02-01'),
    PARTITION p202402 VALUES LESS THAN ('2024-03-01'),
    PARTITION p202403 VALUES LESS THAN ('2024-04-01'),
    PARTITION p202404 VALUES LESS THAN ('2024-05-01')
)
DISTRIBUTED BY HASH(order_id) BUCKETS 6
PROPERTIES (
    "replication_num" = "1"
);

-- 4. 插入测试数据
INSERT INTO dim_users VALUES
(1, 'alice', 'alice@example.com', 25, 'F', 'Beijing', '2023-01-15'),
(2, 'bob', 'bob@example.com', 30, 'M', 'Shanghai', '2023-02-20'),
(3, 'charlie', 'charlie@example.com', 35, 'M', 'Guangzhou', '2023-03-25'),
(4, 'diana', 'diana@example.com', 28, 'F', 'Shenzhen', '2023-04-30'),
(5, 'eve', 'eve@example.com', 32, 'F', 'Hangzhou', '2023-05-10');

INSERT INTO fact_orders VALUES
(1001, 1, 101, '2024-01-05', '2024-01-05 10:30:00', 2, 199.99, 10.00, 189.99, 'completed'),
(1002, 2, 102, '2024-01-10', '2024-01-10 14:20:00', 1, 299.99, 0.00, 299.99, 'completed'),
(1003, 1, 103, '2024-01-15', '2024-01-15 09:15:00', 3, 149.99, 15.00, 134.99, 'completed'),
(1004, 3, 101, '2024-02-01', '2024-02-01 16:45:00', 1, 199.99, 0.00, 199.99, 'completed'),
(1005, 4, 104, '2024-02-05', '2024-02-05 11:00:00', 2, 399.99, 40.00, 359.99, 'completed'),
(1006, 5, 102, '2024-02-10', '2024-02-10 13:30:00', 1, 299.99, 20.00, 279.99, 'completed'),
(1007, 2, 103, '2024-03-01', '2024-03-01 10:00:00', 4, 149.99, 0.00, 149.99, 'completed'),
(1008, 1, 105, '2024-03-05', '2024-03-05 15:20:00', 2, 499.99, 50.00, 449.99, 'completed'),
(1009, 3, 101, '2024-03-10', '2024-03-10 12:10:00', 1, 199.99, 10.00, 189.99, 'pending'),
(1010, 4, 102, '2024-03-15', '2024-03-15 14:50:00', 3, 299.99, 30.00, 269.99, 'completed');

-- 5. 查询示例

-- 简单查询
SELECT * FROM dim_users LIMIT 5;

SELECT * FROM fact_orders WHERE order_date = '2024-01-05';

-- 聚合查询
SELECT 
    order_date,
    COUNT(*) as order_count,
    SUM(final_amount) as total_amount,
    AVG(final_amount) as avg_amount
FROM fact_orders
GROUP BY order_date
ORDER BY order_date;

-- 关联查询（星型模型）
SELECT 
    d.username,
    d.city,
    COUNT(o.order_id) as order_count,
    SUM(o.final_amount) as total_amount
FROM dim_users d
JOIN fact_orders o ON d.user_id = o.user_id
GROUP BY d.username, d.city
ORDER BY total_amount DESC;

-- 时间范围查询
SELECT 
    DATE_FORMAT(order_time, '%Y-%m') as month,
    COUNT(*) as order_count,
    SUM(final_amount) as total_revenue
FROM fact_orders
WHERE order_time BETWEEN '2024-01-01' AND '2024-03-31'
GROUP BY DATE_FORMAT(order_time, '%Y-%m')
ORDER BY month;

-- 分区查询
SHOW PARTITIONS FROM fact_orders;

SELECT * FROM fact_orders PARTITION(p202401);

-- 6. 性能测试查询

-- 创建大表（用于性能测试）
CREATE TABLE IF NOT EXISTS perf_test (
    id BIGINT,
    user_id INT,
    event_date DATE,
    event_time DATETIME,
    event_type VARCHAR(20),
    value DECIMAL(10, 2)
) ENGINE=OLAP
DUPLICATE KEY(id)
PARTITION BY RANGE(event_date) (
    PARTITION p202401 VALUES LESS THAN ('2024-02-01'),
    PARTITION p202402 VALUES LESS THAN ('2024-03-01'),
    PARTITION p202403 VALUES LESS THAN ('2024-04-01')
)
DISTRIBUTED BY HASH(id) BUCKETS 12
PROPERTIES (
    "replication_num" = "1"
);

-- 插入大量测试数据（使用循环）
-- 注意：这个查询会生成 100万 行数据，可能需要一些时间
INSERT INTO perf_test 
WITH RECURSIVE numbers AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM numbers WHERE n < 1000000
)
SELECT 
    n AS id,
    (n % 10000) AS user_id,
    DATE_ADD('2024-01-01', INTERVAL (n % 90) DAY) AS event_date,
    DATE_ADD('2024-01-01 00:00:00', INTERVAL n SECOND) AS event_time,
    ELT((n % 5) + 1, 'click', 'view', 'purchase', 'add_cart', 'favorite') AS event_type,
    (RAND() * 1000) AS value
FROM numbers;

-- 性能测试查询 1: 简单聚合
SELECT 
    event_date,
    COUNT(*) as event_count,
    AVG(value) as avg_value
FROM perf_test
GROUP BY event_date
ORDER BY event_date
LIMIT 10;

-- 性能测试查询 2: 关联聚合
SELECT 
    user_id,
    COUNT(*) as event_count,
    SUM(value) as total_value
FROM perf_test
WHERE event_date BETWEEN '2024-01-01' AND '2024-01-31'
GROUP BY user_id
ORDER BY total_value DESC
LIMIT 10;

-- 性能测试查询 3: 复杂聚合
SELECT 
    event_type,
    DATE_FORMAT(event_time, '%Y-%m-%d') as day,
    COUNT(*) as event_count,
    AVG(value) as avg_value,
    MIN(value) as min_value,
    MAX(value) as max_value
FROM perf_test
WHERE event_date BETWEEN '2024-01-01' AND '2024-01-31'
GROUP BY event_type, DATE_FORMAT(event_time, '%Y-%m-%d')
ORDER BY event_type, day;

-- 7. 查看表状态
SHOW TABLE STATUS;

-- 查看表结构
SHOW CREATE TABLE fact_orders;

-- 查看表分区
SHOW PARTITIONS FROM fact_orders;

-- 查看表分布
SHOW DATA FROM fact_orders;

-- 8. 优化建议

-- 查看查询计划
EXPLAIN SELECT * FROM fact_orders WHERE user_id = 1;

-- 查看查询 profile
SET enable_profile = true;
SELECT * FROM fact_orders WHERE user_id = 1;
SHOW QUERY PROFILE '/xxx';  -- 使用实际的 Profile ID

-- 收集统计信息（提升查询性能）
ANALYZE TABLE dim_users;
ANALYZE TABLE fact_orders;

-- 9. 管理命令

-- 查看后端节点状态
SHOW BACKENDS;

-- 查看前端节点状态
SHOW FRONTENDS;

-- 查看当前连接
SHOW PROCESSLIST;

-- 查看慢查询
SHOW RUNNING QUERIES;

-- 查看磁盘使用
SHOW DISK;

-- 10. 数据导入示例

-- Stream Load 示例（大数据量导入）
-- 假设有一个 CSV 文件 data.csv，内容如下：
-- user_id,username,email,age,gender,city,register_date
-- 6,frank,frank@example.com,40,M,Nanjing,2023-06-15
-- 7,grace,grace@example.com,27,F,Chengdu,2023-07-20

-- 使用 curl 导入
-- curl --location-trusted -u root: \
--     -H "column_separator:," \
--     -H "columns:user_id,username,email,age,gender,city,register_date" \
--     -T data.csv \
--     http://localhost:8030/api/demo/dim_users/_stream_load

-- 查看导入任务
SHOW LOAD ORDER BY CreateTime DESC LIMIT 5;
