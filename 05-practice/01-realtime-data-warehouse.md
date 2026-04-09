# 实时数仓建设

## 项目背景

构建一个完整的实时数仓，实现 T+0 数据分析，支持电商业务的实时决策。

```
┌─────────────────────────────────────────────────────────────┐
│                    实时数仓架构                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  数据源          数据集成         数仓分层        应用       │
│  ┌─────┐        ┌─────┐        ┌─────┐        ┌─────┐     │
│  │MySQL│───────→│Canal│───────→│ ODS │───────→│报表 │     │
│  └─────┘        └─────┘        │ DWD │        └─────┘     │
│  ┌─────┐        ┌─────┐        │ DWS │        ┌─────┐     │
│  │业务 │───────→│Kafka│───────→│ ADS │───────→│大屏 │     │
│  │系统 │        └─────┘        └─────┘        └─────┘     │
│  └─────┘        ┌─────┐                         ┌─────┐   │
│  ┌─────┐        │Flink│────────────────────────→│API  │   │
│  │埋点 │───────→│ CDC │                         └─────┘   │
│  └─────┘        └─────┘                                    │
│                                                              │
│  ODS: 原始数据层    DWD: 明细数据层                         │
│  DWS: 汇总数据层    ADS: 应用数据层                         │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 一、数仓分层设计

### 分层架构

```
┌─────────────────────────────────────────────────────────────┐
│                    数仓分层设计                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ADS (Application Data Store) - 应用数据层                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  面向具体应用的数据集市                              │   │
│  │  - 实时销售大屏                                     │   │
│  │  - 用户分析报表                                     │   │
│  │  - 商品分析报表                                     │   │
│  └─────────────────────────────────────────────────────┘   │
│                           ↑                                  │
│  DWS (Data Warehouse Summary) - 汇总数据层                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  按主题域汇总的宽表                                  │   │
│  │  - 用户主题宽表                                     │   │
│  │  - 商品主题宽表                                     │   │
│  │  - 交易主题宽表                                     │   │
│  └─────────────────────────────────────────────────────┘   │
│                           ↑                                  │
│  DWD (Data Warehouse Detail) - 明细数据层                   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  清洗后的业务明细数据                                │   │
│  │  - 订单明细表                                       │   │
│  │  - 用户明细表                                       │   │
│  │  - 商品明细表                                       │   │
│  └─────────────────────────────────────────────────────┘   │
│                           ↑                                  │
│  ODS (Operational Data Store) - 原始数据层                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  原始业务数据，保持原样                              │   │
│  │  - 订单业务表                                       │   │
│  │  - 用户业务表                                       │   │
│  │  - 商品业务表                                       │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 二、ODS 层设计

### 订单业务表

```sql
-- ODS 层：订单业务表（保持原样）
CREATE TABLE ods_order (
    order_id BIGINT COMMENT '订单ID',
    user_id BIGINT COMMENT '用户ID',
    product_id BIGINT COMMENT '商品ID',
    category_id BIGINT COMMENT '分类ID',
    quantity INT COMMENT '数量',
    amount DECIMAL(12,2) COMMENT '金额',
    status VARCHAR(20) COMMENT '状态',
    create_time DATETIME COMMENT '创建时间',
    update_time DATETIME COMMENT '更新时间',
    etl_time DATETIME COMMENT 'ETL时间'
)
DUPLICATE KEY(order_id)
COMMENT 'ODS-订单业务表'
PARTITION BY RANGE(create_time) ()
DISTRIBUTED BY HASH(order_id) BUCKETS 32
PROPERTIES (
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-30",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "replication_num" = "3"
);
```

### 用户业务表

```sql
-- ODS 层：用户业务表
CREATE TABLE ods_user (
    user_id BIGINT COMMENT '用户ID',
    user_name VARCHAR(100) COMMENT '用户名',
    gender VARCHAR(10) COMMENT '性别',
    age INT COMMENT '年龄',
    city VARCHAR(50) COMMENT '城市',
    level INT COMMENT '等级',
    register_time DATETIME COMMENT '注册时间',
    update_time DATETIME COMMENT '更新时间',
    etl_time DATETIME COMMENT 'ETL时间'
)
UNIQUE KEY(user_id)
COMMENT 'ODS-用户业务表'
DISTRIBUTED BY HASH(user_id) BUCKETS 10
PROPERTIES (
    "replication_num" = "3",
    "enable_unique_key_merge_on_write" = "true"
);
```

