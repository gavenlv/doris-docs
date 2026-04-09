# 查询优化

## 概述

查询优化是 Doris 性能调优的核心。本章将深入讲解执行计划分析、慢查询诊断和优化技巧。

```
┌─────────────────────────────────────────────────────────────┐
│                    查询优化流程                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. 问题发现                                                 │
│     ┌─────────────────────────────────────────────────┐     │
│     │  慢查询日志 / 监控告警 / 用户反馈               │     │
│     └─────────────────────────────────────────────────┘     │
│                           ↓                                  │
│  2. 执行计划分析                                             │
│     ┌─────────────────────────────────────────────────┐     │
│     │  EXPLAIN / PROFILE / 查看执行计划               │     │
│     └─────────────────────────────────────────────────┘     │
│                           ↓                                  │
│  3. 瓶颈定位                                                 │
│     ┌─────────────────────────────────────────────────┐     │
│     │  扫描数据量 / Join 策略 / 内存使用              │     │
│     └─────────────────────────────────────────────────┘     │
│                           ↓                                  │
│  4. 优化实施                                                 │
│     ┌─────────────────────────────────────────────────┐     │
│     │  索引优化 / Join 优化 / 参数调优                │     │
│     └─────────────────────────────────────────────────┘     │
│                           ↓                                  │
│  5. 效果验证                                                 │
│     ┌─────────────────────────────────────────────────┐     │
│     │  对比优化前后性能 / 持续监控                    │     │
│     └─────────────────────────────────────────────────┘     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 一、执行计划分析

### EXPLAIN 命令

```sql
-- 查看执行计划
EXPLAIN SELECT * FROM orders WHERE order_date = '2024-01-15';

-- 查看详细执行计划
EXPLAIN VERBOSE SELECT * FROM orders WHERE order_date = '2024-01-15';

-- 输出示例
+------------------------------------------------------------------------------------+
| Explain String                                                                     |
+------------------------------------------------------------------------------------+
| PLAN FRAGMENT 0                                                                    |
|   OUTPUT EXPRS:                                                                    |
|     `order_id`                                                                     |
|     `user_id`                                                                      |
|     `order_date`                                                                   |
|     `amount`                                                                       |
|   PARTITION: UNPARTITIONED                                                         |
|                                                                                    |
|   RESULT SINK                                                                      |
|                                                                                    |
|   1:EXCHANGE                                                                       |
|      distribution: Random                                                          |
|                                                                                    |
| PLAN FRAGMENT 1                                                                    |
|   OUTPUT EXPRS:                                                                    |
|   PARTITION: RANDOM                                                                |
|                                                                                    |
|   STREAM DATA SINK                                                                 |
|     EXCHANGE ID: 01                                                                |
|     UNPARTITIONED                                                                  |
|                                                                                    |
|   0:OlapScanNode                                                                   |
|      TABLE: orders                                                                 |
|      PREAGGREGATION: ON                                                            |
|      PREDICATES: `order_date` = '2024-01-15'                                       |
|      partitions=1/10                                                               |
|      rollup: orders                                                                |
|      tabletRatio=32/32                                                             |
|      tabletList=10001,10002,...                                                    |
|      cardinality=100000                                                            |
|      avgRowSize=100.0                                                              |
+------------------------------------------------------------------------------------+
```

### PROFILE 分析

```sql
-- 开启 Profile
SET enable_profile = true;

-- 执行查询
SELECT * FROM orders WHERE order_date = '2024-01-15';

-- 查看 Profile
SHOW QUERY PROFILE 'xxx';

-- 输出示例
Query:
  Summary:
    - Query ID: xxx
    - Start Time: 2024-01-15 10:30:00
    - End Time: 2024-01-15 10:30:01
    - Total Time: 1s
    - Query State: EOF
    
  Fragment 0:
    - Instance Num: 3
    - Memory Usage: 100MB
    
    OlapScanNode:
      - Tablet Count: 32
      - Rows Read: 100000
      - Bytes Read: 10MB
      - Scan Time: 500ms
      
    EXCHANGE:
      - Send Rows: 100000
      - Send Bytes: 10MB
      - Network Time: 100ms
