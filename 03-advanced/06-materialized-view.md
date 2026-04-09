# 物化视图

## 概述

物化视图 (Materialized View) 是 Doris 的核心性能优化特性，类似于 ClickHouse 的 Projection，能够**自动将查询改写到预聚合的物化视图**，实现查询透明加速。

```
┌─────────────────────────────────────────────────────────────┐
│                    物化视图工作原理                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  用户查询                                                    │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  SELECT date, SUM(amount)                           │   │
│  │  FROM orders                                        │   │
│  │  GROUP BY date                                      │   │
│  └─────────────────────────────────────────────────────┘   │
│                           │                                  │
│                           ▼                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              查询优化器                              │   │
│  │  ─────────────────────────────────────────────────  │   │
│  │  1. 解析查询                                        │   │
│  │  2. 检查是否有匹配的物化视图                        │   │
│  │  3. 自动改写查询                                    │   │
│  └─────────────────────────────────────────────────────┘   │
│                           │                                  │
│              ┌────────────┴────────────┐                    │
│              ▼                         ▼                    │
│  ┌─────────────────┐        ┌─────────────────┐            │
│  │   原始表        │        │   物化视图       │            │
│  │   1亿行         │        │   1万行          │            │
│  │   扫描全表      │        │   直接读取聚合   │            │
│  │   耗时: 15秒    │        │   耗时: 0.1秒    │            │
│  └─────────────────┘        └─────────────────┘            │
│                                      ✅ 自动选择            │
│                                                              │
│  性能提升：10-1000 倍                                        │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 一、物化视图 vs ClickHouse Projection

### 对比分析

```
┌─────────────────────────────────────────────────────────────┐
│              Doris MV vs ClickHouse Projection              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ClickHouse Projection                                       │
│  ─────────────────────────────────────────────────────────  │
│  - 表内多版本存储                                            │
│  - 查询自动选择最优版本                                      │
│  - 与主表强绑定                                              │
│  - 定义在 CREATE TABLE 内                                    │
│                                                              │
│  Doris Materialized View                                     │
│  ─────────────────────────────────────────────────────────  │
│  - 独立的物理表                                              │
│  - 查询自动改写，命中物化视图                                │
│  - 数据自动同步                                              │
│  - 支持更复杂的聚合                                          │
│  - 支持同步和异步刷新                                        │
│                                                              │
│  共同点：                                                    │
│  ✅ 查询自动命中预聚合数据                                   │
│  ✅ 对用户透明，无需修改查询                                 │
│  ✅ 显著提升聚合查询性能                                     │
│  ✅ 数据自动维护                                             │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 功能对比表

| 特性 | Doris MV | ClickHouse Projection |
|------|----------|----------------------|
| 存储方式 | 独立物理表 | 表内多版本 |
| 自动查询改写 | ✅ 支持 | ✅ 支持 |
| 数据同步 | 自动同步 | 自动同步 |
| 聚合类型 | SUM/COUNT/MAX/MIN/HLL/BITMAP | 同左 |
| 刷新策略 | 同步/异步 | 同步 |
| 空间占用 | 额外存储 | 额外存储 |
| JOIN 支持 | ✅ 支持（异步MV） | ❌ 不支持 |
| 外表支持 | ✅ 支持 | ❌ 不支持 |

---

## 二、同步物化视图

### 基本语法

```sql
CREATE MATERIALIZED VIEW [MV name] 
[PROPERTIES ("key"="value")]
AS 
SELECT 
    select_expr1, 
    select_expr2, 
    ...
FROM base_table_name
[WHERE where_expr]
GROUP BY column_name1, column_name2, ...
```

### 创建第一个物化视图

