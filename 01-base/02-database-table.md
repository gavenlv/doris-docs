# 数据库和表管理

## 数据库管理

### 创建数据库

```sql
-- 创建数据库
CREATE DATABASE my_database;

-- 创建数据库并指定字符集
CREATE DATABASE my_database CHARACTER SET 'utf8mb4';

-- 创建数据库并指定注释
CREATE DATABASE my_database COMMENT 'My first database';
```

### 查看数据库

```sql
-- 查看所有数据库
SHOW DATABASES;

-- 查看当前数据库
SELECT DATABASE();

-- 查看数据库创建语句
SHOW CREATE DATABASE my_database;
```

### 使用数据库

```sql
-- 切换到指定数据库
USE my_database;
```

### 修改数据库

```sql
-- 修改数据库注释
ALTER DATABASE my_database SET COMMENT 'Updated comment';
```

### 删除数据库

```sql
-- 删除数据库
DROP DATABASE my_database;

-- 删除数据库（如果存在）
DROP DATABASE IF EXISTS my_database;
```

## 表管理

### 创建表

#### 基本语法

```sql
CREATE TABLE [IF NOT EXISTS] [database.]table_name
(
    column_definition1,
    column_definition2,
    ...
    [index_definition1],
    [index_definition2],
    ...
)
[ENGINE = [olap|mysql|elasticsearch|hive|iceberg|hudi|jdbc]]
[KEY (key_column1, key_column2, ...)]
[COMMENT "table comment"]
[PARTITION BY partition_definition]
[DISTRIBUTED BY HASH (distribution_column1, ...) [BUCKETS bucket_num]]
[PROPERTIES ("key" = "value", ...)]
```

#### Duplicate Key 表（允许重复）

```sql
CREATE TABLE users (
    user_id BIGINT,
    user_name VARCHAR(100),
    age INT,
    city VARCHAR(50),
    register_date DATE
)
DUPLICATE KEY(user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 10
PROPERTIES (
    "replication_num" = "1"
);
```

#### Aggregate Key 表（聚合）

```sql
CREATE TABLE sales (
    user_id BIGINT,
    product_id BIGINT,
    amount DECIMAL(10,2),
    sales_count BIGINT SUM DEFAULT '0'
)
AGGREGATE KEY(user_id, product_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 10
PROPERTIES (
    "replication_num" = "1"
);
```

#### Unique Key 表（唯一）

```sql
CREATE TABLE unique_users (
    user_id BIGINT,
    user_name VARCHAR(100),
    age INT,
    city VARCHAR(50)
)
UNIQUE KEY(user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 10
PROPERTIES (
    "replication_num" = "1"
);
```

### 分区表

#### Range 分区

```sql
CREATE TABLE orders (
    order_id BIGINT,
    user_id BIGINT,
    amount DECIMAL(10,2),
    order_date DATE
)
DUPLICATE KEY(order_id)
PARTITION BY RANGE(order_date) (
    PARTITION p202401 VALUES [('2024-01-01'), ('2024-02-01')),
    PARTITION p202402 VALUES [('2024-02-01'), ('2024-03-01')),
    PARTITION p202403 VALUES [('2024-03-01'), ('2024-04-01'))
)
DISTRIBUTED BY HASH(order_id) BUCKETS 10
PROPERTIES (
    "replication_num" = "1"
);
```

#### List 分区

```sql
CREATE TABLE sales_by_region (
    order_id BIGINT,
    region VARCHAR(50),
    amount DECIMAL(10,2)
)
DUPLICATE KEY(order_id)
PARTITION BY LIST(region) (
    PARTITION p_east VALUES IN ('Beijing', 'Shanghai', 'Hangzhou'),
    PARTITION p_west VALUES IN ('Chengdu', 'Chongqing', 'Xi\'an'),
    PARTITION p_south VALUES IN ('Guangzhou', 'Shenzhen', 'Foshan')
)
DISTRIBUTED BY HASH(order_id) BUCKETS 10
PROPERTIES (
    "replication_num" = "1"
);
```

### 查看表

```sql
-- 查看当前数据库的所有表
SHOW TABLES;

-- 查看表结构
DESCRIBE table_name;
-- 或
DESC table_name;

-- 查看建表语句
SHOW CREATE TABLE table_name;

-- 查看表的详细信息
SHOW FULL COLUMNS FROM table_name;

-- 查看表的分区信息
SHOW PARTITIONS FROM table_name;

-- 查看表的副本分布
SHOW TABLET FROM table_name;
```

