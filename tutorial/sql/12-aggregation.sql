-- =====================================================
-- 第12章：聚合函数详解
-- 演示基础聚合、HLL/Bitmap/Percentile/Retention/自定义UDAF
-- 所需权限：SELECT_PRIV ON tutorial
-- =====================================================

USE tutorial;

-- =====================================================
-- 1. 准备测试数据
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_agg_orders (
    order_id INT NOT NULL,
    user_id INT,
    product_id INT,
    category VARCHAR(50),
    amount DECIMAL(10, 2),
    quantity INT,
    order_time DATETIME,
    city VARCHAR(50)
) ENGINE=OLAP
DUPLICATE KEY(order_id)
DISTRIBUTED BY HASH(order_id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_agg_orders VALUES
(1, 1001, 101, '电子产品', 5999.00, 1, '2024-01-01 10:00:00', '北京'),
(2, 1001, 102, '电子产品', 12999.00, 1, '2024-01-02 11:00:00', '北京'),
(3, 1002, 103, '服装', 599.00, 2, '2024-01-01 12:00:00', '上海'),
(4, 1002, 104, '食品', 99.00, 5, '2024-01-03 13:00:00', '上海'),
(5, 1003, 101, '电子产品', 5999.00, 1, '2024-01-01 14:00:00', '广州'),
(6, 1003, 105, '家居', 1299.00, 1, '2024-01-02 15:00:00', '广州'),
(7, 1001, 106, '服装', 399.00, 1, '2024-01-03 16:00:00', '北京'),
(8, 1004, 102, '电子产品', 12999.00, 1, '2024-01-01 17:00:00', '深圳');

-- =====================================================
-- 2. 基础聚合函数
-- =====================================================

SELECT 
    COUNT(*) AS total_orders,
    COUNT(DISTINCT user_id) AS unique_users,
    SUM(amount) AS total_amount,
    AVG(amount) AS avg_amount,
    MAX(amount) AS max_amount,
    MIN(amount) AS min_amount,
    SUM(quantity) AS total_quantity
FROM demo_agg_orders;

-- =====================================================
-- 3. GROUP BY 分组聚合
-- =====================================================

SELECT 
    category,
    COUNT(*) AS order_count,
    SUM(amount) AS total_amount,
    AVG(amount) AS avg_amount,
    MAX(amount) AS max_amount,
    MIN(amount) AS min_amount
FROM demo_agg_orders
GROUP BY category
ORDER BY total_amount DESC;

SELECT 
    city,
    COUNT(*) AS order_count,
    COUNT(DISTINCT user_id) AS unique_users,
    SUM(amount) AS total_amount
FROM demo_agg_orders
GROUP BY city
ORDER BY total_amount DESC;

-- =====================================================
-- 4. GROUPING SETS（多维分组）
-- =====================================================

SELECT 
    city,
    category,
    COUNT(*) AS order_count,
    SUM(amount) AS total_amount
FROM demo_agg_orders
GROUP BY GROUPING SETS (
    (city, category),
    (city),
    (category),
    ()
)
ORDER BY city, category;

-- =====================================================
-- 5. ROLLUP（上卷聚合）
-- =====================================================

SELECT 
    city,
    category,
    COUNT(*) AS order_count,
    SUM(amount) AS total_amount
FROM demo_agg_orders
GROUP BY ROLLUP (city, category)
ORDER BY city, category;

-- =====================================================
-- 6. CUBE（立方体聚合）
-- =====================================================

SELECT 
    city,
    category,
    COUNT(*) AS order_count,
    SUM(amount) AS total_amount
FROM demo_agg_orders
GROUP BY CUBE (city, category)
ORDER BY city, category;

-- =====================================================
-- 7. HAVING 子句
-- =====================================================

SELECT 
    user_id,
    COUNT(*) AS order_count,
    SUM(amount) AS total_amount
FROM demo_agg_orders
GROUP BY user_id
HAVING COUNT(*) >= 2
ORDER BY total_amount DESC;

-- =====================================================
-- 8. Bitmap 精确去重
-- =====================================================

SELECT 
    city,
    BITMAP_UNION_COUNT(TO_BITMAP(user_id)) AS exact_uv
FROM demo_agg_orders
GROUP BY city
ORDER BY city;

CREATE TABLE IF NOT EXISTS demo_bitmap_agg (
    date_key DATE,
    city VARCHAR(50),
    user_bitmap BITMAP BITMAP_UNION
) ENGINE=OLAP
AGGREGATE KEY(date_key, city)
DISTRIBUTED BY HASH(date_key, city) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_bitmap_agg VALUES
('2024-01-01', '北京', to_bitmap(1001)),
('2024-01-01', '北京', to_bitmap(1002)),
('2024-01-01', '北京', to_bitmap(1003)),
('2024-01-01', '上海', to_bitmap(1001)),
('2024-01-01', '上海', to_bitmap(1004));

SELECT 
    date_key,
    city,
    BITMAP_UNION_COUNT(user_bitmap) AS uv
FROM demo_bitmap_agg
GROUP BY date_key, city
ORDER BY date_key, city;

-- =====================================================
-- 9. HLL 近似去重
-- =====================================================

SELECT 
    city,
    NDV(user_id) AS approx_uv,
    HLL_UNION_AGG(HLL_HASH(user_id)) AS hll_uv
FROM demo_agg_orders
GROUP BY city
ORDER BY city;

CREATE TABLE IF NOT EXISTS demo_hll_agg (
    date_key DATE,
    city VARCHAR(50),
    user_hll HLL HLL_UNION
) ENGINE=OLAP
AGGREGATE KEY(date_key, city)
DISTRIBUTED BY HASH(date_key, city) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_hll_agg VALUES
('2024-01-01', '北京', hll_hash('1001')),
('2024-01-01', '北京', hll_hash('1002')),
('2024-01-01', '北京', hll_hash('1003')),
('2024-01-01', '上海', hll_hash('1001')),
('2024-01-01', '上海', hll_hash('1004'));

SELECT 
    date_key,
    city,
    HLL_UNION_AGG(user_hll) AS approx_uv
FROM demo_hll_agg
GROUP BY date_key, city
ORDER BY date_key, city;

-- =====================================================
-- 10. Percentile 近似百分位数
-- =====================================================

SELECT 
    category,
    PERCENTILE(amount, 0.5) AS median_amount,
    PERCENTILE(amount, 0.9) AS p90_amount,
    PERCENTILE(amount, 0.95) AS p95_amount,
    PERCENTILE(amount, 0.99) AS p99_amount
FROM demo_agg_orders
GROUP BY category
ORDER BY category;

-- =====================================================
-- 11. 其他聚合函数
-- =====================================================

SELECT 
    category,
    GROUP_CONCAT(product_id, ',') AS product_ids,
    COUNT(DISTINCT product_id) AS unique_products
FROM demo_agg_orders
GROUP BY category
ORDER BY category;

SELECT 
    city,
    APPROX_COUNT_DISTINCT(user_id) AS approx_uv,
    COUNT(DISTINCT user_id) AS exact_uv
FROM demo_agg_orders
GROUP BY city
ORDER BY city;

-- =====================================================
-- 12. 留存分析
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_retention_events (
    user_id INT,
    event_date DATE,
    event_type VARCHAR(20)
) ENGINE=OLAP
DUPLICATE KEY(user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_retention_events VALUES
(1001, '2024-01-01', 'login'),
(1001, '2024-01-02', 'login'),
(1001, '2024-01-03', 'login'),
(1002, '2024-01-01', 'login'),
(1002, '2024-01-02', 'login'),
(1003, '2024-01-01', 'login'),
(1003, '2024-01-03', 'login'),
(1004, '2024-01-01', 'login');

SELECT 
    event_date,
    COUNT(DISTINCT user_id) AS active_users,
    RETENTION(
        user_id IN (SELECT user_id FROM demo_retention_events WHERE event_date = '2024-01-01'),
        user_id IN (SELECT user_id FROM demo_retention_events WHERE event_date = '2024-01-02')
    ) AS retention_day1
FROM demo_retention_events
GROUP BY event_date
ORDER BY event_date;

-- =====================================================
-- 13. 序列函数
-- =====================================================

SELECT 
    user_id,
    event_date,
    DENSE_RANK() OVER (PARTITION BY user_id ORDER BY event_date) AS visit_rank
FROM demo_retention_events
ORDER BY user_id, event_date;

-- =====================================================
-- 14. 聚合函数性能对比
-- =====================================================

SELECT 
    'COUNT(DISTINCT)' AS method,
    '精确去重' AS accuracy,
    '高' AS performance_impact,
    '数据量小时使用' AS recommendation
UNION ALL
SELECT 
    'BITMAP',
    '精确去重',
    '低',
    '用户ID等整数类型，推荐'
UNION ALL
SELECT 
    'HLL',
    '近似去重',
    '极低',
    '大数据量、允许误差1%左右'
UNION ALL
SELECT 
    'NDV',
    '近似去重',
    '极低',
    '快速估算，精度略低';

-- =====================================================
-- 15. 清理演示表
-- =====================================================

DROP TABLE IF EXISTS demo_agg_orders;
DROP TABLE IF EXISTS demo_bitmap_agg;
DROP TABLE IF EXISTS demo_hll_agg;
DROP TABLE IF EXISTS demo_retention_events;