```sql
-- 原始订单表
CREATE TABLE orders (
    order_id BIGINT,
    user_id BIGINT,
    product_id BIGINT,
    category VARCHAR(50),
    amount DECIMAL(10,2),
    status VARCHAR(20),
    order_date DATE,
    order_time DATETIME
)
DUPLICATE KEY(order_id)
PARTITION BY RANGE(order_date) ()
DISTRIBUTED BY HASH(order_id) BUCKETS 32
PROPERTIES (
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-30",
    "dynamic_partition.end" = "3"
);

-- 创建物化视图：按日期+类别预聚合
CREATE MATERIALIZED VIEW mv_daily_category_sales
AS SELECT
    order_date,
    category,
    COUNT(*) as order_count,
    SUM(amount) as total_amount,
    COUNT(DISTINCT user_id) as buyer_count
FROM orders
GROUP BY order_date, category;
```

### 自动查询改写示例

```sql
-- 用户查询（原始 SQL）
SELECT 
    order_date,
    category,
    SUM(amount) as total_amount
FROM orders
WHERE order_date = '2024-01-15'
GROUP BY order_date, category;

-- Doris 自动改写为：
SELECT 
    order_date,
    category,
    total_amount
FROM mv_daily_category_sales
WHERE order_date = '2024-01-15';

-- 性能提升：10-100 倍
```

### 验证是否命中物化视图

```sql
-- 方法1：查看执行计划
EXPLAIN SELECT 
    order_date,
    SUM(amount)
FROM orders
WHERE order_date = '2024-01-15'
GROUP BY order_date;

-- 输出中看到：
-- rollup: mv_daily_category_sales  ← 命中物化视图

-- 方法2：查看 Profile
SET enable_profile = true;
SELECT order_date, SUM(amount) FROM orders GROUP BY order_date;
SHOW QUERY PROFILE 'xxx';
-- 查看 Rollup 字段
```

---

## 三、多粒度物化视图

### 设计原则

```
┌─────────────────────────────────────────────────────────────┐
│                  物化视图粒度设计                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  原始表 (最细粒度)                                          │
│  ─────────────────────────────────────────────────────────  │
│  1亿行数据，支持任意查询                                    │
│                                                              │
│         ↓ 创建物化视图                                       │
│                                                              │
│  粗粒度物化视图                                              │
│  ─────────────────────────────────────────────────────────  │
│  GROUP BY date                                               │
│  数据量：365 行/年                                           │
│  适用查询：按天统计                                          │
│                                                              │
│         ↓ 创建物化视图                                       │
│                                                              │
│  中粒度物化视图                                              │
│  ─────────────────────────────────────────────────────────  │
│  GROUP BY date, category                                     │
│  数据量：365 × 10 = 3650 行/年                               │
│  适用查询：按天+类别统计                                     │
│                                                              │
│         ↓ 创建物化视图                                       │
│                                                              │
│  细粒度物化视图                                              │
│  ─────────────────────────────────────────────────────────  │
│  GROUP BY date, category, product                            │
│  数据量：365 × 10 × 1000 = 365万行/年                        │
│  适用查询：按天+类别+商品统计                                │
│                                                              │
│  查询优化器自动选择最优粒度                                  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 创建多粒度物化视图

```sql
-- 原始表
CREATE TABLE sales (
    sale_id BIGINT,
    sale_date DATE,
    product_id BIGINT,
    category_id BIGINT,
    brand_id BIGINT,
    amount DECIMAL(10,2),
    quantity INT
)
DUPLICATE KEY(sale_id)
PARTITION BY RANGE(sale_date) ()
DISTRIBUTED BY HASH(sale_id) BUCKETS 32;

-- 物化视图1：按天聚合（最粗粒度）
CREATE MATERIALIZED VIEW mv_daily_sales
AS SELECT
    sale_date,
    SUM(amount) as total_amount,
    SUM(quantity) as total_quantity,
    COUNT(*) as sale_count
FROM sales
GROUP BY sale_date;

-- 物化视图2：按天+类别聚合（中粒度）
CREATE MATERIALIZED VIEW mv_daily_category_sales
AS SELECT
    sale_date,
    category_id,
    SUM(amount) as total_amount,
    SUM(quantity) as total_quantity,
    COUNT(*) as sale_count
FROM sales
GROUP BY sale_date, category_id;

