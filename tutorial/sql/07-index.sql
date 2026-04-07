-- =====================================================
-- 第07章：索引系统详解
-- 演示前缀索引、Bitmap、Bloom Filter、倒排索引、Ngram
-- 所需权限：CREATE_PRIV ON tutorial
-- =====================================================

USE tutorial;

-- =====================================================
-- 1. 前缀索引（自动创建）
-- Duplicate/Aggregate/Unique Key 自动创建
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_prefix_index (
    user_id BIGINT NOT NULL,
    username VARCHAR(50),
    city VARCHAR(50),
    age INT,
    register_time DATETIME
) ENGINE=OLAP
DUPLICATE KEY(user_id, username, city)
DISTRIBUTED BY HASH(user_id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_prefix_index VALUES
(10001, '张三', '北京', 28, '2024-01-01 10:00:00'),
(10002, '李四', '上海', 35, '2024-01-02 11:00:00'),
(10003, '王五', '广州', 30, '2024-01-03 12:00:00');

EXPLAIN SELECT * FROM demo_prefix_index WHERE user_id = 10001;

EXPLAIN SELECT * FROM demo_prefix_index WHERE user_id = 10001 AND username = '张三';

EXPLAIN SELECT * FROM demo_prefix_index WHERE city = '北京';

-- =====================================================
-- 2. Bitmap 索引
-- 适合低基数列，如性别、状态、地区等
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_bitmap_index (
    id INT NOT NULL,
    name VARCHAR(50),
    gender TINYINT COMMENT '1-男, 2-女',
    city VARCHAR(50),
    status TINYINT COMMENT '0-禁用, 1-启用'
) ENGINE=OLAP
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_bitmap_index VALUES
(1, '张三', 1, '北京', 1),
(2, '李四', 1, '上海', 1),
(3, '王五', 2, '广州', 1),
(4, '赵六', 1, '北京', 0),
(5, '钱七', 2, '上海', 1);

CREATE INDEX idx_gender ON demo_bitmap_index(gender) USING BITMAP;

CREATE INDEX idx_city ON demo_bitmap_index(city) USING BITMAP;

CREATE INDEX idx_status ON demo_bitmap_index(status) USING BITMAP;

SHOW INDEX FROM demo_bitmap_index;

EXPLAIN SELECT * FROM demo_bitmap_index WHERE gender = 1;

EXPLAIN SELECT * FROM demo_bitmap_index WHERE gender = 1 AND city = '北京';

EXPLAIN SELECT * FROM demo_bitmap_index WHERE gender = 1 AND status = 1;

-- =====================================================
-- 3. Bloom Filter 索引
-- 适合高基数列，快速判断值是否存在
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_bloom_filter (
    id INT NOT NULL,
    user_id BIGINT,
    order_id BIGINT,
    product_id BIGINT,
    amount DECIMAL(10, 2)
) ENGINE=OLAP
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1",
    "bloom_filter_columns" = "user_id,order_id,product_id",
    "bloom_filter_fpp" = "0.05"
);

SHOW CREATE TABLE demo_bloom_filter;

INSERT INTO demo_bloom_filter VALUES
(1, 10001, 1000001, 100001, 500.00),
(2, 10002, 1000002, 100002, 800.00),
(3, 10003, 1000003, 100003, 300.00),
(4, 10001, 1000004, 100001, 200.00);

EXPLAIN SELECT * FROM demo_bloom_filter WHERE user_id = 10001;

EXPLAIN SELECT * FROM demo_bloom_filter WHERE user_id = 99999;

-- =====================================================
-- 4. 倒排索引（Inverted Index）
-- 适合全文检索、文本搜索
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_inverted_index (
    id INT NOT NULL,
    title VARCHAR(200),
    content TEXT,
    author VARCHAR(50),
    create_time DATETIME
) ENGINE=OLAP
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_inverted_index VALUES
(1, 'Apache Doris 入门教程', 'Doris 是一个现代化的 MPP 分析型数据库，专注于 OLAP 场景', '张三', '2024-01-01 10:00:00'),
(2, 'Doris 架构详解', 'Doris 采用 FE 和 BE 架构，支持高并发查询', '李四', '2024-01-02 11:00:00'),
(3, '数据库性能优化', '性能优化需要从多个维度考虑，包括索引、分区、查询优化等', '王五', '2024-01-03 12:00:00'),
(4, 'Doris 实时分析实践', 'Doris 支持实时数据导入和分析，适合实时报表场景', '赵六', '2024-01-04 13:00:00');

CREATE INDEX idx_title ON demo_inverted_index(title) USING INVERTED PROPERTIES("parser" = "english");