---

## 三、DWD 层设计

### 订单明细表

```sql
-- DWD 层：订单明细表（清洗后的明细）
CREATE TABLE dwd_order_detail (
    order_id BIGINT COMMENT '订单ID',
    user_id BIGINT COMMENT '用户ID',
    user_name VARCHAR(100) COMMENT '用户名',
    product_id BIGINT COMMENT '商品ID',
    product_name VARCHAR(200) COMMENT '商品名称',
    category_id BIGINT COMMENT '分类ID',
    category_name VARCHAR(100) COMMENT '分类名称',
    quantity INT COMMENT '数量',
    original_amount DECIMAL(12,2) COMMENT '原价金额',
    discount_amount DECIMAL(12,2) COMMENT '优惠金额',
    final_amount DECIMAL(12,2) COMMENT '实付金额',
    status VARCHAR(20) COMMENT '状态',
    province VARCHAR(50) COMMENT '省份',
    city VARCHAR(50) COMMENT '城市',
    order_date DATE COMMENT '订单日期',
    order_time DATETIME COMMENT '订单时间',
    etl_time DATETIME COMMENT 'ETL时间'
)
DUPLICATE KEY(order_id, user_id, order_date)
COMMENT 'DWD-订单明细表'
PARTITION BY RANGE(order_date) ()
DISTRIBUTED BY HASH(user_id) BUCKETS 32
PROPERTIES (
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-365",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "replication_num" = "3",
    "bloom_filter_columns" = "product_id,category_id"
);
```

---

## 四、DWS 层设计

### 用户主题宽表

```sql
-- DWS 层：用户主题宽表
CREATE TABLE dws_user_summary (
    user_id BIGINT COMMENT '用户ID',
    user_name VARCHAR(100) COMMENT '用户名',
    gender VARCHAR(10) COMMENT '性别',
    age INT COMMENT '年龄',
    city VARCHAR(50) COMMENT '城市',
    level INT COMMENT '等级',
    register_date DATE COMMENT '注册日期',
    stat_date DATE COMMENT '统计日期',
    order_count BIGINT SUM COMMENT '订单数',
    order_amount DECIMAL(12,2) SUM COMMENT '订单金额',
    product_count BIGINT SUM COMMENT '商品数',
    first_order_date DATE MIN COMMENT '首单日期',
    last_order_date DATE MAX COMMENT '最近下单日期'
)
AGGREGATE KEY(user_id, user_name, gender, age, city, level, register_date, stat_date)
COMMENT 'DWS-用户主题宽表'
PARTITION BY RANGE(stat_date) ()
DISTRIBUTED BY HASH(user_id) BUCKETS 32
PROPERTIES (
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-365",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "replication_num" = "3"
);
```

### 商品主题宽表

```sql
-- DWS 层：商品主题宽表
CREATE TABLE dws_product_summary (
    product_id BIGINT COMMENT '商品ID',
    product_name VARCHAR(200) COMMENT '商品名称',
    category_id BIGINT COMMENT '分类ID',
    category_name VARCHAR(100) COMMENT '分类名称',
    stat_date DATE COMMENT '统计日期',
    order_count BIGINT SUM COMMENT '订单数',
    sale_quantity BIGINT SUM COMMENT '销售数量',
    sale_amount DECIMAL(12,2) SUM COMMENT '销售金额',
    buyer_count BIGINT SUM COMMENT '购买人数',
    avg_price DECIMAL(10,2) MAX COMMENT '平均单价'
)
AGGREGATE KEY(product_id, product_name, category_id, category_name, stat_date)
COMMENT 'DWS-商品主题宽表'
PARTITION BY RANGE(stat_date) ()
DISTRIBUTED BY HASH(product_id) BUCKETS 32
PROPERTIES (
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-365",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "replication_num" = "3"
);
```

---

## 五、ADS 层设计

### 实时销售大屏