-- 物化视图3：按天+品牌聚合（中粒度）
CREATE MATERIALIZED VIEW mv_daily_brand_sales
AS SELECT
    sale_date,
    brand_id,
    SUM(amount) as total_amount,
    SUM(quantity) as total_quantity,
    COUNT(*) as sale_count
FROM sales
GROUP BY sale_date, brand_id;

-- 物化视图4：按天+类别+品牌聚合（细粒度）
CREATE MATERIALIZED VIEW mv_daily_category_brand_sales
AS SELECT
    sale_date,
    category_id,
    brand_id,
    SUM(amount) as total_amount,
    SUM(quantity) as total_quantity,
    COUNT(*) as sale_count
FROM sales
GROUP BY sale_date, category_id, brand_id;
```

### 查询自动选择最优视图

```sql
-- 查询1：按天统计 → 命中 mv_daily_sales（最粗粒度）
SELECT sale_date, SUM(amount) 
FROM sales 
GROUP BY sale_date;

-- 查询2：按天+类别统计 → 命中 mv_daily_category_sales
SELECT sale_date, category_id, SUM(amount) 
FROM sales 
GROUP BY sale_date, category_id;

-- 查询3：按天+品牌统计 → 命中 mv_daily_brand_sales
SELECT sale_date, brand_id, SUM(amount) 
FROM sales 
GROUP BY sale_date, brand_id;

-- 查询4：按天+类别+品牌统计 → 命中 mv_daily_category_brand_sales
SELECT sale_date, category_id, brand_id, SUM(amount) 
FROM sales 
GROUP BY sale_date, category_id, brand_id;

-- 查询5：按天+类别统计（带WHERE）→ 命中 mv_daily_category_sales
SELECT sale_date, category_id, SUM(amount) 
FROM sales 
WHERE sale_date = '2024-01-15'
GROUP BY sale_date, category_id;
```

---

## 四、查询改写规则

### 命中条件详解

```
┌─────────────────────────────────────────────────────────────┐
│                  物化视图命中条件                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. GROUP BY 列匹配                                         │
│     ─────────────────────────────────────────────────────── │
│     MV: GROUP BY date, category                             │
│     查询: GROUP BY date           ✅ 命中（子集）           │
│     查询: GROUP BY date, category ✅ 命中（完全匹配）       │
│     查询: GROUP BY date, product  ❌ 不命中                 │
│                                                              │
│  2. 聚合函数匹配                                            │
│     ─────────────────────────────────────────────────────── │
│     MV: SUM(amount), COUNT(*)                               │
│     查询: SUM(amount)             ✅ 命中                   │
│     查询: COUNT(*)                ✅ 命中                   │
│     查询: AVG(amount)             ❌ 不命中（MV没有）       │
│     查询: SUM(amount) + COUNT(*)  ✅ 命中                   │
│                                                              │
│  3. WHERE 条件匹配                                          │
│     ─────────────────────────────────────────────────────── │
│     MV: 无过滤条件                                          │
│     查询: WHERE date = 'xxx'      ✅ 命中                   │
│                                                              │
│     MV: WHERE status = 'paid'                               │
│     查询: WHERE status = 'paid'   ✅ 命中                   │
│     查询: WHERE status = 'pending' ❌ 不命中                │
│                                                              │
│  4. SELECT 列匹配                                           │
│     ─────────────────────────────────────────────────────── │
│     MV: date, category, SUM(amount)                         │
│     查询: SELECT date, SUM(amount) ✅ 命中                  │
│     查询: SELECT date, product    ❌ 不命中                 │
│                                                              │
│  5. 分区裁剪                                                │
│     ─────────────────────────────────────────────────────── │
│     MV 和原表分区一致，支持分区裁剪                         │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 详细示例

