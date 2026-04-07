-- =====================================================
-- 第09章：数据更新与删除
-- 演示 DELETE/UPDATE/REPLACE/Schema Change 操作
-- 所需权限：UPDATE_PRIV, DELETE_PRIV ON tutorial
-- =====================================================

USE tutorial;

-- =====================================================
-- 1. DELETE 删除数据
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_delete_table (
    id INT NOT NULL,
    name VARCHAR(50),
    age INT,
    city VARCHAR(50),
    status TINYINT
) ENGINE=OLAP
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_delete_table VALUES
(1, '张三', 28, '北京', 1),
(2, '李四', 35, '上海', 1),
(3, '王五', 30, '广州', 0),
(4, '赵六', 25, '深圳', 1),
(5, '钱七', 40, '杭州', 0);

SELECT * FROM demo_delete_table ORDER BY id;

DELETE FROM demo_delete_table WHERE id = 5;

SELECT * FROM demo_delete_table ORDER BY id;

DELETE FROM demo_delete_table WHERE status = 0;

SELECT * FROM demo_delete_table ORDER BY id;

DELETE FROM demo_delete_table WHERE city = '上海';

SELECT * FROM demo_delete_table ORDER BY id;

-- =====================================================
-- 2. UPDATE 更新数据（Primary Key模型）
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_update_table (
    id INT NOT NULL,
    name VARCHAR(50),
    age INT,
    city VARCHAR(50),
    status TINYINT,
    update_time DATETIME
) ENGINE=OLAP
PRIMARY KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1",
    "enable_unique_key_merge_on_write" = "true"
);

INSERT INTO demo_update_table VALUES
(1, '张三', 28, '北京', 1, '2024-01-01 10:00:00'),
(2, '李四', 35, '上海', 1, '2024-01-01 10:00:00'),
(3, '王五', 30, '广州', 0, '2024-01-01 10:00:00');

SELECT * FROM demo_update_table ORDER BY id;

UPDATE demo_update_table 
SET age = 29, update_time = CURRENT_TIMESTAMP()
WHERE id = 1;

SELECT * FROM demo_update_table ORDER BY id;

UPDATE demo_update_table 
SET status = 1, update_time = CURRENT_TIMESTAMP()
WHERE status = 0;

SELECT * FROM demo_update_table ORDER BY id;

UPDATE demo_update_table 
SET city = '深圳', update_time = CURRENT_TIMESTAMP()
WHERE name = '李四';

SELECT * FROM demo_update_table ORDER BY id;