### 修改表

#### 添加列

```sql
-- 添加单列
ALTER TABLE users ADD COLUMN email VARCHAR(100);

-- 添加多列
ALTER TABLE users ADD COLUMN phone VARCHAR(20), ADD COLUMN address VARCHAR(200);

-- 添加列到指定位置
ALTER TABLE users ADD COLUMN email VARCHAR(100) AFTER user_name;

-- 添加列到第一位
ALTER TABLE users ADD COLUMN id BIGINT FIRST;
```

#### 修改列

```sql
-- 修改列类型
ALTER TABLE users MODIFY COLUMN age INT;

-- 修改列名
ALTER TABLE users RENAME COLUMN user_name TO name;

-- 修改列类型和位置
ALTER TABLE users MODIFY COLUMN age INT AFTER name;
```

#### 删除列

```sql
-- 删除单列
ALTER TABLE users DROP COLUMN email;

-- 删除多列
ALTER TABLE users DROP COLUMN phone, DROP COLUMN address;
```

#### 添加分区

```sql
-- 添加 Range 分区
ALTER TABLE orders ADD PARTITION p202404 VALUES [('2024-04-01'), ('2024-05-01'));

-- 添加 List 分区
ALTER TABLE sales_by_region ADD PARTITION p_north VALUES IN ('Beijing', 'Tianjin');
```

#### 删除分区

```sql
-- 删除分区
ALTER TABLE orders DROP PARTITION p202401;
```

### 重命名表

```sql
-- 重命名表
ALTER TABLE users RENAME new_users;

-- 重命名表（如果存在）
ALTER TABLE IF EXISTS users RENAME new_users;
```

### 删除表

```sql
-- 删除表
DROP TABLE users;

-- 删除表（如果存在）
DROP TABLE IF EXISTS users;

-- 强制删除表
DROP TABLE users FORCE;
```

### 清空表

```sql
-- 清空表数据
TRUNCATE TABLE users;

-- 清空表（如果存在）
TRUNCATE TABLE IF EXISTS users;
```

## 表属性配置

### 常用属性

```sql
CREATE TABLE example (
    id BIGINT,
    name VARCHAR(100)
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 10
PROPERTIES (
    "replication_num" = "3",              -- 副本数量
    "storage_type" = "COLUMN",            -- 存储类型：COLUMN（列存）或 ROW（行存）
    "compression" = "LZ4",                -- 压缩算法：LZ4, ZSTD, SNAPPY
    "in_memory" = "false",                -- 是否内存表
    "enable_unique_key_merge_on_write" = "true",  -- Unique Key 写时合并
    "bloom_filter_columns" = "id",        -- Bloom Filter 列
    "colocate_with" = "group1"            -- Colocate 分组
);
```

### 动态分区

```sql
CREATE TABLE dynamic_orders (
    order_id BIGINT,
    user_id BIGINT,
    amount DECIMAL(10,2),
    order_date DATE
)
DUPLICATE KEY(order_id)
PARTITION BY RANGE(order_date) ()
DISTRIBUTED BY HASH(order_id) BUCKETS 10
PROPERTIES (
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-30",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "dynamic_partition.buckets" = "10"
);
```

## 索引管理

### 创建索引

```sql
-- 创建 BITMAP 索引
CREATE INDEX idx_city_bitmap ON users (city) USING BITMAP;

-- 创建 Bloom Filter 索引
ALTER TABLE users SET ("bloom_filter_columns" = "city");

-- 创建 NGram Bloom Filter 索引
CREATE INDEX idx_name_ngram ON users (user_name) USING NGRAM_BLOOM;
```

### 删除索引

```sql
-- 删除 BITMAP 索引
DROP INDEX idx_city_bitmap ON users;

-- 删除 Bloom Filter 索引
ALTER TABLE users UNSET ("bloom_filter_columns");
```

## 数据模型选择指南

| 数据模型 | 适用场景 | 特点 |
|---------|---------|------|
| Duplicate Key | 需要保留所有记录 | 允许重复，查询灵活 |
| Aggregate Key | 需要聚合统计 | 自动聚合，性能高 |
| Unique Key | 需要唯一性约束 | 保证数据唯一 |

## 下一步

- [增删改查操作](./03-crud.md) - 学习基本的 CRUD 操作