```sql
-- 物化视图定义
CREATE MATERIALIZED VIEW mv_order_agg
AS SELECT
    order_date,
    user_id,
    COUNT(*) as order_count,
    SUM(amount) as total_amount,
    MAX(amount) as max_amount,
    MIN(amount) as min_amount
FROM orders
GROUP BY order_date, user_id;

-- ✅ 案例1：完全匹配
SELECT order_date, user_id, SUM(amount)
FROM orders
GROUP BY order_date, user_id;
-- 命中 mv_order_agg

-- ✅ 案例2：GROUP BY 子集
SELECT order_date, SUM(amount)
FROM orders
GROUP BY order_date;
-- 命中 mv_order_agg（进一步聚合）

-- ✅ 案例3：带 WHERE 条件
SELECT order_date, user_id, SUM(amount)
FROM orders
WHERE order_date = '2024-01-15'
GROUP BY order_date, user_id;
-- 命中 mv_order_agg

-- ✅ 案例4：多个聚合函数
SELECT order_date, user_id, SUM(amount), MAX(amount), COUNT(*)
FROM orders
GROUP BY order_date, user_id;
-- 命中 mv_order_agg

-- ❌ 案例5：聚合函数不匹配
SELECT order_date, user_id, AVG(amount)
FROM orders
GROUP BY order_date, user_id;
-- 不命中（MV 没有 AVG）

-- ❌ 案例6：额外列
SELECT order_date, user_id, product_id, SUM(amount)
FROM orders
GROUP BY order_date, user_id, product_id;
-- 不命中（product_id 不在 MV 中）

-- ❌ 案例7：WHERE 条件不匹配
-- 假设 MV 有 WHERE status = 'paid'
SELECT order_date, user_id, SUM(amount)
FROM orders
WHERE status = 'pending'
GROUP BY order_date, user_id;
-- 不命中
```

---

## 五、带过滤条件的物化视图

### 创建带过滤的物化视图

```sql
-- 创建只聚合已支付订单的物化视图
CREATE MATERIALIZED VIEW mv_paid_orders
AS SELECT
    order_date,
    user_id,
    COUNT(*) as order_count,
    SUM(amount) as total_amount
FROM orders
WHERE status = 'paid'
GROUP BY order_date, user_id;

-- 查询自动命中
SELECT 
    order_date,
    COUNT(*) as order_count
FROM orders
WHERE status = 'paid'
  AND order_date = '2024-01-15'
GROUP BY order_date;
-- 命中 mv_paid_orders

-- 不命中的查询
SELECT 
    order_date,
    COUNT(*) as order_count
FROM orders
WHERE status = 'pending'
GROUP BY order_date;
-- 不命中，走原表
```

### 多状态物化视图

```sql
-- 已支付订单
CREATE MATERIALIZED VIEW mv_paid_orders
AS SELECT order_date, user_id, COUNT(*), SUM(amount)
FROM orders WHERE status = 'paid'
GROUP BY order_date, user_id;

-- 已发货订单
CREATE MATERIALIZED VIEW mv_shipped_orders
AS SELECT order_date, user_id, COUNT(*), SUM(amount)
FROM orders WHERE status = 'shipped'
GROUP BY order_date, user_id;

-- 已完成订单
CREATE MATERIALIZED VIEW mv_completed_orders
AS SELECT order_date, user_id, COUNT(*), SUM(amount)
FROM orders WHERE status = 'completed'
GROUP BY order_date, user_id;

-- 查询时自动选择对应的物化视图
SELECT order_date, SUM(amount) 
FROM orders 
WHERE status = 'paid' 
GROUP BY order_date;
-- 命中 mv_paid_orders
```

---

## 六、异步物化视图

### 概述

```
┌─────────────────────────────────────────────────────────────┐
│                  异步物化视图特点                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  同步物化视图                                                │
│  ─────────────────────────────────────────────────────────  │
│  - 数据导入时同步更新                                        │
│  - 导入性能有一定影响                                        │
│  - 数据实时性高                                              │
│  - 只支持单表                                                │
│                                                              │
│  异步物化视图（Doris 2.0+）                                  │
│  ─────────────────────────────────────────────────────────  │
│  - 定时刷新或手动刷新                                        │
│  - 导入性能无影响                                            │
│  - 数据有一定延迟                                            │
│  - 支持多表 JOIN                                             │
│  - 支持外表                                                  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 创建异步物化视图

```sql
-- 基本语法
CREATE MATERIALIZED VIEW [MV name]
BUILD [IMMEDIATE | DEFERRED]
REFRESH [COMPLETE | AUTO] ON [SCHEDULE | COMMIT]
AS SELECT ...;

