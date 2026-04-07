-- =====================================================
-- 第04章：数据类型全解
-- 演示 Doris 支持的各种数据类型及其特性
-- 所需权限：CREATE_PRIV ON tutorial
-- =====================================================

USE tutorial;

-- =====================================================
-- 1. 数值类型
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_numeric_types (
    id INT NOT NULL,
    tiny_int TINYINT COMMENT '1字节整数 -128~127',
    small_int SMALLINT COMMENT '2字节整数 -32768~32767',
    int_col INT COMMENT '4字节整数',
    big_int BIGINT COMMENT '8字节整数',
    large_int LARGEINT COMMENT '16字节大整数',
    float_col FLOAT COMMENT '4字节浮点数',
    double_col DOUBLE COMMENT '8字节双精度',
    decimal_col DECIMAL(10, 2) COMMENT '定点数 精度10 小数位2'
) ENGINE=OLAP
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 1
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_numeric_types VALUES
(1, 127, 32767, 2147483647, 9223372036854775807, 170141183460469231731687303715884105727, 3.14159, 3.14159265358979, 12345.67),
(2, -128, -32768, -2147483648, -9223372036854775808, -170141183460469231731687303715884105728, -3.14159, -3.14159265358979, -12345.67);

SELECT * FROM demo_numeric_types;

SELECT 
    id,
    tiny_int + 1 AS tiny_int_plus,
    int_col * 2 AS int_double,
    ROUND(double_col, 2) AS double_rounded,
    decimal_col + 100.50 AS decimal_add
FROM demo_numeric_types;

-- =====================================================
-- 2. 字符串类型
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_string_types (
    id INT NOT NULL,
    char_col CHAR(10) COMMENT '定长字符串 最大255',
    varchar_col VARCHAR(100) COMMENT '变长字符串 最大65533',
    string_col STRING COMMENT '长字符串 最大2147483643'
) ENGINE=OLAP
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 1
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_string_types VALUES
(1, 'hello', 'This is a varchar string', 'This is a very long string that can store up to 2GB of data'),
(2, 'world', 'Another varchar example', REPEAT('A', 1000));

SELECT 
    id,
    char_col,
    LENGTH(char_col) AS char_length,
    varchar_col,
    LENGTH(varchar_col) AS varchar_length,
    LEFT(string_col, 50) AS string_preview,
    LENGTH(string_col) AS string_length
FROM demo_string_types;

-- =====================================================
-- 3. 日期时间类型
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_datetime_types (
    id INT NOT NULL,
    date_col DATE COMMENT '日期 YYYY-MM-DD',
    datetime_col DATETIME COMMENT '日期时间 YYYY-MM-DD HH:MI:SS',
    datetimev2_col DATETIMEV2(3) COMMENT '日期时间 带毫秒精度'
) ENGINE=OLAP
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 1
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_datetime_types VALUES
(1, '2024-01-01', '2024-01-01 12:30:45', '2024-01-01 12:30:45.123'),
(2, CURRENT_DATE(), CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP());

SELECT 
    id,
    date_col,
    YEAR(date_col) AS year,
    MONTH(date_col) AS month,
    DAY(date_col) AS day,
    datetime_col,
    HOUR(datetime_col) AS hour,
    MINUTE(datetime_col) AS minute,
    SECOND(datetime_col) AS second,
    datetimev2_col,
    DATE_FORMAT(datetime_col, '%Y年%m月%d日 %H:%i:%s') AS formatted_date
FROM demo_datetime_types;

SELECT 
    id,
    date_col,
    DATE_ADD(date_col, INTERVAL 7 DAY) AS add_7_days,
    DATE_SUB(date_col, INTERVAL 1 MONTH) AS sub_1_month,
    DATEDIFF('2024-01-10', date_col) AS days_diff,
    datetime_col,
    DATE_ADD(datetime_col, INTERVAL 2 HOUR) AS add_2_hours
FROM demo_datetime_types;

-- =====================================================
-- 4. 复杂类型 - Array
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_array_type (
    id INT NOT NULL,
    tags ARRAY<VARCHAR(50)> COMMENT '标签数组',
    scores ARRAY<INT> COMMENT '分数数组'
) ENGINE=OLAP
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 1
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_array_type VALUES
(1, ['tag1', 'tag2', 'tag3'], [90, 85, 92]),
(2, ['apple', 'banana', 'orange', 'grape'], [88, 76, 95, 82]);

SELECT 
    id,
    tags,
    scores,
    ARRAY_LENGTH(tags) AS tag_count,
    ARRAY_LENGTH(scores) AS score_count,
    tags[1] AS first_tag,
    scores[1] AS first_score
FROM demo_array_type;

SELECT 
    id,
    tags,
    ARRAY_JOIN(tags, ', ') AS tags_str,
    scores,
    ARRAY_MAX(scores) AS max_score,
    ARRAY_MIN(scores) AS min_score,
    ARRAY_AVG(scores) AS avg_score
FROM demo_array_type;

-- =====================================================
-- 5. 复杂类型 - Map
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_map_type (
    id INT NOT NULL,
    attributes MAP<VARCHAR(50), VARCHAR(100)> COMMENT '属性Map'
) ENGINE=OLAP
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 1
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_map_type VALUES
(1, {'color': 'red', 'size': 'large', 'brand': 'Nike'}),
(2, {'color': 'blue', 'size': 'medium', 'brand': 'Adidas', 'price': '99.99'});

