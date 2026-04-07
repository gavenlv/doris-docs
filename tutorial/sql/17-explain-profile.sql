-- =====================================================
-- 第17章：执行计划与性能诊断
-- 演示 EXPLAIN/Profile解读、算子性能、资源消耗分析
-- 所需权限：SELECT_PRIV ON tutorial
-- =====================================================

USE tutorial;

-- =====================================================
-- 1. 准备测试数据
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_profile_orders (
    order_id INT NOT NULL,
    user_id INT,
    product_id INT,
    amount DECIMAL(10, 2),
    order_time DATETIME,
    city VARCHAR(50),
    status TINYINT
) ENGINE=OLAP
DUPLICATE KEY(order_id)
PARTITION BY RANGE(order_time) ()
DISTRIBUTED BY HASH(order_id) BUCKETS 5
PROPERTIES (
    "replication_num" = "1",
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-7",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p"
);

INSERT INTO demo_profile_orders VALUES
(1, 1001, 101, 500.00, '2024-01-01 10:00:00', '北京', 1),
(2, 1001, 102, 800.00, '2024-01-01 11:00:00', '北京', 1),
(3, 1002, 103, 300.00, '2024-01-02 10:00:00', '上海', 1),
(4, 1002, 101, 500.00, '2024-01-02 11:00:00', '上海', 0),
(5, 1003, 104, 600.00, '2024-01-03 10:00:00', '广州', 1),
(6, 1003, 102, 800.00, '2024-01-03 11:00:00', '广州', 1),
(7, 1004, 105, 200.00, '2024-01-01 12:00:00', '深圳', 1),
(8, 1004, 101, 500.00, '2024-01-02 12:00:00', '深圳', 1);

-- =====================================================
-- 2. EXPLAIN 基础用法
-- =====================================================

EXPLAIN SELECT * FROM demo_profile_orders WHERE city = '北京';

EXPLAIN VERBOSE SELECT * FROM demo_profile_orders WHERE city = '北京';

EXPLAIN COSTS SELECT * FROM demo_profile_orders WHERE city = '北京';

-- =====================================================
-- 3. 查看执行计划各个级别
-- =====================================================

EXPLAIN SELECT 
    city,
    COUNT(*) AS order_count,
    SUM(amount) AS total_amount
FROM demo_profile_orders
WHERE order_time >= '2024-01-01' AND order_time < '2024-01-03'
GROUP BY city
ORDER BY total_amount DESC;

-- =====================================================
-- 4. Profile 开启与分析
-- =====================================================

SET enable_profile = true;

SELECT 
    city,
    COUNT(*) AS order_count,
    SUM(amount) AS total_amount
FROM demo_profile_orders
WHERE order_time >= '2024-01-01' AND order_time < '2024-01-03'
GROUP BY city
ORDER BY total_amount DESC;

SHOW QUERY PROFILE;

-- 查看最近一次查询的 Profile
-- SHOW QUERY PROFILE '<query_id>';

-- =====================================================
-- 5. 执行计划算子解读
-- =====================================================

EXPLAIN SELECT 
    o.city,
    COUNT(*) AS cnt
FROM demo_profile_orders o
WHERE o.status = 1
GROUP BY o.city
ORDER BY cnt DESC
LIMIT 10;

-- 算子说明：
-- 1. OLAP_SCAN_NODE: 扫描表数据
-- 2. AGGREGATION_NODE: 聚合操作
-- 3. SORT_NODE: 排序操作
-- 4. LIMIT_NODE: LIMIT 操作

-- =====================================================
-- 6. Join 执行计划分析
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_profile_users (
    user_id INT NOT NULL,
    username VARCHAR(50),
    city VARCHAR(50)
) ENGINE=OLAP
DUPLICATE KEY(user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_profile_users VALUES
(1001, '张三', '北京'),
(1002, '李四', '上海'),
(1003, '王五', '广州'),
(1004, '赵六', '深圳');

EXPLAIN SELECT 
    u.username,
    o.order_id,
    o.amount
FROM demo_profile_users u
JOIN demo_profile_orders o ON u.user_id = o.user_id
WHERE o.status = 1;

-- =====================================================
-- 7. 分区裁剪分析
-- =====================================================

EXPLAIN SELECT * FROM demo_profile_orders 
WHERE order_time >= '2024-01-02' AND order_time < '2024-01-03';

-- =====================================================
-- 8. 索引使用分析
-- =====================================================

CREATE INDEX idx_city ON demo_profile_orders(city) USING BITMAP;

SHOW INDEX FROM demo_profile_orders;

EXPLAIN SELECT * FROM demo_profile_orders WHERE city = '北京';

-- =====================================================
-- 9. 聚合查询分析
-- =====================================================

EXPLAIN SELECT 
    DATE(order_time) AS order_date,
    city,
    COUNT(*) AS order_count,
    SUM(amount) AS total_amount,
    AVG(amount) AS avg_amount
FROM demo_profile_orders
GROUP BY DATE(order_time), city
ORDER BY order_date, total_amount DESC;

-- =====================================================
-- 10. 子查询执行计划
-- =====================================================

EXPLAIN SELECT * FROM demo_profile_users 
WHERE user_id IN (SELECT user_id FROM demo_profile_orders WHERE status = 1);

EXPLAIN SELECT 
    u.username,
    (SELECT COUNT(*) FROM demo_profile_orders o WHERE o.user_id = u.user_id) AS order_count
FROM demo_profile_users u;

-- =====================================================
-- 11. 窗口函数执行计划
-- =====================================================

EXPLAIN SELECT 
    user_id,
    order_id,
    amount,
    ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY order_time) AS row_num,
    SUM(amount) OVER (PARTITION BY user_id ORDER BY order_time) AS running_total
FROM demo_profile_orders;

-- =====================================================
-- 12. 性能问题诊断
-- =====================================================

-- 场景1：全表扫描
EXPLAIN SELECT * FROM demo_profile_orders WHERE amount > 500;

-- 场景2：数据倾斜
EXPLAIN SELECT city, COUNT(*) FROM demo_profile_orders GROUP BY city;

-- 场景3：大表Join
EXPLAIN SELECT 
    u.username,
    COUNT(*) AS order_count
FROM demo_profile_users u
LEFT JOIN demo_profile_orders o ON u.user_id = o.user_id
GROUP BY u.username;

-- =====================================================
-- 13. 查询性能优化建议
-- =====================================================

SELECT 
    '分区裁剪' AS optimization,
    '查询条件包含分区列' AS method,
    '减少扫描数据量' AS benefit
UNION ALL
SELECT 
    '索引使用',
    '为高频查询列创建索引',
    '加速数据过滤'
UNION ALL
SELECT 
    'Colocate Join',
    '频繁Join的表使用相同分布',
    '减少网络传输'
UNION ALL
SELECT 
    '物化视图',
    '预计算复杂聚合',
    '加速聚合查询'
UNION ALL
SELECT 
    '合理分桶',
    '根据数据量和查询模式选择分桶数',
    '提高并发性能';

-- =====================================================
-- 14. Profile 关键指标
-- =====================================================

-- 关键指标说明：
-- 1. TotalTime: 查询总耗时
-- 2. ScanTime: 扫描数据耗时
-- 3. OutputRows: 输出行数
-- 4. OutputBytes: 输出数据量
-- 5. MemoryUsage: 内存使用量
-- 6. CpuTime: CPU时间

-- =====================================================
-- 15. 清理演示表
-- =====================================================

SET enable_profile = false;

DROP TABLE IF EXISTS demo_profile_orders;
DROP TABLE IF EXISTS demo_profile_users;