-- 创建定时刷新的物化视图
CREATE MATERIALIZED VIEW mv_user_order_summary
BUILD IMMEDIATE 
REFRESH COMPLETE ON SCHEDULE EVERY 1 HOUR
AS SELECT
    u.user_id,
    u.user_name,
    COUNT(o.order_id) as order_count,
    SUM(o.amount) as total_amount,
    MAX(o.order_time) as last_order_time
FROM users u
LEFT JOIN orders o ON u.user_id = o.user_id
GROUP BY u.user_id, u.user_name;

-- 创建每天刷新的物化视图
CREATE MATERIALIZED VIEW mv_daily_report
BUILD IMMEDIATE
REFRESH COMPLETE ON SCHEDULE EVERY 1 DAY STARTS '2024-01-01 02:00:00'
AS SELECT
    order_date,
    COUNT(*) as order_count,
    SUM(amount) as total_amount
FROM orders
GROUP BY order_date;
```

### 刷新策略

```sql
-- 手动刷新
REFRESH MATERIALIZED VIEW mv_user_order_summary;

-- 暂停自动刷新
ALTER MATERIALIZED VIEW mv_user_order_summary SET INACTIVE;

-- 恢复自动刷新
ALTER MATERIALIZED VIEW mv_user_order_summary SET ACTIVE;

-- 修改刷新间隔
ALTER MATERIALIZED VIEW mv_user_order_summary 
SET REFRESH COMPLETE ON SCHEDULE EVERY 30 MINUTE;
```

### 查看物化视图状态

```sql
-- 查看所有物化视图
SHOW MATERIALIZED VIEWS;

-- 查看指定物化视图
SHOW MATERIALIZED VIEW mv_user_order_summary;

-- 查看刷新任务
SHOW MATERIALIZED VIEW TASK ON mv_user_order_summary;

-- 查看物化视图详情
DESC mv_user_order_summary;
```

---

## 七、高级聚合函数

### HLL 近似去重

```sql
-- 创建支持 UV 统计的物化视图
CREATE MATERIALIZED VIEW mv_daily_uv
AS SELECT
    order_date,
    category,
    HLL_UNION_AGG(hll_hash(user_id)) as uv
FROM (
    SELECT order_date, category, hll_hash(user_id) as user_id
    FROM orders
) t
GROUP BY order_date, category;

-- 查询 UV
SELECT 
    order_date,
    HLL_CARDINALITY(uv) as uv_count
FROM mv_daily_uv
WHERE order_date = '2024-01-15';
```

### Bitmap 精确去重

```sql
-- 创建支持精确 UV 的物化视图
CREATE MATERIALIZED VIEW mv_daily_uv_exact
AS SELECT
    order_date,
    category,
    BITMAP_UNION(TO_BITMAP(user_id)) as uv_bitmap
FROM orders
GROUP BY order_date, category;

-- 查询精确 UV
SELECT 
    order_date,
    BITMAP_COUNT(uv_bitmap) as uv_count
FROM mv_daily_uv_exact
WHERE order_date = '2024-01-15';
```

---

## 八、性能优化实践

### 性能对比测试

```sql
-- 测试表：1 亿行数据
CREATE TABLE test_sales (
    sale_id BIGINT,
    sale_date DATE,
    product_id BIGINT,
    category_id BIGINT,
    amount DECIMAL(10,2)
)
DUPLICATE KEY(sale_id)
PARTITION BY RANGE(sale_date) ()
DISTRIBUTED BY HASH(sale_id) BUCKETS 64;

-- 创建物化视图
CREATE MATERIALIZED VIEW mv_daily_category
AS SELECT
    sale_date,
    category_id,
    SUM(amount) as total_amount,
    COUNT(*) as sale_count
FROM test_sales
GROUP BY sale_date, category_id;