```sql
-- ADS 层：实时销售统计
CREATE TABLE ads_realtime_sales (
    stat_time DATETIME COMMENT '统计时间',
    stat_date DATE COMMENT '统计日期',
    stat_hour INT COMMENT '统计小时',
    order_count BIGINT SUM COMMENT '订单数',
    order_amount DECIMAL(14,2) SUM COMMENT '订单金额',
    buyer_count BIGINT SUM COMMENT '购买人数',
    product_count BIGINT SUM COMMENT '商品数'
)
AGGREGATE KEY(stat_time, stat_date, stat_hour)
COMMENT 'ADS-实时销售统计'
DISTRIBUTED BY HASH(stat_date) BUCKETS 10
PROPERTIES (
    "replication_num" = "3"
);

-- 创建物化视图加速查询
CREATE MATERIALIZED VIEW mv_realtime_sales_1min
AS SELECT
    DATE_TRUNC(stat_time, 'minute') as stat_minute,
    SUM(order_count) as order_count,
    SUM(order_amount) as order_amount,
    SUM(buyer_count) as buyer_count
FROM ads_realtime_sales
GROUP BY DATE_TRUNC(stat_time, 'minute');
```

### 商品销售排行

```sql
-- ADS 层：商品销售排行
CREATE TABLE ads_product_rank (
    stat_date DATE COMMENT '统计日期',
    rank_type VARCHAR(20) COMMENT '排行类型',
    product_id BIGINT COMMENT '商品ID',
    product_name VARCHAR(200) COMMENT '商品名称',
    sale_amount DECIMAL(12,2) SUM COMMENT '销售金额',
    sale_quantity BIGINT SUM COMMENT '销售数量',
    rank INT REPLACE COMMENT '排名'
)
AGGREGATE KEY(stat_date, rank_type, product_id, product_name)
COMMENT 'ADS-商品销售排行'
DISTRIBUTED BY HASH(product_id) BUCKETS 10
PROPERTIES (
    "replication_num" = "3"
);
```

---

## 六、实时数据同步

### Flink CDC 同步

```sql
-- Flink SQL: 从 MySQL 同步到 Doris ODS 层

-- 创建 MySQL CDC 源表
CREATE TABLE mysql_order (
    order_id BIGINT,
    user_id BIGINT,
    product_id BIGINT,
    quantity INT,
    amount DECIMAL(12,2),
    status STRING,
    create_time TIMESTAMP,
    update_time TIMESTAMP,
    PRIMARY KEY (order_id) NOT ENFORCED
) WITH (
    'connector' = 'mysql-cdc',
    'hostname' = 'mysql-host',
    'port' = '3306',
    'username' = 'root',
    'password' = 'password',
    'database-name' = 'ecommerce',
    'table-name' = 'orders'
);

-- 创建 Doris 目标表
CREATE TABLE doris_ods_order (
    order_id BIGINT,
    user_id BIGINT,
    product_id BIGINT,
    quantity INT,
    amount DECIMAL(12,2),
    status STRING,
    create_time TIMESTAMP,
    update_time TIMESTAMP,
    etl_time TIMESTAMP
) WITH (
    'connector' = 'doris',
    'fenodes' = 'doris-fe:8030',
    'table.identifier' = 'realtime_warehouse.ods_order',
    'username' = 'root',
    'password' = '',
    'sink.properties.format' = 'json',
    'sink.properties.strip_outer_array' = 'true'
);

-- 同步数据
INSERT INTO doris_ods_order
SELECT 
    order_id,
    user_id,
    product_id,
    quantity,
    amount,
    status,
    create_time,
    update_time,
    CURRENT_TIMESTAMP as etl_time
FROM mysql_order;
```

### Flink ETL 处理