-- =====================================================
-- 3. UPDATE 更新数据（Unique Key模型）
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_unique_update (
    user_id BIGINT NOT NULL,
    username VARCHAR(50),
    vip_level TINYINT,
    score INT,
    update_time DATETIME
) ENGINE=OLAP
UNIQUE KEY(user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_unique_update VALUES
(10001, 'user_001', 1, 100, '2024-01-01 10:00:00'),
(10002, 'user_002', 2, 200, '2024-01-01 10:00:00'),
(10003, 'user_003', 1, 150, '2024-01-01 10:00:00');

SELECT * FROM demo_unique_update ORDER BY user_id;

INSERT INTO demo_unique_update VALUES
(10001, 'user_001_vip', 3, 500, CURRENT_TIMESTAMP());

SELECT * FROM demo_unique_update ORDER BY user_id;

-- =====================================================
-- 4. INSERT OVERWRITE（覆盖写入）
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_overwrite_table (
    id INT NOT NULL,
    name VARCHAR(50),
    score INT
) ENGINE=OLAP
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_overwrite_table VALUES
(1, '张三', 85),
(2, '李四', 90),
(3, '王五', 78);

SELECT * FROM demo_overwrite_table ORDER BY id;

INSERT OVERWRITE TABLE demo_overwrite_table VALUES
(1, '张三', 95),
(2, '李四', 92),
(3, '王五', 88),
(4, '赵六', 85);

SELECT * FROM demo_overwrite_table ORDER BY id;

-- =====================================================
-- 5. 分区级删除
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_partition_delete (
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

INSERT INTO demo_partition_delete VALUES
(1, 'event1', '2024-01-15 10:00:00'),
(2, 'event2', '2024-02-20 11:00:00'),
(3, 'event3', '2024-03-10 12:00:00');

SELECT * FROM demo_partition_delete ORDER BY id;

DELETE FROM demo_partition_delete PARTITION(p202401);

SELECT * FROM demo_partition_delete ORDER BY id;

-- =====================================================
-- 6. 条件删除与批量删除
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_batch_delete (
    id INT NOT NULL,
    user_id BIGINT,
    order_time DATETIME,
    amount DECIMAL(10, 2),
    status TINYINT
) ENGINE=OLAP
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_batch_delete VALUES
(1, 10001, '2024-01-01 10:00:00', 500.00, 1),
(2, 10001, '2024-01-02 11:00:00', 300.00, 0),
(3, 10002, '2024-01-01 12:00:00', 800.00, 1),
(4, 10002, '2024-01-03 13:00:00', 200.00, 0),
(5, 10003, '2024-01-01 14:00:00', 600.00, 1);

SELECT * FROM demo_batch_delete ORDER BY id;

DELETE FROM demo_batch_delete WHERE status = 0;

SELECT * FROM demo_batch_delete ORDER BY id;

DELETE FROM demo_batch_delete WHERE order_time < '2024-01-02 00:00:00';

SELECT * FROM demo_batch_delete ORDER BY id;

-- =====================================================
-- 7. 使用 Sequence Column 实现行级更新
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_sequence_update (
    id INT NOT NULL,
    name VARCHAR(50),
    score INT,
    update_time DATETIME
) ENGINE=OLAP
UNIQUE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1",
    "function_column.sequence_type" = "DATETIME",
    "function_column.sequence_col" = "update_time"
);

INSERT INTO demo_sequence_update VALUES
(1, '张三', 85, '2024-01-01 10:00:00'),
(2, '李四', 90, '2024-01-01 10:00:00');

SELECT * FROM demo_sequence_update ORDER BY id;

INSERT INTO demo_sequence_update VALUES
(1, '张三', 95, '2024-01-02 10:00:00');

SELECT * FROM demo_sequence_update ORDER BY id;

INSERT INTO demo_sequence_update VALUES
(1, '张三旧数据', 70, '2023-12-01 10:00:00');

SELECT * FROM demo_sequence_update ORDER BY id;

-- =====================================================
-- 8. DELETE 与 UPDATE 性能考虑
-- =====================================================

-- DELETE 操作会标记数据为删除，不会立即释放空间
-- 需要通过 Compaction 清理已删除数据

-- 查看表的 Compaction 状态
-- SHOW TABLET FROM demo_delete_table;

-- 手动触发 Compaction
-- CUMULATIVE COMPACTION FOR TABLE demo_delete_table;

-- =====================================================
-- 9. 更新删除最佳实践
-- =====================================================

SELECT 
    'DELETE' AS operation,
    'Duplicate模型' AS suitable_model,
    '按条件删除数据' AS use_case,
    '标记删除，空间不立即释放' AS note
UNION ALL
SELECT 
    'UPDATE',
    'Primary Key模型',
    '按条件更新数据',
    'Merge-on-Write，性能更好'
UNION ALL
SELECT 
    'INSERT覆盖',
    'Unique Key模型',
    '全量更新',
    '相同Key保留最新版本'
UNION ALL
SELECT 
    'Sequence Column',
    'Unique Key模型',
    '按时间版本更新',
    '只保留最新版本数据';

-- =====================================================
-- 10. 清理演示表
-- =====================================================

DROP TABLE IF EXISTS demo_delete_table;
DROP TABLE IF EXISTS demo_update_table;
DROP TABLE IF EXISTS demo_unique_update;
DROP TABLE IF EXISTS demo_overwrite_table;
DROP TABLE IF EXISTS demo_partition_delete;
DROP TABLE IF EXISTS demo_batch_delete;
DROP TABLE IF EXISTS demo_sequence_update;
