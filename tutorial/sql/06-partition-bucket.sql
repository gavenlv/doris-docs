-- =====================================================
-- 第06章：分区与分桶策略
-- 演示 Range/List/Hash 分区、分桶策略、冷热分离
-- 所需权限：CREATE_PRIV ON tutorial
-- =====================================================

USE tutorial;

-- =====================================================
-- 1. Range 分区（范围分区）
-- 最常用的分区方式，适合时间序列数据
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_range_partition (
    order_id BIGINT NOT NULL,
    user_id BIGINT,
    order_time DATETIME,
    amount DECIMAL(18, 2)
) ENGINE=OLAP
DUPLICATE KEY(order_id)
PARTITION BY RANGE(order_time) (
    PARTITION p202301 VALUES [('2023-01-01 00:00:00'), ('2023-02-01 00:00:00')),
    PARTITION p202302 VALUES [('2023-02-01 00:00:00'), ('2023-03-01 00:00:00')),
    PARTITION p202303 VALUES [('2023-03-01 00:00:00'), ('2023-04-01 00:00:00'))
)
DISTRIBUTED BY HASH(order_id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);

SHOW PARTITIONS FROM demo_range_partition;

INSERT INTO demo_range_partition VALUES
(1, 10001, '2023-01-15 10:00:00', 500.00),
(2, 10002, '2023-02-20 11:00:00', 800.00),
(3, 10003, '2023-03-10 12:00:00', 300.00);

SELECT * FROM demo_range_partition WHERE order_time >= '2023-02-01' AND order_time < '2023-03-01';

-- =====================================================
-- 2. List 分区（列表分区）
-- 适合按地区、类别等离散值分区
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_list_partition (
    id INT NOT NULL,
    name VARCHAR(50),
    city VARCHAR(50),
    amount DECIMAL(10, 2)
) ENGINE=OLAP
DUPLICATE KEY(id)
PARTITION BY LIST(city) (
    PARTITION p_beijing VALUES IN ('北京'),
    PARTITION p_shanghai VALUES IN ('上海'),
    PARTITION p_guangzhou VALUES IN ('广州', '深圳'),
    PARTITION p_other VALUES IN ('杭州', '南京', '成都')
)
DISTRIBUTED BY HASH(id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);

SHOW PARTITIONS FROM demo_list_partition;

INSERT INTO demo_list_partition VALUES
(1, '张三', '北京', 1000.00),
(2, '李四', '上海', 2000.00),
(3, '王五', '广州', 1500.00),
(4, '赵六', '深圳', 1800.00),
(5, '钱七', '杭州', 1200.00);

SELECT * FROM demo_list_partition WHERE city = '北京';

-- =====================================================
-- 3. 动态分区
-- 自动创建和删除分区
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_dynamic_partition (
    log_id BIGINT NOT NULL,
    user_id BIGINT,
    action VARCHAR(50),
    log_time DATETIME
) ENGINE=OLAP
DUPLICATE KEY(log_id)
PARTITION BY RANGE(log_time) ()
DISTRIBUTED BY HASH(log_id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1",
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-7",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "dynamic_partition.buckets" = "3"
);

SHOW CREATE TABLE demo_dynamic_partition;

SHOW PARTITIONS FROM demo_dynamic_partition;

-- =====================================================
-- 4. 多列分区
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_multi_column_partition (
    order_id BIGINT NOT NULL,
    user_id BIGINT,
    order_date DATE,
    region VARCHAR(20),
    amount DECIMAL(18, 2)
) ENGINE=OLAP
DUPLICATE KEY(order_id)
PARTITION BY RANGE(order_date) ()
DISTRIBUTED BY HASH(user_id) BUCKETS 5
PROPERTIES (
    "replication_num" = "1",
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "MONTH",
    "dynamic_partition.start" = "-12",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p"
);

SHOW PARTITIONS FROM demo_multi_column_partition;

