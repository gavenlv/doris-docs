-- =====================================================
-- 第14章：物化视图详解
-- 演示异步MV、刷新策略、查询重写、与Rollup对比
-- 所需权限：CREATE_PRIV ON tutorial
-- =====================================================

USE tutorial;

-- =====================================================
-- 1. 准备测试数据
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_mv_sales (
    sale_id INT NOT NULL,
    product_id INT,
    product_name VARCHAR(100),
    category VARCHAR(50),
    sale_amount DECIMAL(10, 2),
    quantity INT,
    sale_time DATETIME,
    city VARCHAR(50)
) ENGINE=OLAP
DUPLICATE KEY(sale_id)
PARTITION BY RANGE(sale_time) ()
DISTRIBUTED BY HASH(sale_id) BUCKETS 5
PROPERTIES (
    "replication_num" = "1",
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-7",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p"
);

INSERT INTO demo_mv_sales VALUES
(1, 101, 'iPhone', '电子产品', 5999.00, 1, '2024-01-01 10:00:00', '北京'),
(2, 102, 'MacBook', '电子产品', 12999.00, 1, '2024-01-01 11:00:00', '上海'),
(3, 103, 'T恤', '服装', 199.00, 2, '2024-01-01 12:00:00', '广州'),
(4, 101, 'iPhone', '电子产品', 5999.00, 1, '2024-01-02 10:00:00', '北京'),
(5, 104, '零食', '食品', 99.00, 5, '2024-01-02 11:00:00', '深圳'),
(6, 102, 'MacBook', '电子产品', 12999.00, 1, '2024-01-02 12:00:00', '上海'),
(7, 105, '沙发', '家居', 2999.00, 1, '2024-01-03 10:00:00', '杭州'),
(8, 103, 'T恤', '服装', 199.00, 3, '2024-01-03 11:00:00', '北京');

-- =====================================================
-- 2. 创建同步物化视图（Rollup）
-- =====================================================

ALTER TABLE demo_mv_sales ADD ROLLUP rollup_category (
    category,
    SUM(sale_amount),
    SUM(quantity),
    COUNT(*)
);

SHOW ALTER TABLE ROLLUP FROM demo_mv_sales;

DESC demo_mv_sales ALL;

-- =====================================================
-- 3. 创建异步物化视图
-- =====================================================

CREATE MATERIALIZED VIEW demo_mv_category_agg
BUILD IMMEDIATE REFRESH COMPLETE ON MANUAL
PARTITION BY DATE(sale_time)
DISTRIBUTED BY HASH(category) BUCKETS 3
PROPERTIES (
    "replication_num" = "1",
    "grace_period" = "3600",
    "excluded_trigger_tables" = ""
)
AS
SELECT 
    DATE(sale_time) AS sale_date,
    category,
    SUM(sale_amount) AS total_amount,
    SUM(quantity) AS total_quantity,
    COUNT(*) AS sale_count
FROM demo_mv_sales
GROUP BY DATE(sale_time), category;

SHOW MATERIALIZED VIEWS;

SHOW CREATE MATERIALIZED VIEW demo_mv_category_agg;

DESC demo_mv_category_agg;

SELECT * FROM demo_mv_category_agg ORDER BY sale_date, category;

-- =====================================================
-- 4. 物化视图刷新策略
-- =====================================================

-- 手动刷新
REFRESH MATERIALIZED VIEW demo_mv_category_agg COMPLETE;

-- 查看刷新任务
SHOW MATERIALIZED VIEW TASK ON demo_mv_category_agg;

-- 创建定时刷新的物化视图
CREATE MATERIALIZED VIEW demo_mv_daily_city
BUILD IMMEDIATE REFRESH COMPLETE ON SCHEDULE EVERY 1 DAY STARTS '2024-01-01 02:00:00'
DISTRIBUTED BY HASH(sale_date) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
)
AS
SELECT 
    DATE(sale_time) AS sale_date,
    city,
    SUM(sale_amount) AS total_amount,
    COUNT(DISTINCT product_id) AS product_count
FROM demo_mv_sales
GROUP BY DATE(sale_time), city;

SHOW CREATE MATERIALIZED VIEW demo_mv_daily_city;

-- =====================================================
-- 5. 物化视图查询重写
-- =====================================================

INSERT INTO demo_mv_sales VALUES
(9, 106, '耳机', '电子产品', 599.00, 2, '2024-01-03 12:00:00', '上海');

REFRESH MATERIALIZED VIEW demo_mv_category_agg COMPLETE;

SELECT 
    category,
    SUM(sale_amount) AS total_amount
FROM demo_mv_sales
WHERE DATE(sale_time) = '2024-01-03'
GROUP BY category;

EXPLAIN SELECT 
    category,
    SUM(sale_amount) AS total_amount