SELECT 
    id,
    attributes,
    MAP_SIZE(attributes) AS attr_count,
    element_at(attributes, 'color') AS color_value,
    attributes['brand'] AS brand_value
FROM demo_map_type;

-- =====================================================
-- 6. 复杂类型 - Struct
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_struct_type (
    id INT NOT NULL,
    user_info STRUCT<name:VARCHAR(50), age:INT, city:VARCHAR(50)> COMMENT '用户信息结构体'
) ENGINE=OLAP
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 1
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_struct_type VALUES
(1, {'name': '张三', 'age': 28, 'city': '北京'}),
(2, {'name': '李四', 'age': 35, 'city': '上海'});

SELECT 
    id,
    user_info,
    user_info.name AS user_name,
    user_info.age AS user_age,
    user_info.city AS user_city
FROM demo_struct_type;

-- =====================================================
-- 7. JSON 类型
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_json_type (
    id INT NOT NULL,
    json_col JSON COMMENT 'JSON数据'
) ENGINE=OLAP
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 1
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_json_type VALUES
(1, '{"name": "张三", "age": 28, "city": "北京", "hobbies": ["reading", "swimming"]}'),
(2, '{"name": "李四", "age": 35, "city": "上海", "score": 95.5}');

SELECT 
    id,
    json_col,
    json_col.name AS name,
    json_col.age AS age,
    json_col.city AS city,
    CAST(json_col.age AS INT) AS age_int
FROM demo_json_type;

SELECT 
    id,
    json_col,
    JSON_QUERY(json_col, '$.name') AS name_value,
    JSON_VALUE(json_col, '$.age') AS age_value
FROM demo_json_type;

-- =====================================================
-- 8. Bitmap 类型（用于精确去重）
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_bitmap_type (
    id INT NOT NULL,
    date_key DATE,
    user_bitmap BITMAP BITMAP_UNION COMMENT '用户Bitmap'
) ENGINE=OLAP
AGGREGATE KEY(id, date_key)
DISTRIBUTED BY HASH(id) BUCKETS 1
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_bitmap_type VALUES
(1, '2024-01-01', to_bitmap(10001)),
(1, '2024-01-01', to_bitmap(10002)),
(1, '2024-01-01', to_bitmap(10003)),
(1, '2024-01-02', to_bitmap(10001)),
(1, '2024-01-02', to_bitmap(10004));

SELECT 
    id,
    date_key,
    BITMAP_UNION_COUNT(user_bitmap) AS uv_count,
    BITMAP_COUNT(user_bitmap) AS bitmap_size
FROM demo_bitmap_type
GROUP BY id, date_key
ORDER BY date_key;

-- =====================================================
-- 9. HLL 类型（用于近似去重）
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_hll_type (
    id INT NOT NULL,
    date_key DATE,
    user_hll HLL HLL_UNION COMMENT '用户HLL'
) ENGINE=OLAP
AGGREGATE KEY(id, date_key)
DISTRIBUTED BY HASH(id) BUCKETS 1
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_hll_type VALUES
(1, '2024-01-01', hll_hash('10001')),
(1, '2024-01-01', hll_hash('10002')),
(1, '2024-01-01', hll_hash('10003')),
(1, '2024-01-02', hll_hash('10001')),
(1, '2024-01-02', hll_hash('10004'));

SELECT 
    id,
    date_key,
    HLL_UNION_AGG(user_hll) AS uv_approx
FROM demo_hll_type
GROUP BY id, date_key
ORDER BY date_key;

-- =====================================================
-- 10. 类型转换
-- =====================================================

SELECT 
    CAST('123' AS INT) AS str_to_int,
    CAST(123.45 AS VARCHAR) AS float_to_str,
    CAST('2024-01-01' AS DATE) AS str_to_date,
    CAST('2024-01-01 12:30:45' AS DATETIME) AS str_to_datetime,
    CAST(1 AS BOOLEAN) AS int_to_bool;

-- =====================================================
-- 11. NULL 值处理
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_null_handling (
    id INT NOT NULL,
    name VARCHAR(50),
    age INT,
    salary DECIMAL(10, 2)
) ENGINE=OLAP
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 1
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_null_handling VALUES
(1, '张三', 28, 10000.00),
(2, '李四', NULL, 12000.00),
(3, NULL, 35, NULL),
(4, '王五', 30, 15000.00);

SELECT 
    id,
    name,
    age,
    salary,
    IFNULL(name, '未知') AS name_with_default,
    COALESCE(age, 0) AS age_with_default,
    COALESCE(salary, 0.00) AS salary_with_default,
    NULLIF(age, 28) AS age_null_if_28
FROM demo_null_handling;

-- =====================================================
-- 12. 清理演示表
-- =====================================================

DROP TABLE IF EXISTS demo_numeric_types;
DROP TABLE IF EXISTS demo_string_types;
DROP TABLE IF EXISTS demo_datetime_types;
DROP TABLE IF EXISTS demo_array_type;
DROP TABLE IF EXISTS demo_map_type;
DROP TABLE IF EXISTS demo_struct_type;
DROP TABLE IF EXISTS demo_json_type;
DROP TABLE IF EXISTS demo_bitmap_type;
DROP TABLE IF EXISTS demo_hll_type;
DROP TABLE IF EXISTS demo_null_handling;