-- =====================================================
-- 5. 分桶策略
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_bucket_strategy (
    user_id BIGINT NOT NULL,
    username VARCHAR(50),
    city VARCHAR(50),
    register_time DATETIME
) ENGINE=OLAP
DUPLICATE KEY(user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 10
PROPERTIES (
    "replication_num" = "1"
);

SHOW CREATE TABLE demo_bucket_strategy;

CREATE TABLE IF NOT EXISTS demo_random_bucket (
    id INT NOT NULL,
    name VARCHAR(50),
    data VARCHAR(100)
) ENGINE=OLAP
DUPLICATE KEY(id)
DISTRIBUTED BY RANDOM BUCKETS 5
PROPERTIES (
    "replication_num" = "1"
);

SHOW CREATE TABLE demo_random_bucket;

-- =====================================================
-- 6. 分区裁剪演示
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_partition_pruning (
    id INT NOT NULL,
    name VARCHAR(50),
    event_time DATETIME
) ENGINE=OLAP
DUPLICATE KEY(id)
PARTITION BY RANGE(event_time) (
    PARTITION p202401 VALUES [('2024-01-01 00:00:00'), ('2024-02-01 00:00:00')),
    PARTITION p202402 VALUES [('2024-02-01 00:00:00'), ('2024-03-01 00:00:00')),
    PARTITION p202403 VALUES [('2024-03-01 00:00:00'), ('2024-04-01 00:00:00'))
)
DISTRIBUTED BY HASH(id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_partition_pruning VALUES
(1, 'event1', '2024-01-15 10:00:00'),
(2, 'event2', '2024-02-20 11:00:00'),
(3, 'event3', '2024-03-10 12:00:00');

EXPLAIN SELECT * FROM demo_partition_pruning WHERE event_time >= '2024-02-01' AND event_time < '2024-03-01';

-- =====================================================
-- 7. 冷热数据分离
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_cold_hot_data (
    id BIGINT NOT NULL,
    name VARCHAR(50),
    create_time DATETIME,
    data VARCHAR(200)
) ENGINE=OLAP
DUPLICATE KEY(id)
PARTITION BY RANGE(create_time) (
    PARTITION p_hot VALUES [('2024-01-01'), ('2024-02-01')),
    PARTITION p_warm VALUES [('2023-07-01'), ('2024-01-01')),
    PARTITION p_cold VALUES [('2023-01-01'), ('2023-07-01'))
)
DISTRIBUTED BY HASH(id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1",
    "storage_medium" = "SSD",
    "storage_cooldown_time" = "2024-03-01 00:00:00"
);

SHOW CREATE TABLE demo_cold_hot_data;

ALTER TABLE demo_cold_hot_data MODIFY PARTITION p_cold SET ("storage_medium" = "HDD");

SHOW CREATE TABLE demo_cold_hot_data;

-- =====================================================
-- 8. 分区管理操作
-- =====================================================

ALTER TABLE demo_range_partition ADD PARTITION p202304 VALUES [('2023-04-01 00:00:00'), ('2023-05-01 00:00:00'));

SHOW PARTITIONS FROM demo_range_partition;

ALTER TABLE demo_range_partition DROP PARTITION p202301;

SHOW PARTITIONS FROM demo_range_partition;

ALTER TABLE demo_list_partition ADD PARTITION p_wuhan VALUES IN ('武汉', '长沙');

SHOW PARTITIONS FROM demo_list_partition;

-- =====================================================
-- 9. 分桶数调整
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_bucket_resize (
    id INT NOT NULL,
    name VARCHAR(50)
) ENGINE=OLAP
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 5
PROPERTIES (
    "replication_num" = "1"
);

SHOW CREATE TABLE demo_bucket_resize;

-- =====================================================
-- 10. 分区与分桶选择建议
-- =====================================================

SELECT 
    'Range分区' AS partition_type,
    '时间序列数据、日志、订单' AS best_for,
    '支持分区裁剪，方便数据管理' AS advantage
UNION ALL
SELECT 
    'List分区',
    '地区、类别等离散值',
    '灵活的分区定义，适合特定业务'
UNION ALL
SELECT 
    '动态分区',
    '持续增长的时间数据',
    '自动管理分区，减少运维成本'
UNION ALL
SELECT 
    'Hash分桶',
    '数据分布均匀的场景',
    '数据均匀分布，并发查询性能好'
UNION ALL
SELECT 
    'Random分桶',
    '不需要频繁Join的表',
    '写入性能好，但查询性能略低';

-- =====================================================
-- 11. 清理演示表
-- =====================================================

DROP TABLE IF EXISTS demo_range_partition;
DROP TABLE IF EXISTS demo_list_partition;
DROP TABLE IF EXISTS demo_dynamic_partition;
DROP TABLE IF EXISTS demo_multi_column_partition;
DROP TABLE IF EXISTS demo_bucket_strategy;
DROP TABLE IF EXISTS demo_random_bucket;
DROP TABLE IF EXISTS demo_partition_pruning;
DROP TABLE IF EXISTS demo_cold_hot_data;
DROP TABLE IF EXISTS demo_bucket_resize;