FROM demo_mv_sales
WHERE DATE(sale_time) = '2024-01-03'
GROUP BY category;

-- =====================================================
-- 6. 分区物化视图
-- =====================================================

CREATE MATERIALIZED VIEW demo_mv_partitioned
BUILD IMMEDIATE REFRESH AUTO ON MANUAL
PARTITION BY DATE(sale_time)
DISTRIBUTED BY HASH(product_id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1",
    "partition_ttl_number" = "30"
)
AS
SELECT 
    sale_time,
    product_id,
    product_name,
    SUM(sale_amount) AS total_amount,
    SUM(quantity) AS total_quantity
FROM demo_mv_sales
GROUP BY sale_time, product_id, product_name;

SHOW MATERIALIZED VIEW demo_mv_partitioned;

-- =====================================================
-- 7. 物化视图管理
-- =====================================================

-- 暂停物化视图
ALTER MATERIALIZED VIEW demo_mv_category_agg SET ACTIVE = FALSE;

SHOW MATERIALIZED VIEW demo_mv_category_agg;

-- 恢复物化视图
ALTER MATERIALIZED VIEW demo_mv_category_agg SET ACTIVE = TRUE;

SHOW MATERIALIZED VIEW demo_mv_category_agg;

-- 修改刷新策略
ALTER MATERIALIZED VIEW demo_mv_category_agg SET REFRESH COMPLETE ON SCHEDULE EVERY 6 HOUR;

SHOW CREATE MATERIALIZED VIEW demo_mv_category_agg;

-- =====================================================
-- 8. 物化视图与 Rollup 对比
-- =====================================================

SELECT 
    'Rollup' AS type,
    '同步更新' AS update_mode,
    '基表数据变化立即生效' AS characteristic,
    '简单聚合场景' AS best_for,
    '功能相对简单' AS limitation
UNION ALL
SELECT 
    '异步物化视图',
    '异步更新',
    '可定时刷新，支持复杂查询',
    '复杂聚合、多表Join',
    '数据有延迟'
UNION ALL
SELECT 
    '同步物化视图',
    '同步更新',
    '基表数据变化立即生效',
    '实时聚合场景',
    '仅支持单表聚合';

-- =====================================================
-- 9. 物化视图使用场景
-- =====================================================

-- 场景1：预计算复杂聚合
CREATE MATERIALIZED VIEW demo_mv_product_rank
BUILD IMMEDIATE REFRESH COMPLETE ON MANUAL
DISTRIBUTED BY HASH(category) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
)
AS
SELECT 
    category,
    product_name,
    SUM(sale_amount) AS total_amount,
    RANK() OVER (PARTITION BY category ORDER BY SUM(sale_amount) DESC) AS amount_rank
FROM demo_mv_sales
GROUP BY category, product_name;

SELECT * FROM demo_mv_product_rank ORDER BY category, amount_rank;

-- 场景2：宽表预关联
CREATE TABLE IF NOT EXISTS demo_mv_dim_product (
    product_id INT,
    product_name VARCHAR(100),
    category VARCHAR(50),
    brand VARCHAR(50)
) ENGINE=OLAP
DUPLICATE KEY(product_id)
DISTRIBUTED BY HASH(product_id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_mv_dim_product VALUES
(101, 'iPhone', '电子产品', 'Apple'),
(102, 'MacBook', '电子产品', 'Apple'),
(103, 'T恤', '服装', 'Nike'),
(104, '零食', '食品', '三只松鼠'),
(105, '沙发', '家居', '宜家'),
(106, '耳机', '电子产品', 'Sony');

CREATE MATERIALIZED VIEW demo_mv_sales_with_brand
BUILD IMMEDIATE REFRESH COMPLETE ON MANUAL
DISTRIBUTED BY HASH(product_id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
)
AS
SELECT 
    s.sale_id,
    s.product_id,
    s.product_name,
    d.brand,
    s.sale_amount,
    s.sale_time
FROM demo_mv_sales s
LEFT JOIN demo_mv_dim_product d ON s.product_id = d.product_id;

SELECT * FROM demo_mv_sales_with_brand LIMIT 5;

-- =====================================================
-- 10. 清理演示表和物化视图
-- =====================================================

DROP MATERIALIZED VIEW IF EXISTS demo_mv_category_agg;
DROP MATERIALIZED VIEW IF EXISTS demo_mv_daily_city;
DROP MATERIALIZED VIEW IF EXISTS demo_mv_partitioned;
DROP MATERIALIZED VIEW IF EXISTS demo_mv_product_rank;
DROP MATERIALIZED VIEW IF EXISTS demo_mv_sales_with_brand;
DROP TABLE IF EXISTS demo_mv_sales;
DROP TABLE IF EXISTS demo_mv_dim_product;
