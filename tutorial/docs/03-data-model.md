# 数据模型深度解析

## 3.1 Doris 数据模型概述

Doris 提供了四种数据模型，每种模型针对不同的业务场景：

| 模型 | 适用场景 | 特点 |
|------|----------|------|
| DUPLICATE | 日志、事件流、原始数据 | 保留所有原始数据，不做聚合 |
| AGGREGATE | 报表、统计、预聚合 | 相同Key自动聚合，节省存储 |
| UNIQUE | 维度表、用户表、需要更新的表 | 相同Key保留最新版本 |
| PRIMARY KEY | 实时更新、频繁删除、点查询 | 支持实时更新删除，查询性能更好 |

## 3.2 DUPLICATE 模型（明细模型）

### 什么是 DUPLICATE 模型

DUPLICATE 模型是最简单的数据模型，保留所有原始数据，不做任何聚合或去重。

### 适用场景

- 日志数据存储
- 事件流数据
- 需要保留所有明细数据的场景
- 数据仓库的 ODS 层

### 建表示例

```sql
CREATE TABLE log_events (
    log_id BIGINT NOT NULL,
    user_id BIGINT,
    action VARCHAR(50),
    page_url VARCHAR(500),
    action_time DATETIME,
    device_type VARCHAR(20)
) ENGINE=OLAP
DUPLICATE KEY(log_id)
DISTRIBUTED BY HASH(log_id) BUCKETS 10
PROPERTIES (
    "replication_num" = "3"
);
```

### 特点

- **保留所有数据**：相同 Key 的数据会全部保留
- **查询灵活**：可以查询任意维度的明细数据
- **存储开销大**：不做聚合，存储空间占用较大
- **适合追加写入**：数据只追加，不修改

## 3.3 AGGREGATE 模型（聚合模型）

### 什么是 AGGREGATE 模型

AGGREGATE 模型会对相同 Key 的数据按照指定的聚合函数进行聚合，只保留聚合结果。

### 适用场景

- 报表统计
- 多维分析
- 预聚合场景
- 数据仓库的 DWS 层

### 聚合函数

| 函数 | 说明 |
|------|------|
| SUM | 求和 |
| MAX | 最大值 |
| MIN | 最小值 |
| REPLACE | 替换为最新值 |
| REPLACE_IF_NOT_NULL | 非空替换 |
| HLL_UNION | HLL 聚合 |
| BITMAP_UNION | Bitmap 聚合 |

### 建表示例

```sql
CREATE TABLE user_stats (
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
PARTITION BY RANGE(date_key) ()
DISTRIBUTED BY HASH(user_id) BUCKETS 10
PROPERTIES (
    "replication_num" = "3",
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-30",
    "dynamic_partition.end" = "3"
);
```

### 特点

- **自动聚合**：导入时自动聚合相同 Key 的数据
- **节省存储**：只存储聚合结果，大幅减少存储空间
- **查询快速**：预聚合数据，查询性能好
- **无法查询明细**：聚合后无法获取原始明细数据

## 3.4 UNIQUE 模型（唯一主键模型）

### 什么是 UNIQUE 模型

UNIQUE 模型保证相同 Key 的数据唯一，后导入的数据会覆盖之前的数据。

### 适用场景

- 维度表
- 用户表
- 需要保证唯一性的表
- 需要频繁更新的表

### 建表示例

```sql
CREATE TABLE dim_user (
    user_id BIGINT NOT NULL,
    username VARCHAR(50),
    email VARCHAR(100),
    phone VARCHAR(20),
    vip_level TINYINT,
    register_time DATETIME,
    update_time DATETIME
) ENGINE=OLAP
UNIQUE KEY(user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 10
PROPERTIES (
    "replication_num" = "3"
);
```

### 特点

- **唯一性保证**：相同 Key 只保留一条记录
- **支持更新**：新数据会覆盖旧数据
- **适合维度表**：维度表通常需要保证主键唯一
- **更新性能一般**：适合低频更新场景

## 3.5 PRIMARY KEY 模型（主键模型）

### 什么是 PRIMARY KEY 模型

PRIMARY KEY 模型是 UNIQUE 模型的增强版，支持实时更新和删除，查询性能更好。

