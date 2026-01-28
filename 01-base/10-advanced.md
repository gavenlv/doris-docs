# 高级功能

## 物化视图

### 创建物化视图

```sql
-- 基本物化视图
CREATE MATERIALIZED VIEW mv_user_city_stats
AS SELECT city, COUNT(*) as user_count, AVG(age) as avg_age
FROM users
GROUP BY city;

-- 物化视图 + WHERE
CREATE MATERIALIZED VIEW mv_user_city_stats_filtered
AS SELECT city, COUNT(*) as user_count, AVG(age) as avg_age
FROM users
WHERE age > 25
GROUP BY city;

-- 物化视图 + JOIN
CREATE MATERIALIZED VIEW mv_user_order_stats
AS SELECT u.user_id, u.user_name, COUNT(o.order_id) as order_count, SUM(o.amount) as total_amount
FROM users u
LEFT JOIN orders o ON u.user_id = o.user_id
GROUP BY u.user_id, u.user_name;
```

### 查看物化视图

```sql
-- 查看所有物化视图
SHOW MATERIALIZED VIEWS;

-- 查看指定物化视图
SHOW MATERIALIZED VIEWS WHERE DatabaseName = 'my_database';

-- 查看物化视图结构
DESCRIBE mv_user_city_stats;

-- 查看物化视图创建语句
SHOW CREATE MATERIALIZED VIEW mv_user_city_stats;
```

### 删除物化视图

```sql
-- 删除物化视图
DROP MATERIALIZED VIEW mv_user_city_stats;

-- 删除物化视图（如果存在）
DROP MATERIALIZED VIEW IF EXISTS mv_user_city_stats;
```

### 物化视图自动重写

```sql
-- 查询自动使用物化视图
SELECT city, COUNT(*) as user_count, AVG(age) as avg_age
FROM users
GROUP BY city;

-- 查询自动使用物化视图（带 WHERE）
SELECT city, COUNT(*) as user_count, AVG(age) as avg_age
FROM users
WHERE age > 25
GROUP BY city;
```

## 动态分区

### 创建动态分区表

```sql
-- 基本动态分区
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

-- 动态分区 + 按月
CREATE TABLE dynamic_orders_monthly (
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
    "dynamic_partition.time_unit" = "MONTH",
    "dynamic_partition.start" = "-12",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "dynamic_partition.buckets" = "10"
);
```

### 修改动态分区配置

```sql
-- 启用动态分区
ALTER TABLE dynamic_orders SET ("dynamic_partition.enable" = "true");

-- 修改时间范围
ALTER TABLE dynamic_orders SET (
    "dynamic_partition.start" = "-60",
    "dynamic_partition.end" = "7"
);

-- 修改时间单位
ALTER TABLE dynamic_orders SET ("dynamic_partition.time_unit" = "MONTH");

-- 修改分桶数量
ALTER TABLE dynamic_orders SET ("dynamic_partition.buckets" = "20");
```

### 查看动态分区

```sql
-- 查看动态分区配置
SHOW DYNAMIC PARTITION TABLES;

-- 查看表的动态分区配置
SHOW CREATE TABLE dynamic_orders;

-- 查看所有分区
SHOW PARTITIONS FROM dynamic_orders;
```

## Colocate Group

### 创建 Colocate Group

```sql
-- 创建 Colocate Group 表
CREATE TABLE colocate_users (
    user_id BIGINT,
    user_name VARCHAR(100),
    age INT,
    city VARCHAR(50)
)
DUPLICATE KEY(user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 10
PROPERTIES (
    "colocate_with" = "user_group"
);

-- 创建相同 Colocate Group 的表
CREATE TABLE colocate_orders (
    order_id BIGINT,
    user_id BIGINT,
    amount DECIMAL(10,2),
    order_date DATE
)
DUPLICATE KEY(order_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 10
PROPERTIES (
    "colocate_with" = "user_group"
);
```

### 查看 Colocate Group

```sql
-- 查看所有 Colocate Group
SHOW COLOCATE GROUP;

-- 查看指定 Colocate Group
SHOW COLOCATE GROUP WHERE GroupName = 'user_group';

-- 查看表的 Colocate Group
SHOW CREATE TABLE colocate_users;
```

### Colocate Join 优化

```sql
-- Colocate Join 自动优化
SELECT u.user_name, o.order_id, o.amount
FROM colocate_users u
INNER JOIN colocate_orders o ON u.user_id = o.user_id;

-- 查看执行计划（确认 Colocate Join）
EXPLAIN SELECT u.user_name, o.order_id, o.amount
FROM colocate_users u
INNER JOIN colocate_orders o ON u.user_id = o.user_id;
```

## Rollup

### 创建 Rollup

```sql
-- 创建 Rollup
ALTER TABLE users ADD ROLLUP rollup_city_age (city, age);

-- 创建 Rollup + 聚合
ALTER TABLE orders ADD ROLLUP rollup_user_amount (user_id, amount);

-- 创建 Rollup + 替换
ALTER TABLE users ADD ROLLUP rollup_city_age (city, age) REPLACE;
```