```sql
-- Flink SQL: DWD 层 ETL

-- 从 ODS 读取
CREATE TABLE ods_order_source (
    ...
) WITH (
    'connector' = 'doris',
    'fenodes' = 'doris-fe:8030',
    'table.identifier' = 'realtime_warehouse.ods_order'
);

-- 关联维度表
CREATE TABLE dim_user (
    ...
) WITH (
    'connector' = 'doris',
    'fenodes' = 'doris-fe:8030',
    'table.identifier' = 'realtime_warehouse.dim_user',
    'lookup.jdbc.async' = 'true'
);

CREATE TABLE dim_product (
    ...
) WITH (
    'connector' = 'doris',
    'fenodes' = 'doris-fe:8030',
    'table.identifier' = 'realtime_warehouse.dim_product',
    'lookup.jdbc.async' = 'true'
);

-- ETL 处理写入 DWD
INSERT INTO doris_dwd_order_detail
SELECT 
    o.order_id,
    o.user_id,
    u.user_name,
    o.product_id,
    p.product_name,
    p.category_id,
    p.category_name,
    o.quantity,
    o.amount as original_amount,
    0 as discount_amount,
    o.amount as final_amount,
    o.status,
    u.province,
    u.city,
    DATE(o.create_time) as order_date,
    o.create_time as order_time,
    CURRENT_TIMESTAMP as etl_time
FROM ods_order_source o
LEFT JOIN dim_user FOR SYSTEM_TIME AS OF o.proctime AS u
    ON o.user_id = u.user_id
LEFT JOIN dim_product FOR SYSTEM_TIME AS OF o.proctime AS p
    ON o.product_id = p.product_id;
```

---

## 七、实时指标计算

### 实时销售统计

```sql
-- Flink SQL: 实时销售统计

-- 从 DWD 读取
CREATE TABLE dwd_order_detail_source (
    ...
) WITH (
    'connector' = 'doris',
    'fenodes' = 'doris-fe:8030',
    'table.identifier' = 'realtime_warehouse.dwd_order_detail'
);

-- 实时聚合
INSERT INTO doris_ads_realtime_sales
SELECT
    TUMBLE_START(order_time, INTERVAL '1' MINUTE) as stat_time,
    DATE_FORMAT(TUMBLE_START(order_time, INTERVAL '1' MINUTE), 'yyyy-MM-dd') as stat_date,
    HOUR(TUMBLE_START(order_time, INTERVAL '1' MINUTE)) as stat_hour,
    COUNT(DISTINCT order_id) as order_count,
    SUM(final_amount) as order_amount,
    COUNT(DISTINCT user_id) as buyer_count,
    SUM(quantity) as product_count
FROM dwd_order_detail_source
GROUP BY
    TUMBLE(order_time, INTERVAL '1' MINUTE),
    DATE_FORMAT(order_time, 'yyyy-MM-dd'),
    HOUR(order_time);
```

---

## 八、BI 报表

### 实时销售大屏 SQL

```sql
-- 今日实时销售
SELECT
    SUM(order_count) as total_orders,
    SUM(order_amount) as total_amount,
    SUM(buyer_count) as total_buyers
FROM ads_realtime_sales
WHERE stat_date = CURRENT_DATE;

-- 每小时销售趋势
SELECT
    stat_hour,
    SUM(order_count) as order_count,
    SUM(order_amount) as order_amount
FROM ads_realtime_sales
WHERE stat_date = CURRENT_DATE
GROUP BY stat_hour
ORDER BY stat_hour;

-- 商品销售排行 TOP 10
SELECT
    product_name,
    sale_amount,
    sale_quantity,
    rank
FROM ads_product_rank
WHERE stat_date = CURRENT_DATE
  AND rank_type = 'amount'
ORDER BY rank
LIMIT 10;
```

---

## 九、项目总结

### 技术架构

| 组件 | 作用 |
|------|------|
| MySQL | 业务数据库 |
| Canal | CDC 数据捕获 |
| Kafka | 消息队列 |
| Flink | 实时计算 |
| Doris | 实时数仓 |
| Grafana | 数据可视化 |

### 性能指标

| 指标 | 目标 | 实际 |
|------|------|------|
| 数据延迟 | < 5s | 3s |
| 查询响应 | < 1s | 0.5s |
| 并发 QPS | 100 | 150 |

### 最佳实践

1. **分层设计**：ODS → DWD → DWS → ADS，职责清晰
2. **实时同步**：使用 Flink CDC 实现实时同步
3. **预聚合**：使用物化视图加速查询
4. **监控告警**：建立完整的监控体系

---

## 下一步

- [日志分析平台](./02-log-analysis.md)
- [用户行为分析](./03-user-behavior.md)
