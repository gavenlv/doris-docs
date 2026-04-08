# 数据模型

## 概述

Doris 提供三种数据模型，适用于不同的业务场景。选择正确的数据模型是性能优化的第一步。

```
┌─────────────────────────────────────────────────────────────┐
│                    三种数据模型                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Duplicate Key (明细模型)                            │   │
│  │  ━━━━━━━━━━━━━━━━━━━━━━━━━                          │   │
│  │  特点：保留所有原始数据，不做任何聚合                 │   │
│  │  场景：日志、事件流、原始数据存储                     │   │
│  │  示例：用户行为日志、系统日志、点击流                 │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Aggregate Key (聚合模型)                            │   │
│  │  ━━━━━━━━━━━━━━━━━━━━━━━                            │   │
│  │  特点：相同 Key 自动聚合，预计算                      │   │
│  │  场景：报表、统计、多维分析                          │   │
│  │  示例：销售日报、用户统计、流量汇总                   │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Unique Key (唯一主键模型)                           │   │
│  │  ━━━━━━━━━━━━━━━━━━━━━                              │   │
│  │  特点：主键唯一，支持更新删除                        │   │
│  │  场景：维度表、状态表、需要更新的表                   │   │
│  │  示例：用户表、订单表、商品表                         │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 一、Duplicate Key (明细模型)

### 特点

- **保留所有数据**：不做任何聚合，保留每一条原始记录
- **无预聚合**：查询时实时计算
- **适合日志类数据**：事件流、日志、埋点数据

### 创建表

```sql
-- 用户行为日志表
CREATE TABLE user_behavior (
    user_id BIGINT COMMENT '用户ID',
    event_time DATETIME COMMENT '事件时间',
    event_type VARCHAR(50) COMMENT '事件类型',
    page_id VARCHAR(100) COMMENT '页面ID',
    device_id VARCHAR(100) COMMENT '设备ID',
    ip_address VARCHAR(50) COMMENT 'IP地址',
    extra_info STRING COMMENT '扩展信息'
)
DUPLICATE KEY(user_id, event_time)
COMMENT '用户行为日志表'
PARTITION BY RANGE(event_time) (
    PARTITION p202401 VALUES LESS THAN ('2024-02-01'),
    PARTITION p202402 VALUES LESS THAN ('2024-03-01'),
    PARTITION p202403 VALUES LESS THAN ('2024-04-01')
)
DISTRIBUTED BY HASH(user_id) BUCKETS 32
PROPERTIES (
    "replication_num" = "3"
);
```

### 数据写入

```sql
-- 每条记录都会保留
INSERT INTO user_behavior VALUES
    (1, '2024-01-15 10:30:00', 'view', 'home', 'device_001', '192.168.1.1', '{}'),
    (1, '2024-01-15 10:31:00', 'click', 'product_1', 'device_001', '192.168.1.1', '{}'),
    (1, '2024-01-15 10:32:00', 'view', 'home', 'device_001', '192.168.1.1', '{}'),
    (1, '2024-01-15 10:30:00', 'view', 'home', 'device_001', '192.168.1.1', '{}'); -- 重复也会保留