-- 性能测试
-- 查询1：原始表
SELECT sale_date, category_id, SUM(amount)
FROM test_sales
GROUP BY sale_date, category_id;
-- 耗时：15 秒

-- 查询2：自动命中物化视图
SELECT sale_date, category_id, SUM(amount)
FROM test_sales
GROUP BY sale_date, category_id;
-- 耗时：0.1 秒

-- 性能提升：150 倍
```

### 最佳实践

```
┌─────────────────────────────────────────────────────────────┐
│                  物化视图最佳实践                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. 根据查询模式设计                                        │
│     ─────────────────────────────────────────────────────── │
│     - 分析慢查询日志                                        │
│     - 找出高频聚合查询                                      │
│     - 针对性创建物化视图                                    │
│                                                              │
│  2. 控制物化视图数量                                        │
│     ─────────────────────────────────────────────────────── │
│     - 每个物化视图占用存储空间                              │
│     - 影响数据导入性能                                      │
│     - 建议：单表不超过 5 个                                 │
│                                                              │
│  3. 选择合适的聚合粒度                                      │
│     ─────────────────────────────────────────────────────── │
│     - 粗粒度：查询灵活，聚合度低                            │
│     - 细粒度：聚合度高，查询受限                            │
│     - 建议：覆盖 80% 的高频查询                             │
│                                                              │
│  4. 监控物化视图使用情况                                    │
│     ─────────────────────────────────────────────────────── │
│     - 定期检查命中率                                        │
│     - 删除未使用的物化视图                                  │
│     - 优化低效的物化视图                                    │
│                                                              │
│  5. 合理使用异步刷新                                        │
│     ─────────────────────────────────────────────────────── │
│     - 实时性要求高：同步刷新                                │
│     - 实时性要求低：异步刷新                                │
│     - 复杂计算：异步刷新                                    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 九、物化视图管理

### 查看物化视图

```sql
-- 查看所有物化视图
SHOW MATERIALIZED VIEWS;

-- 查看指定表的物化视图
SHOW MATERIALIZED VIEWS FROM db_name;

-- 查看物化视图详情
SHOW MATERIALIZED VIEW mv_name;

-- 查看物化视图结构
DESC mv_name;
```

### 删除物化视图

```sql
-- 删除物化视图
DROP MATERIALIZED VIEW mv_name;

-- 删除前检查依赖
SHOW MATERIALIZED VIEW mv_name;
```

### 修改物化视图

```sql
-- 修改刷新策略（异步MV）
ALTER MATERIALIZED VIEW mv_name 
SET REFRESH COMPLETE ON SCHEDULE EVERY 1 HOUR;

-- 暂停刷新
ALTER MATERIALIZED VIEW mv_name SET INACTIVE;

-- 恢复刷新
ALTER MATERIALIZED VIEW mv_name SET ACTIVE;

-- 修改物化视图名称
ALTER MATERIALIZED VIEW mv_name RENAME new_mv_name;
```

---

## 十、常见问题

### Q1: 物化视图为什么没有命中？

```sql
-- 检查执行计划
EXPLAIN SELECT ...;

-- 常见原因：
-- 1. GROUP BY 列不匹配
-- 2. 聚合函数不支持
-- 3. WHERE 条件不匹配
-- 4. SELECT 列不在物化视图中
```

### Q2: 物化视图数据不一致？

```sql
-- 检查物化视图状态
SHOW MATERIALIZED VIEW mv_name;

-- 手动刷新
REFRESH MATERIALIZED VIEW mv_name;

-- 重建物化视图
DROP MATERIALIZED VIEW mv_name;
CREATE MATERIALIZED VIEW mv_name AS ...;
```

### Q3: 物化视图占用空间过大？

```sql
-- 查看物化视图大小
SHOW DATA FROM mv_name;

-- 优化建议：
-- 1. 减少聚合粒度
-- 2. 删除不必要的列
-- 3. 使用压缩
```

---

## 下一步

- [Join 优化](./05-join-optimization.md) - 学习 Join 优化策略
- [性能调优](./08-performance-tuning.md) - 系统级性能调优
