-- =====================================================
-- 第16章：Nereids优化器
-- 演示 CBO/RBO、统计信息、Join Reorder、MV重写
-- 所需权限：SELECT_PRIV ON tutorial
-- =====================================================

USE tutorial;

-- =====================================================
-- 1. 准备测试数据
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_nereids_table1 (
    id INT NOT NULL,
    name VARCHAR(50),
    value INT,
    category VARCHAR(20)
) ENGINE=OLAP
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 5
PROPERTIES (
    "replication_num" = "1"
);

CREATE TABLE IF NOT EXISTS demo_nereids_table2 (
    id INT NOT NULL,
    ref_id INT,
    amount DECIMAL(10, 2),
    status TINYINT
) ENGINE=OLAP
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 5
PROPERTIES (
    "replication_num" = "1"
);

CREATE TABLE IF NOT EXISTS demo_nereids_table3 (
    id INT NOT NULL,
    category_name VARCHAR(50),
    description VARCHAR(200)
) ENGINE=OLAP
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_nereids_table1 VALUES
(1, 'A', 100, 'cat1'),
(2, 'B', 200, 'cat1'),
(3, 'C', 150, 'cat2'),
(4, 'D', 300, 'cat2'),
(5, 'E', 250, 'cat3');

INSERT INTO demo_nereids_table2 VALUES
(1, 1, 1000.00, 1),
(2, 1, 2000.00, 1),
(3, 2, 1500.00, 0),
(4, 3, 3000.00, 1),
(5, 4, 2500.00, 1);

INSERT INTO demo_nereids_table3 VALUES
(1, 'cat1', 'Category 1'),
(2, 'cat2', 'Category 2'),
(3, 'cat3', 'Category 3');

-- =====================================================
-- 2. 查看执行计划
-- =====================================================

EXPLAIN SELECT * FROM demo_nereids_table1 WHERE value > 100;

EXPLAIN VERBOSE SELECT * FROM demo_nereids_table1 WHERE value > 100;

-- =====================================================
-- 3. 统计信息收集
-- =====================================================

ANALYZE TABLE demo_nereids_table1 UPDATE STATISTICS;

SHOW TABLE STATS demo_nereids_table1;

SHOW COLUMN STATS demo_nereids_table1;

ANALYZE TABLE demo_nereids_table2 UPDATE STATISTICS;

SHOW TABLE STATS demo_nereids_table2;

-- =====================================================
-- 4. CBO (Cost-Based Optimizer) 优化
-- =====================================================

EXPLAIN SELECT 
    t1.name,
    t2.amount
FROM demo_nereids_table1 t1
JOIN demo_nereids_table2 t2 ON t1.id = t2.ref_id
WHERE t1.value > 100;

EXPLAIN COSTS SELECT 
    t1.name,
    t2.amount
FROM demo_nereids_table1 t1
JOIN demo_nereids_table2 t2 ON t1.id = t2.ref_id
WHERE t1.value > 100;

-- =====================================================
-- 5. Join Reorder（Join重排序）
-- =====================================================

EXPLAIN SELECT 
    t1.name,
    t2.amount,
    t3.category_name
FROM demo_nereids_table1 t1
JOIN demo_nereids_table2 t2 ON t1.id = t2.ref_id
JOIN demo_nereids_table3 t3 ON t1.category = t3.category_name
WHERE t1.value > 100;

SET enable_join_reorder = true;

EXPLAIN SELECT 
    t1.name,
    t2.amount,
    t3.category_name
FROM demo_nereids_table1 t1
JOIN demo_nereids_table2 t2 ON t1.id = t2.ref_id
JOIN demo_nereids_table3 t3 ON t1.category = t3.category_name
WHERE t1.value > 100;

-- =====================================================
-- 6. 谓词下推
-- =====================================================

EXPLAIN SELECT 
    t1.name,
    t2.amount
FROM demo_nereids_table1 t1
JOIN demo_nereids_table2 t2 ON t1.id = t2.ref_id
WHERE t1.category = 'cat1' AND t2.status = 1;

