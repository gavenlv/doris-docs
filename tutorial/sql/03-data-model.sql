-- =====================================================
-- 第03章：数据模型深度解析
-- 演示 Duplicate/Aggregate/Unique/Primary Key 模型
-- 所需权限：CREATE_PRIV ON tutorial
-- =====================================================

USE tutorial;

-- =====================================================
-- 1. DUPLICATE 模型（明细模型）
-- 适用场景：日志、事件流、原始数据存储
-- 特点：保留所有原始数据，不做聚合
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_duplicate_log (
    log_id BIGINT NOT NULL,
    user_id BIGINT,
    action VARCHAR(50),
    page_url VARCHAR(500),
    action_time DATETIME,
    device_type VARCHAR(20),
    ip_address VARCHAR(50)
) ENGINE=OLAP
DUPLICATE KEY(log_id)
COMMENT '日志明细表 - Duplicate模型示例'
DISTRIBUTED BY HASH(log_id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_duplicate_log VALUES
(1, 10001, 'click', '/index', '2024-01-01 10:00:00', 'iOS', '192.168.1.1'),
(2, 10001, 'view', '/product/100', '2024-01-01 10:05:00', 'iOS', '192.168.1.1'),
(3, 10001, 'click', '/product/100', '2024-01-01 10:06:00', 'iOS', '192.168.1.1'),
(4, 10002, 'click', '/index', '2024-01-01 11:00:00', 'Android', '192.168.1.2'),
(5, 10001, 'click', '/index', '2024-01-01 10:00:00', 'iOS', '192.168.1.1');

SELECT * FROM demo_duplicate_log ORDER BY log_id;

-- =====================================================
-- 2. AGGREGATE 模型（聚合模型）
-- 适用场景：报表、统计、预聚合场景
-- 特点：相同Key的数据自动聚合，节省存储
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_aggregate_stats (
    user_id BIGINT NOT NULL,
    date_key DATE NOT NULL,
    pv BIGINT SUM COMMENT '页面浏览量',
    uv BIGINT SUM COMMENT '独立访客数',
    order_count BIGINT SUM COMMENT '订单数',
    order_amount DECIMAL(18, 2) SUM COMMENT '订单金额',
    first_visit_time DATETIME MIN COMMENT '首次访问时间',
    last_visit_time DATETIME MAX COMMENT '最后访问时间'
) ENGINE=OLAP
AGGREGATE KEY(user_id, date_key)
COMMENT '用户统计聚合表 - Aggregate模型示例'
PARTITION BY RANGE(date_key) (
    PARTITION p202401 VALUES [('2024-01-01'), ('2024-02-01')),
    PARTITION p202402 VALUES [('2024-02-01'), ('2024-03-01'))
)
DISTRIBUTED BY HASH(user_id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_aggregate_stats VALUES
(10001, '2024-01-01', 10, 1, 2, 500.00, '2024-01-01 08:00:00', '2024-01-01 20:00:00'),
(10001, '2024-01-01', 5, 1, 1, 300.00, '2024-01-01 10:00:00', '2024-01-01 22:00:00'),
(10001, '2024-01-02', 8, 1, 1, 200.00, '2024-01-02 09:00:00', '2024-01-02 18:00:00'),
(10002, '2024-01-01', 15, 1, 3, 800.00, '2024-01-01 07:00:00', '2024-01-01 21:00:00');

SELECT * FROM demo_aggregate_stats ORDER BY user_id, date_key;

-- =====================================================
-- 3. UNIQUE 模型（唯一主键模型）
-- 适用场景：维度表、用户表、需要更新的表
-- 特点：相同Key的数据保留最新版本
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_unique_user (
    user_id BIGINT NOT NULL,
    username VARCHAR(50),
    email VARCHAR(100),
    phone VARCHAR(20),
    vip_level TINYINT,
    register_time DATETIME,
    update_time DATETIME
) ENGINE=OLAP
UNIQUE KEY(user_id)
COMMENT '用户表 - Unique模型示例'
DISTRIBUTED BY HASH(user_id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_unique_user VALUES
(10001, 'user_001', 'user001@example.com', '13800138001', 1, '2024-01-01 10:00:00', '2024-01-01 10:00:00');

SELECT * FROM demo_unique_user WHERE user_id = 10001;

INSERT INTO demo_unique_user VALUES
(10001, 'user_001_vip', 'user001@example.com', '13800138001', 3, '2024-01-01 10:00:00', '2024-01-02 15:00:00');

SELECT * FROM demo_unique_user WHERE user_id = 10001;

INSERT INTO demo_unique_user VALUES
(10002, 'user_002', 'user002@example.com', '13800138002', 2, '2024-01-02 10:00:00', '2024-01-02 10:00:00'),
(10003, 'user_003', 'user003@example.com', '13800138003', 1, '2024-01-03 10:00:00', '2024-01-03 10:00:00');

SELECT * FROM demo_unique_user ORDER BY user_id;

-- =====================================================
-- 4. PRIMARY KEY 模型（主键模型）
-- 适用场景：实时更新、频繁删除、点查询
-- 特点：支持实时更新和删除，查询性能更好
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_primary_order (
    order_id BIGINT NOT NULL,
    order_no VARCHAR(50),
    user_id BIGINT,
    total_amount DECIMAL(18, 2),
    order_status TINYINT,
    create_time DATETIME,
    update_time DATETIME
) ENGINE=OLAP
PRIMARY KEY(order_id)
COMMENT '订单表 - Primary Key模型示例'
DISTRIBUTED BY HASH(order_id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1",
    "enable_unique_key_merge_on_write" = "true"
);

INSERT INTO demo_primary_order VALUES
(1000001, 'ORD001', 10001, 500.00, 0, '2024-01-01 10:00:00', '2024-01-01 10:00:00');

SELECT * FROM demo_primary_order WHERE order_id = 1000001;

UPDATE demo_primary_order 
SET order_status = 1, update_time = '2024-01-01 10:30:00'
WHERE order_id = 1000001;

SELECT * FROM demo_primary_order WHERE order_id = 1000001;

DELETE FROM demo_primary_order WHERE order_id = 1000001;

SELECT * FROM demo_primary_order;

INSERT INTO demo_primary_order VALUES
(1000001, 'ORD001', 10001, 500.00, 1, '2024-01-01 10:00:00', '2024-01-01 10:30:00'),
(1000002, 'ORD002', 10002, 800.00, 0, '2024-01-01 11:00:00', '2024-01-01 11:00:00'),
(1000003, 'ORD003', 10001, 300.00, 2, '2024-01-01 12:00:00', '2024-01-01 12:00:00');

SELECT * FROM demo_primary_order ORDER BY order_id;

-- =====================================================
-- 5. 模型对比与选择建议
-- =====================================================

SELECT 
    'DUPLICATE' AS model_type,
    '日志、事件流、原始数据' AS best_for,
    '保留所有数据，不做聚合' AS feature,
    '存储空间较大，查询需聚合' AS trade_off
UNION ALL
SELECT 
    'AGGREGATE',
    '报表、统计、预聚合',
    '自动聚合，节省存储',
    '查询时无法获取明细'
UNION ALL
SELECT 
    'UNIQUE',
    '维度表、用户表',
    '相同Key保留最新版本',
    '更新性能一般，适合低频更新'
UNION ALL
SELECT 
    'PRIMARY KEY',
    '实时更新、频繁删除',
    '支持实时更新删除，点查询快',
    '写入性能略低，存储空间稍大';

-- =====================================================
-- 6. 实际场景示例：订单状态流转
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_order_status_flow (
    order_id BIGINT NOT NULL,
    status TINYINT,
    status_name VARCHAR(20),
    change_time DATETIME,
    operator VARCHAR(50)
) ENGINE=OLAP
DUPLICATE KEY(order_id)
COMMENT '订单状态流转记录'
DISTRIBUTED BY HASH(order_id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_order_status_flow VALUES
(1000001, 0, '待支付', '2024-01-01 10:00:00', 'system'),
(1000001, 1, '已支付', '2024-01-01 10:05:00', 'user'),
(1000001, 2, '已发货', '2024-01-02 09:00:00', 'admin'),
(1000001, 3, '已完成', '2024-01-03 14:00:00', 'user');

SELECT 
    order_id,
    GROUP_CONCAT(status_name ORDER BY change_time SEPARATOR ' -> ') AS status_flow
FROM demo_order_status_flow
GROUP BY order_id;

-- =====================================================
-- 7. 清理演示表
-- =====================================================

DROP TABLE IF EXISTS demo_duplicate_log;
DROP TABLE IF EXISTS demo_aggregate_stats;
DROP TABLE IF EXISTS demo_unique_user;
DROP TABLE IF EXISTS demo_primary_order;
DROP TABLE IF EXISTS demo_order_status_flow;
