# 分区管理

## 分区类型

Doris 支持多种分区类型，适用于不同的业务场景：

| 分区类型 | 适用场景 | 特点 |
|---------|---------|------|
| Range 分区 | 时间序列、数值范围 | 按范围划分 |
| List 分区 | 枚举值、地区 | 按离散值划分 |
| 分桶 | 数据分布 | 按哈希分布 |

## Range 分区

### 创建 Range 分区表

```sql
-- 按日期分区
CREATE TABLE orders (
    order_id BIGINT,
    user_id BIGINT,
    product_id BIGINT,
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

-- 按数值分区
CREATE TABLE sales (
    sale_id BIGINT,
    product_id BIGINT,
    amount DECIMAL(10,2),
    sale_year INT
)
DUPLICATE KEY(sale_id)
PARTITION BY RANGE(sale_year) (
    PARTITION p2020 VALUES [('2020'), ('2021')),
    PARTITION p2021 VALUES [('2021'), ('2022')),
    PARTITION p2022 VALUES [('2022'), ('2023'))
)
DISTRIBUTED BY HASH(sale_id) BUCKETS 10
PROPERTIES (
    "replication_num" = "1"
);
```

### 添加 Range 分区

```sql
-- 添加单个分区
ALTER TABLE orders ADD PARTITION p202404 VALUES [('2024-04-01'), ('2024-05-01'));

-- 添加多个分区
ALTER TABLE orders ADD PARTITION p202405 VALUES [('2024-05-01'), ('2024-06-01')),
                       PARTITION p202406 VALUES [('2024-06-01'), ('2024-07-01'));
```

### 删除 Range 分区

```sql
-- 删除单个分区
ALTER TABLE orders DROP PARTITION p202401;

-- 删除多个分区
ALTER TABLE orders DROP PARTITION p202401, p202402;

-- 删除分区（如果存在）
ALTER TABLE orders DROP PARTITION IF EXISTS p202401;
```

### 清空 Range 分区

```sql
-- 清空分区数据
TRUNCATE TABLE orders PARTITION p202401;

-- 清空多个分区
TRUNCATE TABLE orders PARTITION (p202401, p202402);
```

## List 分区

### 创建 List 分区表

```sql
-- 按地区分区
CREATE TABLE sales_by_region (
    order_id BIGINT,
    region VARCHAR(50),
    amount DECIMAL(10,2),
    order_date DATE
)
DUPLICATE KEY(order_id)
PARTITION BY LIST(region) (
    PARTITION p_east VALUES IN ('Beijing', 'Shanghai', 'Hangzhou', 'Nanjing'),
    PARTITION p_west VALUES IN ('Chengdu', 'Chongqing', 'Xi\'an', 'Lanzhou'),
    PARTITION p_south VALUES IN ('Guangzhou', 'Shenzhen', 'Foshan', 'Dongguan'),
    PARTITION p_north VALUES IN ('Tianjin', 'Shijiazhuang', 'Taiyuan', 'Hohhot')
)
DISTRIBUTED BY HASH(order_id) BUCKETS 10
PROPERTIES (
    "replication_num" = "1"
);

-- 按状态分区
CREATE TABLE orders_status (
    order_id BIGINT,
    status VARCHAR(20),
    amount DECIMAL(10,2)
)
DUPLICATE KEY(order_id)
PARTITION BY LIST(status) (
    PARTITION p_pending VALUES IN ('pending', 'processing'),
    PARTITION p_completed VALUES IN ('completed', 'delivered'),
    PARTITION p_cancelled VALUES IN ('cancelled', 'refunded')
)
DISTRIBUTED BY HASH(order_id) BUCKETS 10
PROPERTIES (
    "replication_num" = "1"
);
```

### 添加 List 分区

```sql
-- 添加单个分区
ALTER TABLE sales_by_region ADD PARTITION p_central VALUES IN ('Wuhan', 'Changsha', 'Zhengzhou');

-- 添加多个分区
ALTER TABLE sales_by_region ADD PARTITION p_northeast VALUES IN ('Shenyang', 'Dalian', 'Changchun'),
                                 PARTITION p_northwest VALUES IN ('Urumqi', 'Lhasa', 'Yinchuan');
```

### 删除 List 分区

```sql
-- 删除分区
ALTER TABLE sales_by_region DROP PARTITION p_central;
```

## 分桶

### 创建分桶表

```sql
-- 基本分桶
CREATE TABLE users (
    user_id BIGINT,
    user_name VARCHAR(100),
    age INT,
    city VARCHAR(50)
)
DUPLICATE KEY(user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 10
PROPERTIES (
    "replication_num" = "1"
);

-- 多列分桶
CREATE TABLE orders (
    order_id BIGINT,
    user_id BIGINT,
    product_id BIGINT,
    amount DECIMAL(10,2)
)
DUPLICATE KEY(order_id)
DISTRIBUTED BY HASH(user_id, product_id) BUCKETS 10
PROPERTIES (
    "replication_num" = "1"
);

-- 随机分桶
CREATE TABLE logs (
    log_id BIGINT,
    log_message TEXT,
    log_time DATETIME
)
DUPLICATE KEY(log_id)
DISTRIBUTED BY RANDOM BUCKETS 10
PROPERTIES (
    "replication_num" = "1"
);
```