-- 查询返回所有记录
SELECT * FROM user_behavior WHERE user_id = 1;
-- 返回 4 条记录
```

### 适用场景

| 场景 | 说明 |
|------|------|
| 日志存储 | 系统日志、应用日志、访问日志 |
| 事件流 | 用户行为、点击流、埋点数据 |
| 原始数据 | 需要保留完整原始记录 |
| 数据湖 | 作为数据湖的底层存储 |

### 优缺点

| 优点 | 缺点 |
|------|------|
| 数据完整，不丢失 | 存储空间较大 |
| 支持任意维度分析 | 聚合查询性能较低 |
| 灵活性高 | 需要查询时聚合 |

---

## 二、Aggregate Key (聚合模型)

### 特点

- **自动聚合**：相同 Key 的数据自动聚合
- **预计算**：导入时完成聚合，查询更快
- **支持多种聚合函数**：SUM、MAX、MIN、REPLACE、HLL_UNION 等

### 聚合函数

```
┌─────────────────────────────────────────────────────────────┐
│                    聚合函数类型                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  SUM        求和，数值列                                     │
│  ─────────────────────────────────────────────────────────  │
│  用法：amount DECIMAL(10,2) SUM                             │
│  效果：相同 Key 的 amount 值相加                             │
│                                                              │
│  MAX        最大值                                           │
│  ─────────────────────────────────────────────────────────  │
│  用法：update_time DATETIME MAX                              │
│  效果：保留相同 Key 的最大时间                                │
│                                                              │
│  MIN        最小值                                           │
│  ─────────────────────────────────────────────────────────  │
│  用法：create_time DATETIME MIN                              │
│  效果：保留相同 Key 的最小时间                                │
│                                                              │
│  REPLACE    替换，保留最新值                                  │
│  ─────────────────────────────────────────────────────────  │
│  用法：status VARCHAR(50) REPLACE                           │
│  效果：相同 Key 的 status 替换为最新值                        │
│                                                              │
│  REPLACE_IF_NOT_NULL    非 NULL 替换                        │
│  ─────────────────────────────────────────────────────────  │
│  用法：email VARCHAR(100) REPLACE_IF_NOT_NULL               │
│  效果：新值非 NULL 时才替换                                   │
│                                                              │
│  HLL_UNION  HyperLogLog 聚合，用于近似去重                   │
│  ─────────────────────────────────────────────────────────  │
│  用法：uv HLL HLL_UNION                                      │
│  效果：合并 HLL 估算值                                        │
│                                                              │
│  BITMAP_UNION    Bitmap 聚合，用于精确去重                   │
│  ─────────────────────────────────────────────────────────  │
│  用法：user_ids BITMAP BITMAP_UNION                         │
│  效果：合并 Bitmap                                           │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 创建表

```sql
-- 每日销售汇总表
CREATE TABLE daily_sales (
    sale_date DATE COMMENT '销售日期',
    product_id BIGINT COMMENT '商品ID',
    category VARCHAR(50) COMMENT '商品类别',
    sale_count INT SUM COMMENT '销售数量',
    sale_amount DECIMAL(12,2) SUM COMMENT '销售金额',
    max_price DECIMAL(10,2) MAX COMMENT '最高单价',
    min_price DECIMAL(10,2) MIN COMMENT '最低单价',
    last_update DATETIME REPLACE COMMENT '最后更新时间'
)
AGGREGATE KEY(sale_date, product_id, category)
COMMENT '每日销售汇总表'
PARTITION BY RANGE(sale_date) (
    PARTITION p202401 VALUES LESS THAN ('2024-02-01'),
    PARTITION p202402 VALUES LESS THAN ('2024-03-01'),
    PARTITION p202403 VALUES LESS THAN ('2024-04-01')
)
DISTRIBUTED BY HASH(product_id) BUCKETS 32
PROPERTIES (
    "replication_num" = "3"
);
```

### 数据写入

```sql
-- 第一次导入
INSERT INTO daily_sales VALUES
    ('2024-01-15', 1, '手机', 10, 69990.00, 6999.00, 6999.00, '2024-01-15 10:00:00');

-- 第二次导入（相同 Key）
INSERT INTO daily_sales VALUES
    ('2024-01-15', 1, '手机', 5, 34995.00, 7999.00, 5999.00, '2024-01-15 14:00:00');

-- 查询结果（自动聚合）
SELECT * FROM daily_sales WHERE sale_date = '2024-01-15' AND product_id = 1;

-- 结果：
-- sale_date: 2024-01-15
-- product_id: 1
-- category: 手机
-- sale_count: 15 (10 + 5)
-- sale_amount: 104985.00 (69990 + 34995)
-- max_price: 7999.00 (MAX)
-- min_price: 5999.00 (MIN)
-- last_update: 2024-01-15 14:00:00 (REPLACE)
```

### 用户统计表示例

```sql
-- 用户统计表（使用 HLL 和 Bitmap）
CREATE TABLE user_stats (
    stat_date DATE COMMENT '统计日期',
    app_id VARCHAR(50) COMMENT '应用ID',
    pv BIGINT SUM COMMENT '页面浏览量',
    uv HLL HLL_UNION COMMENT '独立用户数(近似)',
    user_ids BITMAP BITMAP_UNION COMMENT '用户ID集合(精确)'
)
AGGREGATE KEY(stat_date, app_id)
COMMENT '用户统计表'
DISTRIBUTED BY HASH(app_id) BUCKETS 10;

-- 导入数据
INSERT INTO user_stats VALUES
    ('2024-01-15', 'app_001', 1000, hll_hash('user_1'), to_bitmap(1)),
    ('2024-01-15', 'app_001', 500, hll_hash('user_2'), to_bitmap(2)),
    ('2024-01-15', 'app_001', 300, hll_hash('user_1'), to_bitmap(1));

-- 查询
SELECT 
    stat_date,
    app_id,
    SUM(pv) as pv,
    HLL_UNION_AGG(uv) as uv_approx,
    BITMAP_UNION_COUNT(user_ids) as uv_exact
FROM user_stats
GROUP BY stat_date, app_id;
```