-- =====================================================
-- 7. 投影下推
-- =====================================================

EXPLAIN SELECT 
    t1.name
FROM demo_nereids_table1 t1
WHERE t1.value > 100;

-- =====================================================
-- 8. 常量折叠
-- =====================================================

EXPLAIN SELECT * FROM demo_nereids_table1 WHERE 1 = 1 AND value > 100;

EXPLAIN SELECT * FROM demo_nereids_table1 WHERE value > 100 AND 2 > 1;

-- =====================================================
-- 9. 子查询优化
-- =====================================================

EXPLAIN SELECT * FROM demo_nereids_table1 
WHERE id IN (SELECT ref_id FROM demo_nereids_table2 WHERE status = 1);

EXPLAIN SELECT * FROM demo_nereids_table1 t1
WHERE EXISTS (SELECT 1 FROM demo_nereids_table2 t2 WHERE t2.ref_id = t1.id AND t2.status = 1);

-- =====================================================
-- 10. 物化视图重写
-- =====================================================

CREATE MATERIALIZED VIEW demo_nereids_mv
BUILD IMMEDIATE REFRESH COMPLETE ON MANUAL
DISTRIBUTED BY HASH(category) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
)
AS
SELECT 
    category,
    SUM(value) AS total_value,
    COUNT(*) AS cnt
FROM demo_nereids_table1
GROUP BY category;

REFRESH MATERIALIZED VIEW demo_nereids_mv COMPLETE;

SELECT category, SUM(value) AS total_value
FROM demo_nereids_table1
GROUP BY category;

EXPLAIN SELECT category, SUM(value) AS total_value
FROM demo_nereids_table1
GROUP BY category;

-- =====================================================
-- 11. 优化器提示（Hints）
-- =====================================================

SELECT /*+ SET_VAR(enable_join_reorder=true) */
    t1.name,
    t2.amount
FROM demo_nereids_table1 t1
JOIN demo_nereids_table2 t2 ON t1.id = t2.ref_id;

SELECT /*+ SET_VAR(parallel_fragment_exec_instance_num=4) */
    COUNT(*)
FROM demo_nereids_table1;

-- =====================================================
-- 12. 执行计划分析
-- =====================================================

EXPLAIN SELECT 
    t1.category,
    COUNT(*) AS cnt,
    SUM(t2.amount) AS total_amount
FROM demo_nereids_table1 t1
JOIN demo_nereids_table2 t2 ON t1.id = t2.ref_id
WHERE t1.value > 100 AND t2.status = 1
GROUP BY t1.category
ORDER BY total_amount DESC;

-- =====================================================
-- 13. 优化器配置参数
-- =====================================================

SHOW VARIABLES LIKE '%optimizer%';

SHOW VARIABLES LIKE '%join%';

SHOW VARIABLES LIKE '%statistic%';

-- =====================================================
-- 14. 优化规则对比
-- =====================================================

SELECT 
    '谓词下推' AS rule,
    '将过滤条件尽可能下推到存储层' AS description,
    '减少数据传输' AS benefit
UNION ALL
SELECT 
    '投影下推',
    '只读取需要的列',
    '减少IO开销'
UNION ALL
SELECT 
    'Join Reorder',
    '根据代价调整Join顺序',
    '减少中间结果集'
UNION ALL
SELECT 
    '常量折叠',
    '编译时计算常量表达式',
    '减少运行时计算'
UNION ALL
SELECT 
    '子查询转Join',
    '将子查询转换为Join',
    '提高执行效率'
UNION ALL
SELECT 
    'MV重写',
    '使用物化视图替换原查询',
    '加速聚合查询';

-- =====================================================
-- 15. 清理演示表
-- =====================================================

DROP MATERIALIZED VIEW IF EXISTS demo_nereids_mv;
DROP TABLE IF EXISTS demo_nereids_table1;
DROP TABLE IF EXISTS demo_nereids_table2;
DROP TABLE IF EXISTS demo_nereids_table3;