### 查看 Rollup

```sql
-- 查看所有 Rollup
SHOW ROLLUP FROM users;

-- 查看指定 Rollup
SHOW ROLLUP FROM users WHERE RollupName = 'rollup_city_age';

-- 查看表的所有索引（包括 Rollup）
SHOW INDEX FROM users;
```

### 删除 Rollup

```sql
-- 删除 Rollup
ALTER TABLE users DROP ROLLUP rollup_city_age;

-- 删除 Rollup（如果存在）
ALTER TABLE users DROP ROLLUP IF EXISTS rollup_city_age;
```

### Rollup 自动使用

```sql
-- 查询自动使用 Rollup
SELECT city, AVG(age) as avg_age
FROM users
GROUP BY city;

-- 查看执行计划（确认 Rollup）
EXPLAIN SELECT city, AVG(age) as avg_age
FROM users
GROUP BY city;
```

## 变更数据

### Schema Change

```sql
-- 添加列
ALTER TABLE users ADD COLUMN email VARCHAR(100);

-- 添加多列
ALTER TABLE users ADD COLUMN phone VARCHAR(20), ADD COLUMN address VARCHAR(200);

-- 修改列类型
ALTER TABLE users MODIFY COLUMN age INT;

-- 删除列
ALTER TABLE users DROP COLUMN email;

-- 重命名列
ALTER TABLE users RENAME COLUMN user_name TO name;

-- 重排序列
ALTER TABLE users MODIFY COLUMN age AFTER name;
```

### Schema Change 参数

```sql
-- 设置超时时间
ALTER TABLE users ADD COLUMN email VARCHAR(100) PROPERTIES ("timeout" = "3600");

-- 设置并行度
ALTER TABLE users ADD COLUMN email VARCHAR(100) PROPERTIES ("light_schema_change" = "true");
```

### 查看 Schema Change

```sql
-- 查看 Schema Change 任务
SHOW ALTER TABLE COLUMN;

-- 查看指定 Schema Change 任务
SHOW ALTER TABLE COLUMN WHERE TableName = 'users';

-- 取消 Schema Change
CANCEL ALTER TABLE COLUMN FROM users;
```

## 数据备份与恢复

### 创建快照

```sql
-- 创建快照
CREATE SNAPSHOT snapshot_20240101 FOR my_database;

-- 创建快照（指定保留时间）
CREATE SNAPSHOT snapshot_20240101 FOR my_database PROPERTIES ("timeout" = "3600");
```

### 查看快照

```sql
-- 查看所有快照
SHOW SNAPSHOT;

-- 查看指定快照
SHOW SNAPSHOT WHERE SnapshotName = 'snapshot_20240101';

-- 查看快照详细信息
SHOW SNAPSHOT WHERE SnapshotName = 'snapshot_20240101'\G
```

### 恢复快照

```sql
-- 恢复快照
RESTORE SNAPSHOT snapshot_20240101 FROM my_database;

-- 恢复快照（指定表）
RESTORE SNAPSHOT snapshot_20240101 FROM my_database
PROPERTIES ("backup_timestamp" = "2024-01-01 00:00:00");

-- 恢复快照（替换现有表）
RESTORE SNAPSHOT snapshot_20240101 FROM my_database
PROPERTIES ("backup_timestamp" = "2024-01-01 00:00:00", "replication_num" = "1");
```

### 删除快照

```sql
-- 删除快照
DROP SNAPSHOT snapshot_20240101;

-- 删除快照（如果存在）
DROP SNAPSHOT IF EXISTS snapshot_20240101;
```

## 数据导出

### 导出为 CSV

```sql
-- 导出为 CSV
SELECT * FROM users
INTO OUTFILE "/tmp/users.csv"
FORMAT AS CSV
PROPERTIES (
    "delimiter" = ",",
    "line_delimiter" = "\n"
);

-- 导出到 HDFS
SELECT * FROM users
INTO OUTFILE "hdfs://namenode:8020/export/users.csv"
FORMAT AS CSV
PROPERTIES (
    "delimiter" = ",",
    "line_delimiter" = "\n"
)
WITH BROKER hdfs_broker
(
    "username" = "hdfs",
    "password" = "password"
);
```

## 数据导入

### Stream Load

```bash
# 导入 CSV 文件
curl --location-trusted -u root: \
    -H "label:label_20240101" \
    -H "column_separator:," \
    -T users.csv \
    http://127.0.0.1:8030/api/my_database/users/_stream_load

# 导入 JSON 文件
curl --location-trusted -u root: \
    -H "label:label_20240101" \
    -H "format:json" \
    -T users.json \
    http://127.0.0.1:8030/api/my_database/users/_stream_load
```

### Broker Load

