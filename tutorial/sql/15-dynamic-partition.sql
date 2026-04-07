-- =====================================================
-- 第15章：动态分区与生命周期
-- 演示动态分区策略、自动过期、存储回收、冷热分离
-- 所需权限：CREATE_PRIV ON tutorial
-- =====================================================

USE tutorial;

-- =====================================================
-- 1. 动态分区基础
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_dynamic_partition_basic (
    id INT NOT NULL,
    name VARCHAR(50),
    event_time DATETIME
) ENGINE=OLAP
DUPLICATE KEY(id)
PARTITION BY RANGE(event_time) ()
DISTRIBUTED BY HASH(id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1",
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-7",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "dynamic_partition.buckets" = "3"
);

SHOW CREATE TABLE demo_dynamic_partition_basic;

SHOW PARTITIONS FROM demo_dynamic_partition_basic;

-- =====================================================
-- 2. 按小时动态分区
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_dynamic_partition_hourly (
    id INT NOT NULL,
    log_data VARCHAR(100),
    log_time DATETIME
) ENGINE=OLAP
DUPLICATE KEY(id)
PARTITION BY RANGE(log_time) ()
DISTRIBUTED BY HASH(id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1",
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "HOUR",
    "dynamic_partition.start" = "-24",
    "dynamic_partition.end" = "6",
    "dynamic_partition.prefix" = "p"
);

SHOW CREATE TABLE demo_dynamic_partition_hourly;

-- =====================================================
-- 3. 按月动态分区
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_dynamic_partition_monthly (
    id INT NOT NULL,
    report_data VARCHAR(100),
    report_month DATE
) ENGINE=OLAP
DUPLICATE KEY(id)
PARTITION BY RANGE(report_month) ()
DISTRIBUTED BY HASH(id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1",
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "MONTH",
    "dynamic_partition.start" = "-12",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p"
);

SHOW CREATE TABLE demo_dynamic_partition_monthly;

-- =====================================================
-- 4. 动态分区参数详解
-- =====================================================

SELECT 
    'dynamic_partition.enable' AS parameter,
    '是否启用动态分区' AS description,
    'true/false' AS value_type,
    'true' AS default_value
UNION ALL
SELECT 
    'dynamic_partition.time_unit',
    '分区粒度',
    'DAY/HOUR/MONTH/WEEK/YEAR',
    'DAY'
UNION ALL
SELECT 
    'dynamic_partition.start',
    '保留历史分区数',
    '负整数',
    '负无穷'
UNION ALL
SELECT 
    'dynamic_partition.end',
    '提前创建分区数',
    '正整数',
    '0'
UNION ALL
SELECT 
    'dynamic_partition.prefix',
    '分区名前缀',
    '字符串',
    'p'
UNION ALL
SELECT 
    'dynamic_partition.buckets',
    '分桶数',
    '正整数',
    '自动';

-- =====================================================
-- 5. 分区自动过期
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_partition_ttl (
    id INT NOT NULL,
    log_data VARCHAR(100),
    create_time DATETIME
) ENGINE=OLAP
DUPLICATE KEY(id)
PARTITION BY RANGE(create_time) ()
DISTRIBUTED BY HASH(id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1",
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-7",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "dynamic_partition.history_partition_num" = "7"
);

SHOW CREATE TABLE demo_partition_ttl;

-- =====================================================
-- 6. 冷热数据分离
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_cold_hot_partition (
    id INT NOT NULL,
    data VARCHAR(100),
    event_time DATETIME
) ENGINE=OLAP
DUPLICATE KEY(id)
PARTITION BY RANGE(event_time) (
    PARTITION p_hot VALUES [('2024-01-01'), ('2024-02-01')),
    PARTITION p_warm VALUES [('2023-07-01'), ('2024-01-01')),
    PARTITION p_cold VALUES [('2023-01-01'), ('2023-07-01'))
)
DISTRIBUTED BY HASH(id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1",
    "storage_medium" = "SSD",
    "storage_cooldown_time" = "2024-06-01 00:00:00"
);

SHOW CREATE TABLE demo_cold_hot_partition;

ALTER TABLE demo_cold_hot_partition MODIFY PARTITION p_cold SET ("storage_medium" = "HDD");