### 适用场景

| 场景 | 说明 |
|------|------|
| 报表统计 | 预聚合报表，加速查询 |
| 多维分析 | 固定维度的聚合分析 |
| 实时指标 | 实时更新的统计指标 |
| 去重统计 | UV、独立用户数统计 |

### 优缺点

| 优点 | 缺点 |
|------|------|
| 查询性能高 | 只支持固定维度聚合 |
| 存储空间小 | 不保留原始数据 |
| 导入时预聚合 | 聚合函数有限 |

---

## 三、Unique Key (唯一主键模型)

### 特点

- **主键唯一**：相同主键只保留一条记录
- **支持更新**：可以 UPDATE 和 DELETE
- **支持删除**：可以删除指定记录
- **Merge-on-Write**：写入时合并，查询性能好

### 创建表

```sql
-- 用户表
CREATE TABLE users (
    user_id BIGINT COMMENT '用户ID',
    user_name VARCHAR(100) COMMENT '用户名',
    age INT COMMENT '年龄',
    city VARCHAR(50) COMMENT '城市',
    email VARCHAR(100) COMMENT '邮箱',
    phone VARCHAR(20) COMMENT '手机号',
    vip_level INT COMMENT 'VIP等级',
    create_time DATETIME COMMENT '创建时间',
    update_time DATETIME COMMENT '更新时间'
)
UNIQUE KEY(user_id)
COMMENT '用户表'
DISTRIBUTED BY HASH(user_id) BUCKETS 32
PROPERTIES (
    "replication_num" = "3",
    "enable_unique_key_merge_on_write" = "true"
);
```

### 数据写入

```sql
-- 插入数据
INSERT INTO users VALUES
    (1, '张三', 25, '北京', 'zhangsan@email.com', '13800138000', 1, NOW(), NOW());

-- 更新数据（相同主键会覆盖）
INSERT INTO users VALUES
    (1, '张三', 26, '上海', 'zhangsan@email.com', '13800138000', 2, NOW(), NOW());

-- 使用 UPDATE 更新
UPDATE users SET age = 27, city = '广州' WHERE user_id = 1;

-- 使用 DELETE 删除
DELETE FROM users WHERE user_id = 1;
```

### 订单表示例

```sql
-- 订单表（状态会变化）
CREATE TABLE orders (
    order_id VARCHAR(50) COMMENT '订单ID',
    user_id BIGINT COMMENT '用户ID',
    product_id BIGINT COMMENT '商品ID',
    amount DECIMAL(10,2) COMMENT '订单金额',
    status VARCHAR(20) COMMENT '订单状态',
    create_time DATETIME COMMENT '创建时间',
    update_time DATETIME COMMENT '更新时间'
)
UNIQUE KEY(order_id)
COMMENT '订单表'
DISTRIBUTED BY HASH(order_id) BUCKETS 32
PROPERTIES (
    "replication_num" = "3",
    "enable_unique_key_merge_on_write" = "true"
);

-- 订单状态流转
INSERT INTO orders VALUES ('ORD001', 1, 101, 6999.00, '待支付', NOW(), NOW());
UPDATE orders SET status = '已支付', update_time = NOW() WHERE order_id = 'ORD001';
UPDATE orders SET status = '已发货', update_time = NOW() WHERE order_id = 'ORD001';
UPDATE orders SET status = '已完成', update_time = NOW() WHERE order_id = 'ORD001';

-- 查询当前状态
SELECT * FROM orders WHERE order_id = 'ORD001';
-- 只返回最新状态：已完成
```

### 适用场景

| 场景 | 说明 |
|------|------|
| 维度表 | 用户表、商品表、组织表 |
| 状态表 | 订单表、任务表、流程表 |
| 需要更新 | 数据会频繁变更 |
| 需要删除 | 需要删除历史数据 |

### 优缺点