### 适用场景

- 实时数据更新
- 频繁删除操作
- 点查询场景
- MySQL 实时同步

### 建表示例

```sql
CREATE TABLE orders (
    order_id BIGINT NOT NULL,
    order_no VARCHAR(50),
    user_id BIGINT,
    total_amount DECIMAL(18, 2),
    order_status TINYINT,
    create_time DATETIME,
    update_time DATETIME
) ENGINE=OLAP
PRIMARY KEY(order_id)
DISTRIBUTED BY HASH(order_id) BUCKETS 10
PROPERTIES (
    "replication_num" = "3",
    "enable_unique_key_merge_on_write" = "true"
);
```

### 特点

- **实时更新**：支持 UPDATE 操作
- **实时删除**：支持 DELETE 操作
- **查询性能好**：Merge-on-Write，查询时无需合并
- **点查询快**：主键查询性能优异

### PRIMARY KEY vs UNIQUE

| 特性 | PRIMARY KEY | UNIQUE |
|------|-------------|--------|
| 更新方式 | Merge-on-Write | Merge-on-Read |
| 查询性能 | 更好 | 一般 |
| 写入性能 | 略低 | 更好 |
| 存储空间 | 稍大 | 更小 |
| 适用场景 | 实时更新、点查询 | 低频更新 |

## 3.6 模型选择指南

### 决策树

```
是否需要保留所有原始数据？
├── 是 → DUPLICATE 模型
└── 否 → 是否需要实时更新删除？
    ├── 是 → PRIMARY KEY 模型
    └── 否 → 是否需要预聚合？
        ├── 是 → AGGREGATE 模型
        └── 否 → UNIQUE 模型
```

### 场景对照表

| 业务场景 | 推荐模型 | 理由 |
|----------|----------|------|
| 日志存储 | DUPLICATE | 需要保留所有日志 |
| 用户维度表 | UNIQUE | 需要保证用户唯一 |
| 订单表（实时） | PRIMARY KEY | 需要实时更新状态 |
| 统计报表 | AGGREGATE | 预聚合提升性能 |
| 事件流分析 | DUPLICATE | 需要分析所有事件 |
| 商品维度表 | UNIQUE | 商品信息需要更新 |
| 实时大屏 | PRIMARY KEY | 需要实时更新 |
| 历史数据归档 | AGGREGATE | 节省存储空间 |

## 3.7 实践案例

### 案例1：电商订单系统

```sql
-- 订单事实表（PRIMARY KEY，支持实时更新）
CREATE TABLE fact_orders (
    order_id BIGINT NOT NULL,
    user_id BIGINT,
    total_amount DECIMAL(18, 2),
    order_status TINYINT,
    create_time DATETIME
) ENGINE=OLAP
PRIMARY KEY(order_id)
DISTRIBUTED BY HASH(order_id) BUCKETS 20;

-- 订单明细表（DUPLICATE，保留所有明细）
CREATE TABLE fact_order_items (
    item_id BIGINT NOT NULL,
    order_id BIGINT,
    product_id BIGINT,
    quantity INT,
    price DECIMAL(10, 2)
) ENGINE=OLAP
DUPLICATE KEY(item_id)
DISTRIBUTED BY HASH(order_id) BUCKETS 30;

-- 用户维度表（UNIQUE，保证用户唯一）
CREATE TABLE dim_user (
    user_id BIGINT NOT NULL,
    username VARCHAR(50),
    vip_level TINYINT
) ENGINE=OLAP
UNIQUE KEY(user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 10;

-- 每日销售统计（AGGREGATE，预聚合）
CREATE TABLE dws_daily_sales (
    date_key DATE NOT NULL,
    product_id BIGINT NOT NULL,
    sales_amount DECIMAL(18, 2) SUM,
    sales_count BIGINT SUM
) ENGINE=OLAP
AGGREGATE KEY(date_key, product_id)
PARTITION BY RANGE(date_key) ()
DISTRIBUTED BY HASH(product_id) BUCKETS 10;
```

## 下一步

- [数据类型全解](./04-data-types.md) - 了解 Doris 支持的所有数据类型
- [分区与分桶策略](./06-partition-bucket.md) - 学习如何设计分区和分桶