```

### 关键指标解读

| 指标 | 说明 | 优化方向 |
|------|------|---------|
| partitions | 扫描的分区数 | 减少分区扫描 |
| tabletRatio | 扫描的 Tablet 比例 | 利用分区裁剪 |
| cardinality | 预估行数 | 优化统计信息 |
| rowsRead | 实际读取行数 | 添加过滤条件 |
| bytesRead | 读取字节数 | 减少扫描列 |
| scanTime | 扫描耗时 | 索引优化 |

---

## 二、慢查询诊断

### 慢查询日志

```sql
-- 查看慢查询
SHOW SLOW QUERY;

-- 查看指定时间范围的慢查询
SHOW SLOW QUERY WHERE start_time > '2024-01-01';

-- 查看正在运行的查询
SHOW RUNNING QUERIES;

-- 取消慢查询
CANCEL QUERY 'query_id';
```

### 慢查询分析

```sql
-- 1. 查看查询详情
SHOW QUERY PROFILE 'query_id';

-- 2. 分析执行计划
EXPLAIN VERBOSE SELECT ...;

-- 3. 检查统计信息
SHOW TABLE STATS table_name;

-- 4. 检查索引使用
SHOW INDEX FROM table_name;
```

---

## 三、常见优化模式

### 1. 分区裁剪

```sql
-- 优化前：全表扫描
SELECT * FROM orders WHERE user_id = 123;

-- 优化后：利用分区裁剪
SELECT * FROM orders 
WHERE order_date = '2024-01-15' 
  AND user_id = 123;
```

### 2. 列裁剪

```sql
-- 优化前：SELECT *
SELECT * FROM orders WHERE user_id = 123;

-- 优化后：只查询需要的列
SELECT order_id, amount FROM orders WHERE user_id = 123;
```

### 3. 索引优化

```sql
-- 优化前：未命中索引
SELECT * FROM users WHERE age = 25;

-- 优化后：使用 Bloom Filter 索引
-- 创建索引
ALTER TABLE users SET ("bloom_filter_columns" = "age");

-- 查询命中索引
SELECT * FROM users WHERE age = 25;
```

### 4. Join 优化

```sql
-- 优化前：大表 Join 大表
SELECT * FROM orders o
JOIN order_items i ON o.order_id = i.order_id;

-- 优化后：使用 Colocate Join
-- 创建 Colocate Group
CREATE TABLE orders (...)
DISTRIBUTED BY HASH(order_id) BUCKETS 32
PROPERTIES ("colocate_with" = "order_group");

CREATE TABLE order_items (...)
DISTRIBUTED BY HASH(order_id) BUCKETS 32
PROPERTIES ("colocate_with" = "order_group");
```

### 5. 聚合优化

```sql
-- 优化前：大表聚合
SELECT user_id, COUNT(*) FROM orders GROUP BY user_id;

-- 优化后：使用物化视图
CREATE MATERIALIZED VIEW mv_user_order_count
AS SELECT user_id, COUNT(*) as order_count 
FROM orders GROUP BY user_id;

-- 查询自动使用物化视图
SELECT user_id, COUNT(*) FROM orders GROUP BY user_id;
```

---

## 四、优化器提示

### 使用 Hints

```sql
-- 指定 Join 顺序
SELECT /*+ LEADING(orders, users) */ *
FROM orders o
JOIN users u ON o.user_id = u.user_id;

-- 指定 Join 类型
SELECT /*+ SHUFFLE_JOIN(orders, users) */ *
FROM orders o
JOIN users u ON o.user_id = u.user_id;