| 优点 | 缺点 |
|------|------|
| 支持更新删除 | 写入性能略低 |
| 查询性能好 | 主键长度有限制 |
| 数据一致性好 | 更新代价较高 |

---

## 四、模型选择指南

### 决策树

```
开始
  │
  ├─ 数据是否需要更新/删除？
  │   ├─ 是 → Unique Key
  │   └─ 否 ↓
  │
  ├─ 是否需要保留所有原始数据？
  │   ├─ 是 → Duplicate Key
  │   └─ 否 ↓
  │
  ├─ 是否有固定的聚合维度？
  │   ├─ 是 → Aggregate Key
  │   └─ 否 → Duplicate Key
  │
  └─ 结束
```

### 场景对比

| 场景 | 推荐模型 | 原因 |
|------|---------|------|
| 用户行为日志 | Duplicate | 需要保留完整日志 |
| 系统日志 | Duplicate | 需要保留完整日志 |
| 销售日报 | Aggregate | 固定维度聚合 |
| 用户统计 | Aggregate | 预聚合加速查询 |
| 用户表 | Unique | 需要更新用户信息 |
| 订单表 | Unique | 订单状态会变化 |
| 商品表 | Unique | 商品信息会更新 |
| 实时大屏 | Aggregate | 预聚合加速 |

### 性能对比

```
写入性能：
Duplicate Key > Aggregate Key > Unique Key

查询性能（聚合查询）：
Aggregate Key > Unique Key > Duplicate Key

查询性能（明细查询）：
Duplicate Key > Unique Key > Aggregate Key

存储空间：
Aggregate Key < Unique Key < Duplicate Key
```

---

## 五、最佳实践

### 1. 选择合适的 Key 列

```sql
-- 好的设计：Key 列选择高基数列
CREATE TABLE orders (
    order_id VARCHAR(50),    -- 高基数，适合做 Key
    user_id BIGINT,
    ...
)
UNIQUE KEY(order_id);

-- 不好的设计：Key 列选择低基数列
CREATE TABLE orders (
    status VARCHAR(20),      -- 低基数，不适合做 Key
    order_id VARCHAR(50),
    ...
)
UNIQUE KEY(status);          -- 错误！
```

### 2. 合理使用聚合函数

```sql
-- 好的设计：根据业务需求选择聚合函数
CREATE TABLE user_stats (
    user_id BIGINT,
    login_count INT SUM,         -- 累加登录次数
    last_login DATETIME REPLACE, -- 保留最后登录时间
    first_login DATETIME MIN     -- 保留首次登录时间
)
AGGREGATE KEY(user_id);

-- 不好的设计：所有列都用 REPLACE
CREATE TABLE user_stats (
    user_id BIGINT,
    login_count INT REPLACE,     -- 错误！应该是 SUM
    last_login DATETIME REPLACE,
    first_login DATETIME REPLACE -- 错误！应该是 MIN
)
AGGREGATE KEY(user_id);
```

### 3. 分区分桶设计

```sql
-- 好的设计：根据查询模式设计分区分桶
CREATE TABLE orders (
    order_id VARCHAR(50),
    user_id BIGINT,
    order_date DATE,
    ...
)
UNIQUE KEY(order_id)
PARTITION BY RANGE(order_date) (...)  -- 按日期分区
DISTRIBUTED BY HASH(user_id) BUCKETS 32;  -- 按用户分桶

-- 查询时可以利用分区裁剪
SELECT * FROM orders 
WHERE order_date = '2024-01-15' 
  AND user_id = 123;
```

### 4. 使用物化视图补充聚合

```sql
-- Duplicate Key 表 + 物化视图 = 灵活 + 高性能
CREATE TABLE user_behavior (
    user_id BIGINT,
    event_time DATETIME,
    event_type VARCHAR(50),
    ...
)
DUPLICATE KEY(user_id, event_time)
DISTRIBUTED BY HASH(user_id) BUCKETS 32;

-- 创建物化视图加速聚合查询
CREATE MATERIALIZED VIEW mv_daily_stats
AS SELECT
    DATE(event_time) as stat_date,
    event_type,
    COUNT(*) as event_count,
    COUNT(DISTINCT user_id) as uv
FROM user_behavior
GROUP BY DATE(event_time), event_type;
```

---

## 下一步

- [数据导入](./06-data-import.md) - 学习多种数据导入方式
- [数据导出](./07-data-export.md) - 学习数据导出
- [分区管理](./06-partition.md) - 深入学习分区设计