CREATE INDEX idx_content ON demo_inverted_index(content) USING INVERTED PROPERTIES("parser" = "english");

SHOW INDEX FROM demo_inverted_index;

SELECT * FROM demo_inverted_index WHERE title MATCH 'Doris';

SELECT * FROM demo_inverted_index WHERE content MATCH 'Doris 分析';

SELECT * FROM demo_inverted_index WHERE title MATCH 'Doris' OR content MATCH '优化';

-- =====================================================
-- 5. Ngram Bloom Filter 索引
-- 适合中文全文检索
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_ngram_index (
    id INT NOT NULL,
    title VARCHAR(200),
    content TEXT
) ENGINE=OLAP
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_ngram_index VALUES
(1, 'Apache Doris 数据库教程', 'Doris 是一个高性能的分析型数据库'),
(2, '数据分析最佳实践', '数据分析需要掌握多种技术和工具'),
(3, '大数据平台建设', '构建大数据平台需要考虑数据采集、存储、计算等环节');

CREATE INDEX idx_title_ngram ON demo_ngram_index(title) USING NGRAM_BF PROPERTIES("gram_size" = "2", "bf_size" = "256");

CREATE INDEX idx_content_ngram ON demo_ngram_index(content) USING NGRAM_BF PROPERTIES("gram_size" = "2", "bf_size" = "256");

SHOW INDEX FROM demo_ngram_index;

SELECT * FROM demo_ngram_index WHERE title LIKE '%数据库%';

SELECT * FROM demo_ngram_index WHERE content LIKE '%分析%';

-- =====================================================
-- 6. 组合索引效果演示
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_combined_index (
    id INT NOT NULL,
    user_id BIGINT,
    product_id BIGINT,
    category_id INT,
    action VARCHAR(20),
    action_time DATETIME
) ENGINE=OLAP
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 5
PROPERTIES (
    "replication_num" = "1",
    "bloom_filter_columns" = "user_id,product_id"
);

CREATE INDEX idx_category ON demo_combined_index(category_id) USING BITMAP;

CREATE INDEX idx_action ON demo_combined_index(action) USING BITMAP;

INSERT INTO demo_combined_index VALUES
(1, 10001, 100001, 1, 'view', '2024-01-01 10:00:00'),
(2, 10001, 100001, 1, 'click', '2024-01-01 10:05:00'),
(3, 10002, 100002, 2, 'view', '2024-01-01 11:00:00'),
(4, 10001, 100003, 1, 'purchase', '2024-01-01 12:00:00'),
(5, 10003, 100001, 1, 'view', '2024-01-01 13:00:00');

EXPLAIN SELECT * FROM demo_combined_index WHERE user_id = 10001;

EXPLAIN SELECT * FROM demo_combined_index WHERE user_id = 10001 AND category_id = 1;

EXPLAIN SELECT * FROM demo_combined_index WHERE user_id = 10001 AND action = 'view';

EXPLAIN SELECT * FROM demo_combined_index WHERE user_id = 10001 AND category_id = 1 AND action = 'view';

-- =====================================================
-- 7. 索引管理
-- =====================================================

SHOW INDEX FROM demo_bitmap_index;

DROP INDEX idx_status ON demo_bitmap_index;

SHOW INDEX FROM demo_bitmap_index;

-- =====================================================
-- 8. 索引选择建议
-- =====================================================

SELECT 
    '前缀索引' AS index_type,
    'Duplicate/Aggregate/Unique Key' AS auto_create,
    'Key列的前缀查询' AS best_for,
    '自动创建，无需维护' AS note
UNION ALL
SELECT 
    'Bitmap索引',
    '否',
    '低基数列（性别、状态、地区）',
    '等值查询，多列组合查询'
UNION ALL
SELECT 
    'Bloom Filter',
    '否',
    '高基数列（ID、订单号）',
    '快速判断值是否存在，减少IO'
UNION ALL
SELECT 
    '倒排索引',
    '否',
    '全文检索、文本搜索',
    '支持MATCH查询，适合英文'
UNION ALL
SELECT 
    'Ngram BF',
    '否',
    '中文全文检索',
    '支持LIKE查询优化，适合中文';

-- =====================================================
-- 9. 清理演示表
-- =====================================================

DROP TABLE IF EXISTS demo_prefix_index;
DROP TABLE IF EXISTS demo_bitmap_index;
DROP TABLE IF EXISTS demo_bloom_filter;
DROP TABLE IF EXISTS demo_inverted_index;
DROP TABLE IF EXISTS demo_ngram_index;
DROP TABLE IF EXISTS demo_combined_index;