-- 指定并行度
SELECT /*+ PARALLEL(8) */ *
FROM orders WHERE order_date = '2024-01-15';

-- 禁用特定优化
SELECT /*+ SET_VAR(enable_vectorized_engine=false) */ *
FROM orders;
```

### 常用 Hints

| Hint | 说明 |
|------|------|
| LEADING | 指定 Join 顺序 |
| SHUFFLE_JOIN | 使用 Shuffle Join |
| BROADCAST_JOIN | 使用 Broadcast Join |
| COLOCATE_JOIN | 使用 Colocate Join |
| PARALLEL | 指定并行度 |
| SET_VAR | 设置会话变量 |

---

## 五、参数调优

### 内存相关

```sql
-- 增加查询内存
SET exec_mem_limit = 8589934592;  -- 8GB

-- 增加扫描内存
SET scan_mem_limit = 4294967296;  -- 4GB

-- 增加排序内存
SET sort_buffer_size = 1073741824;  -- 1GB
```

### 并行相关

```sql
-- 增加并行度
SET parallel_fragment_exec_instance_num = 8;

-- 启用向量化引擎
SET enable_vectorized_engine = true;

-- 启用 Pipeline 引擎
SET enable_pipeline_engine = true;
```

### 其他参数

```sql
-- 启用 Runtime Filter
SET runtime_filter_type = "IN_OR_BLOOM_FILTER";
SET runtime_filter_mode = "GLOBAL";

-- 启用查询缓存
SET enable_query_cache = true;
SET query_cache_capacity = 1073741824;  -- 1GB
```

---

## 六、优化案例

### 案例1：慢查询优化

**问题**：查询耗时 30 秒

```sql
SELECT * FROM orders 
WHERE user_id = 123 
ORDER BY order_time DESC 
LIMIT 100;
```

**分析**：
- 未命中分区裁剪
- 未命中索引
- 排序开销大

**优化**：

```sql
-- 1. 添加分区条件
SELECT * FROM orders 
WHERE order_date >= DATE_SUB(CURRENT_DATE, INTERVAL 30 DAY)
  AND user_id = 123 
ORDER BY order_time DESC 
LIMIT 100;

-- 2. 创建 Bloom Filter 索引
ALTER TABLE orders SET ("bloom_filter_columns" = "user_id");

-- 3. 调整排序键
ALTER TABLE orders ORDER BY (user_id, order_time DESC);
```

**结果**：查询耗时降至 0.5 秒

### 案例2：Join 优化

**问题**：大表 Join 耗时 60 秒

```sql
SELECT o.*, u.user_name
FROM orders o
JOIN users u ON o.user_id = u.user_id
WHERE o.order_date = '2024-01-15';
```

**分析**：
- orders 表 10 亿行
- users 表 1000 万行
- 使用 Shuffle Join

**优化**：

```sql
-- 1. 使用 Colocate Join
CREATE TABLE orders (...)
DISTRIBUTED BY HASH(user_id) BUCKETS 32
PROPERTIES ("colocate_with" = "user_group");

CREATE TABLE users (...)
DISTRIBUTED BY HASH(user_id) BUCKETS 32
PROPERTIES ("colocate_with" = "user_group");

-- 2. 使用 Runtime Filter
SET runtime_filter_type = "IN_OR_BLOOM_FILTER";
SET runtime_filter_mode = "GLOBAL";

-- 3. 使用 Broadcast Join（小表广播）
SELECT /*+ BROADCAST_JOIN(users) */ o.*, u.user_name
FROM orders o
JOIN users u ON o.user_id = u.user_id
WHERE o.order_date = '2024-01-15';
```

**结果**：查询耗时降至 5 秒

---

## 下一步

- [Join 优化](./05-join-optimization.md) - 深入学习 Join 优化
- [物化视图](./06-materialized-view.md) - 学习物化视图
- [性能调优](./08-performance-tuning.md) - 系统级调优