```sql
-- 从 HDFS 导入
LOAD LABEL label_hdfs_20240101
(
    DATA INFILE ("hdfs://namenode:8020/data/users.csv")
    INTO TABLE users
    COLUMNS TERMINATED BY ','
    FORMAT AS 'CSV'
    (user_id, user_name, age, city, register_date)
)
WITH BROKER hdfs_broker
(
    "username" = "hdfs",
    "password" = "password"
)
PROPERTIES (
    "timeout" = "3600"
);
```

### Routine Load

```sql
-- 从 Kafka 导入
CREATE ROUTINE LOAD my_database.kafka_users ON users
PROPERTIES (
    "format" = "json",
    "jsonpaths" = "$.user_id, $.user_name, $.age, $.city, $.register_date"
)
FROM KAFKA (
    "kafka_broker_list" = "kafka-broker1:9092,kafka-broker2:9092",
    "kafka_topic" = "users_topic",
    "kafka_partitions" = "0,1,2",
    "kafka_offsets" = "OFFSET_BEGINNING"
);
```

## 高级查询优化

### 查询重写

```sql
-- 物化视图自动重写
SELECT city, COUNT(*) as user_count, AVG(age) as avg_age
FROM users
GROUP BY city;

-- Rollup 自动重写
SELECT city, AVG(age) as avg_age
FROM users
GROUP BY city;
```

### 查询缓存

```sql
-- 启用查询缓存
SET GLOBAL enable_query_cache = true;

-- 查看查询缓存状态
SHOW VARIABLES LIKE 'enable_query_cache';

-- 清空查询缓存
ADMIN SET FRONTEND CONFIG ("enable_query_cache" = "false");
```

### 查询超时

```sql
-- 设置查询超时
SET query_timeout = 300;

-- 查看查询超时设置
SHOW VARIABLES LIKE 'query_timeout';
```

## 高级配置

### FE 配置

```sql
-- 查看 FE 配置
ADMIN SHOW FRONTEND CONFIG LIKE '%query%';

-- 修改 FE 配置
ADMIN SET FRONTEND CONFIG ("max_query_memory" = "8589934592");

-- 重置 FE 配置
ADMIN SET FRONTEND CONFIG ("max_query_memory" = "default");
```

### BE 配置

```sql
-- 查看 BE 配置
ADMIN SHOW BACKEND CONFIG LIKE '%memory%';

-- 修改 BE 配置
ADMIN SET FRONTEND CONFIG ("default_max_query_instances" = "10");
```

## 高级功能最佳实践

### 1. 使用物化视图加速查询

```sql
-- 创建物化视图
CREATE MATERIALIZED VIEW mv_user_city_stats
AS SELECT city, COUNT(*) as user_count, AVG(age) as avg_age
FROM users
GROUP BY city;

-- 查询自动使用物化视图
SELECT city, COUNT(*) as user_count, AVG(age) as avg_age
FROM users
GROUP BY city;
```

### 2. 使用动态分区自动管理分区

```sql
-- 创建动态分区表
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
    "dynamic_partition.end" = "3"
);
```

### 3. 使用 Colocate Group 加速 JOIN

```sql
-- 创建 Colocate Group 表
CREATE TABLE colocate_users (
    user_id BIGINT,
    user_name VARCHAR(100),
    age INT,
    city VARCHAR(50)
)
DUPLICATE KEY(user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 10
PROPERTIES (
    "colocate_with" = "user_group"
);

-- Colocate Join 自动优化
SELECT u.user_name, o.order_id, o.amount
FROM colocate_users u
INNER JOIN colocate_orders o ON u.user_id = o.user_id;
```

## 常见问题

### 物化视图未生效

```sql
-- 检查物化视图是否存在
SHOW MATERIALIZED VIEWS;

-- 检查查询是否匹配物化视图
EXPLAIN SELECT city, COUNT(*) as user_count, AVG(age) as avg_age
FROM users
GROUP BY city;
```

### 动态分区未创建

```sql
-- 检查动态分区配置
SHOW DYNAMIC PARTITION TABLES;

-- 检查动态分区是否启用
SHOW CREATE TABLE dynamic_orders;

-- 手动触发动态分区
ADMIN SET FRONTEND CONFIG ("dynamic_partition_check_interval_seconds" = "60");
```

### Colocate Join 未生效

```sql
-- 检查 Colocate Group
SHOW COLOCATE GROUP;

-- 检查表的 Colocate Group
SHOW CREATE TABLE colocate_users;

-- 查看执行计划
EXPLAIN SELECT u.user_name, o.order_id, o.amount
FROM colocate_users u
INNER JOIN colocate_orders o ON u.user_id = o.user_id;
```

## 参考资料

- [Doris 官方文档](https://doris.apache.org/docs/)
- [物化视图文档](https://doris.apache.org/docs/query-acceleration/materialized-view/)
- [动态分区文档](https://doris.apache.org/docs/data-partition/dynamic-partition/)
- [Colocate Group 文档](https://doris.apache.org/docs/query-acceleration/colocation-join/)
- [Rollup 文档](https://doris.apache.org/docs/table-design/rollup/)