SHOW CREATE TABLE demo_cold_hot_partition;

-- =====================================================
-- 7. 分区生命周期管理
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_partition_lifecycle (
    id INT NOT NULL,
    data VARCHAR(100),
    create_date DATE
) ENGINE=OLAP
DUPLICATE KEY(id)
PARTITION BY RANGE(create_date) ()
DISTRIBUTED BY HASH(id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1",
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-30",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "partition_ttl_number" = "30"
);

SHOW CREATE TABLE demo_partition_lifecycle;

-- =====================================================
-- 8. 手动分区管理
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_manual_partition (
    id INT NOT NULL,
    data VARCHAR(100),
    event_date DATE
) ENGINE=OLAP
DUPLICATE KEY(id)
PARTITION BY RANGE(event_date) (
    PARTITION p20240101 VALUES [('2024-01-01'), ('2024-01-02')),
    PARTITION p20240102 VALUES [('2024-01-02'), ('2024-01-03')),
    PARTITION p20240103 VALUES [('2024-01-03'), ('2024-01-04'))
)
DISTRIBUTED BY HASH(id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);

SHOW PARTITIONS FROM demo_manual_partition;

ALTER TABLE demo_manual_partition ADD PARTITION p20240104 VALUES [('2024-01-04'), ('2024-01-05'));

SHOW PARTITIONS FROM demo_manual_partition;

ALTER TABLE demo_manual_partition DROP PARTITION p20240101;

SHOW PARTITIONS FROM demo_manual_partition;

-- =====================================================
-- 9. 分区裁剪优化
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_partition_pruning_test (
    id INT NOT NULL,
    user_id INT,
    event_time DATETIME,
    amount DECIMAL(10, 2)
) ENGINE=OLAP
DUPLICATE KEY(id)
PARTITION BY RANGE(event_time) ()
DISTRIBUTED BY HASH(id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1",
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-7",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p"
);

INSERT INTO demo_partition_pruning_test VALUES
(1, 1001, '2024-01-01 10:00:00', 100.00),
(2, 1002, '2024-01-02 11:00:00', 200.00),
(3, 1003, '2024-01-03 12:00:00', 300.00);

EXPLAIN SELECT * FROM demo_partition_pruning_test 
WHERE event_time >= '2024-01-02 00:00:00' AND event_time < '2024-01-03 00:00:00';

-- =====================================================
-- 10. 分区策略选择
-- =====================================================

SELECT 
    '按天分区' AS strategy,
    '日志、订单、事件流' AS best_for,
    '数据量大、查询频繁按天' AS scenario,
    'dynamic_partition.time_unit=DAY' AS config
UNION ALL
SELECT 
    '按小时分区',
    '实时监控、高频数据',
    '数据量极大、需要细粒度管理',
    'dynamic_partition.time_unit=HOUR'
UNION ALL
SELECT 
    '按月分区',
    '月报、统计数据',
    '数据量适中、按月查询',
    'dynamic_partition.time_unit=MONTH'
UNION ALL
SELECT 
    '冷热分离',
    '历史数据归档',
    '数据有明确冷热特征',
    'storage_medium=SSD/HDD'
UNION ALL
SELECT 
    'TTL自动过期',
    '临时数据、日志',
    '数据有明确生命周期',
    'partition_ttl_number';

-- =====================================================
-- 11. 动态分区监控
-- =====================================================

-- 查看分区信息
SHOW PARTITIONS FROM demo_dynamic_partition_basic;

-- 查看表属性
SHOW CREATE TABLE demo_dynamic_partition_basic;

-- 查看分区数据分布
SHOW DATA FROM demo_dynamic_partition_basic;

-- =====================================================
-- 12. 清理演示表
-- =====================================================

DROP TABLE IF EXISTS demo_dynamic_partition_basic;
DROP TABLE IF EXISTS demo_dynamic_partition_hourly;
DROP TABLE IF EXISTS demo_dynamic_partition_monthly;
DROP TABLE IF EXISTS demo_partition_ttl;
DROP TABLE IF EXISTS demo_cold_hot_partition;
DROP TABLE IF EXISTS demo_partition_lifecycle;
DROP TABLE IF EXISTS demo_manual_partition;
DROP TABLE IF EXISTS demo_partition_pruning_test;