## 动态分区

### 创建动态分区表

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
    "dynamic_partition.buckets" = "10",
    "dynamic_partition.replication_num" = "1"
);
```

### 动态分区参数

| 参数 | 说明 | 示例 |
|------|------|------|
| dynamic_partition.enable | 是否启用动态分区 | true |
| dynamic_partition.time_unit | 时间单位 | DAY, WEEK, MONTH |
| dynamic_partition.start | 历史分区数量 | -30 |
| dynamic_partition.end | 未来分区数量 | 3 |
| dynamic_partition.prefix | 分区前缀 | p |
| dynamic_partition.buckets | 分桶数量 | 10 |

### 修改动态分区配置

```sql
-- 启用动态分区
ALTER TABLE dynamic_orders SET ("dynamic_partition.enable" = "true");

-- 修改时间范围
ALTER TABLE dynamic_orders SET (
    "dynamic_partition.start" = "-60",
    "dynamic_partition.end" = "7"
);

-- 修改分桶数量
ALTER TABLE dynamic_orders SET ("dynamic_partition.buckets" = "20");
```

## 分区管理

### 查看分区信息

```sql
-- 查看所有分区
SHOW PARTITIONS FROM orders;

-- 查看指定分区
SHOW PARTITIONS FROM orders WHERE PartitionName = 'p202401';

-- 查看分区详细信息
SHOW PARTITIONS FROM orders\G
```

### 查看分区数据

```sql
-- 查询指定分区
SELECT * FROM orders PARTITION (p202401);

-- 查询多个分区
SELECT * FROM orders PARTITION (p202401, p202402);

-- 统计分区数据量
SELECT
    PartitionName,
    Rows,
    DataSize
FROM information_schema.partitions
WHERE TableSchema = 'my_database' AND TableName = 'orders';
```

### 分区裁剪

```sql
-- 使用分区键查询（自动分区裁剪）
SELECT * FROM orders
WHERE order_date >= '2024-01-01' AND order_date < '2024-02-01';

-- 分区裁剪优化
SELECT * FROM orders
WHERE order_date BETWEEN '2024-01-01' AND '2024-01-31';
```

## 分区最佳实践

### 1. 选择合适的分区键

```sql
-- 好的分区键：查询条件中经常使用的列
CREATE TABLE orders (
    order_id BIGINT,
    user_id BIGINT,
    amount DECIMAL(10,2),
    order_date DATE
)
PARTITION BY RANGE(order_date) ...

-- 不好的分区键：基数太小的列
CREATE TABLE orders (
    order_id BIGINT,
    user_id BIGINT,
    amount DECIMAL(10,2),
    status VARCHAR(20)
)
PARTITION BY LIST(status) ...
```

### 2. 合理设置分区数量

```sql
-- 太少的分区：数据倾斜
PARTITION BY RANGE(order_date) (
    PARTITION p2024 VALUES [('2024-01-01'), ('2025-01-01'))
)

-- 太多的分区：元数据开销大
PARTITION BY RANGE(order_date) (
    PARTITION p20240101 VALUES [('2024-01-01'), ('2024-01-02')),
    PARTITION p20240102 VALUES [('2024-01-02'), ('2024-01-03')),
    ...
)

-- 合理的分区：按月或按天
PARTITION BY RANGE(order_date) (
    PARTITION p202401 VALUES [('2024-01-01'), ('2024-02-01')),
    PARTITION p202402 VALUES [('2024-02-01'), ('2024-03-01'))
)
```

### 3. 分区和分桶结合

```sql
-- 分区 + 分桶
CREATE TABLE orders (
    order_id BIGINT,
    user_id BIGINT,
    product_id BIGINT,
    amount DECIMAL(10,2),
    order_date DATE
)
PARTITION BY RANGE(order_date) (
    PARTITION p202401 VALUES [('2024-01-01'), ('2024-02-01')),
    PARTITION p202402 VALUES [('2024-02-01'), ('2024-03-01'))
)
DISTRIBUTED BY HASH(user_id) BUCKETS 10
PROPERTIES (
    "replication_num" = "1"
);
```

## 分区维护

### 定期清理旧分区

```sql
-- 删除 30 天前的分区
ALTER TABLE orders DROP PARTITION IF EXISTS p202312;
ALTER TABLE orders DROP PARTITION IF EXISTS p202311;
```

### 定期创建新分区

```sql
-- 添加下个月的分区
ALTER TABLE orders ADD PARTITION p202405 VALUES [('2024-05-01'), ('2024-06-01'));
```

### 使用动态分区自动管理

```sql
-- 启用动态分区，自动创建和删除分区
ALTER TABLE orders SET (
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "MONTH",
    "dynamic_partition.start" = "-3",
    "dynamic_partition.end" = "1"
);
```

## 下一步

- [索引管理](./07-index.md) - 学习如何创建和使用索引
