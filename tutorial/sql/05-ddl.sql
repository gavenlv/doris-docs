-- =====================================================
-- 第05章：数据库与表管理 (DDL)
-- 演示数据库/表的创建、修改、删除操作
-- 所需权限：CREATE_PRIV, DROP_PRIV ON tutorial
-- =====================================================

USE tutorial;

-- =====================================================
-- 1. 数据库管理
-- =====================================================

CREATE DATABASE IF NOT EXISTS demo_db;

SHOW DATABASES LIKE 'demo%';

SHOW CREATE DATABASE demo_db;

DROP DATABASE IF EXISTS demo_db;

-- =====================================================
-- 2. 创建表 - 完整语法
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_ddl_users (
    user_id BIGINT NOT NULL COMMENT '用户ID',
    username VARCHAR(50) NOT NULL COMMENT '用户名',
    email VARCHAR(100) COMMENT '邮箱',
    phone VARCHAR(20) COMMENT '手机号',
    age INT COMMENT '年龄',
    gender TINYINT COMMENT '性别: 1-男, 2-女',
    city VARCHAR(50) COMMENT '城市',
    vip_level TINYINT DEFAULT 1 COMMENT 'VIP等级',
    register_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '注册时间',
    update_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '更新时间'
) ENGINE=OLAP
DUPLICATE KEY(user_id)
COMMENT '用户表 - DDL演示'
PARTITION BY RANGE(register_time) ()
DISTRIBUTED BY HASH(user_id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1",
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "MONTH",
    "dynamic_partition.start" = "-12",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "dynamic_partition.buckets" = "3"
);

SHOW CREATE TABLE demo_ddl_users;

DESC demo_ddl_users;

SHOW ALL TABLES LIKE 'demo_ddl%';

-- =====================================================
-- 3. 列操作
-- =====================================================

ALTER TABLE demo_ddl_users ADD COLUMN address VARCHAR(200) COMMENT '地址' AFTER city;

DESC demo_ddl_users;

ALTER TABLE demo_ddl_users ADD COLUMN province VARCHAR(50) COMMENT '省份' AFTER city;

DESC demo demo_ddl_users;

ALTER TABLE demo_ddl_users DROP COLUMN address;

DESC demo_ddl_users;

ALTER TABLE demo_ddl_users MODIFY COLUMN phone VARCHAR(30) COMMENT '手机号(扩展长度)';

DESC demo_ddl_users;

ALTER TABLE demo_ddl_users RENAME COLUMN gender TO sex;

DESC demo_ddl_users;

ALTER TABLE demo_ddl_users ADD COLUMN score INT DEFAULT 0 COMMENT '积分' AFTER vip_level;

DESC demo_ddl_users;

-- =====================================================
-- 4. 分区操作
-- =====================================================

ALTER TABLE demo_ddl_users ADD PARTITION p202401 VALUES [('2024-01-01 00:00:00'), ('2024-02-01 00:00:00'));

SHOW PARTITIONS FROM demo_ddl_users;

ALTER TABLE demo_ddl_users ADD PARTITION p202402 VALUES [('2024-02-01 00:00:00'), ('2024-03-01 00:00:00'));

SHOW PARTITIONS FROM demo_ddl_users ORDER BY PartitionName;

ALTER TABLE demo_ddl_users DROP PARTITION p202401;

SHOW PARTITIONS FROM demo_ddl_users;

-- =====================================================
-- 5. 表属性修改
-- =====================================================

ALTER TABLE demo_ddl_users SET ("replication_num" = "1");

SHOW CREATE TABLE demo_ddl_users;

ALTER TABLE demo_ddl_users RENAME demo_ddl_users_v2;

SHOW TABLES LIKE 'demo_ddl%';

ALTER TABLE demo_ddl_users_v2 RENAME demo_ddl_users;

SHOW TABLES LIKE 'demo_ddl%';

-- =====================================================
-- 6. Schema Change（异步修改）
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_schema_change (
    id INT NOT NULL,
    name VARCHAR(50),
    age INT
) ENGINE=OLAP
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 1
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_schema_change VALUES (1, '张三', 28), (2, '李四', 35);

SELECT * FROM demo_schema_change;

ALTER TABLE demo_schema_change ADD COLUMN city VARCHAR(50) DEFAULT '北京';

SHOW ALTER TABLE COLUMN FROM demo_schema_change;

DESC demo_schema_change;

SELECT SLEEP(3);

SELECT * FROM demo_schema_change;

ALTER TABLE demo_schema_change MODIFY COLUMN name VARCHAR(100);

SHOW ALTER TABLE COLUMN FROM demo_schema_change;

SELECT SLEEP(3);

DESC demo_schema_change;

-- =====================================================
-- 7. 临时表
-- =====================================================

CREATE TEMPORARY TABLE demo_temp_table (
    id INT,
    name VARCHAR(50)
);

INSERT INTO demo_temp_table VALUES (1, '临时数据');

SELECT * FROM demo_temp_table;

-- =====================================================
-- 8. 视图
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_view_base (
    id INT NOT NULL,
    name VARCHAR(50),
    department VARCHAR(50),
    salary DECIMAL(10, 2)
) ENGINE=OLAP
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 1
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_view_base VALUES
(1, '张三', '技术部', 15000.00),
(2, '李四', '销售部', 12000.00),
(3, '王五', '技术部', 18000.00),
(4, '赵六', '人事部', 10000.00);

CREATE VIEW demo_employee_view AS
SELECT 
    id,
    name,
    department,
    salary,
    CASE 
        WHEN salary >= 15000 THEN '高薪'
        WHEN salary >= 10000 THEN '中等'
        ELSE '低薪'
    END AS salary_level
FROM demo_view_base;

SHOW CREATE VIEW demo_employee_view;

SELECT * FROM demo_employee_view;

DROP VIEW IF EXISTS demo_employee_view;

-- =====================================================
-- 9. 表结构复制
-- =====================================================

CREATE TABLE demo_ddl_users_copy LIKE demo_ddl_users;

DESC demo_ddl_users_copy;

SHOW CREATE TABLE demo_ddl_users_copy;

DROP TABLE IF EXISTS demo_ddl_users_copy;

-- =====================================================
-- 10. 表信息查看
-- =====================================================

SHOW TABLE STATUS LIKE 'demo_ddl%';

SHOW TABLET FROM demo_ddl_users;

SHOW DATA FROM demo_ddl_users;

SHOW INDEX FROM demo_ddl_users;

-- =====================================================
-- 11. 表删除与恢复
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_drop_table (
    id INT,
    name VARCHAR(50)
) ENGINE=OLAP
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 1
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_drop_table VALUES (1, 'test');

SELECT * FROM demo_drop_table;

DROP TABLE IF EXISTS demo_drop_table;

SHOW TABLES LIKE 'demo_drop%';

-- =====================================================
-- 12. 清理演示表
-- =====================================================

DROP TABLE IF EXISTS demo_ddl_users;
DROP TABLE IF EXISTS demo_schema_change;
DROP TABLE IF EXISTS demo_view_base;
DROP TABLE IF EXISTS demo_ddl_users_copy;
