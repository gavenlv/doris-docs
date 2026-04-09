# 高级表设计

## 概述

表设计是性能优化的基础。好的表设计可以大幅提升查询性能，降低存储成本。

```
┌─────────────────────────────────────────────────────────────┐
│                    表设计核心要素                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. 数据模型选择                                             │
│     ┌─────────────────────────────────────────────────┐     │
│     │  Duplicate / Aggregate / Unique                 │     │
│     └─────────────────────────────────────────────────┘     │
│                                                              │
│  2. 分区策略                                                 │
│     ┌─────────────────────────────────────────────────┐     │
│     │  Range / List / 动态分区                        │     │
│     └─────────────────────────────────────────────────┘     │
│                                                              │
│  3. 分桶策略                                                 │
│     ┌─────────────────────────────────────────────────┐     │
│     │  Hash 分桶 / 分桶数选择                         │     │
│     └─────────────────────────────────────────────────┘     │
│                                                              │
│  4. 排序键设计                                               │
│     ┌─────────────────────────────────────────────────┐     │
│     │  DUPLICATE KEY / AGGREGATE KEY / UNIQUE KEY     │     │
│     └─────────────────────────────────────────────────┘     │
│                                                              │
│  5. 索引设计                                                 │
│     ┌─────────────────────────────────────────────────┐     │
│     │  前缀索引 / Bloom Filter / Bitmap / 倒排索引    │     │
│     └─────────────────────────────────────────────────┘     │
│                                                              │
│  6. 存储优化                                                 │
│     ┌─────────────────────────────────────────────────┐     │
│     │  压缩 / 编码 / 副本数                           │     │
│     └─────────────────────────────────────────────────┘     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 一、数据模型选择

### 选择决策树

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

### 性能对比

```
写入性能：
Duplicate Key > Aggregate Key > Unique Key

查询性能（聚合查询）：
Aggregate Key > Unique Key > Duplicate Key

存储空间：
Aggregate Key < Unique Key < Duplicate Key
```

---

## 二、分区策略

### Range 分区

```sql
-- 按日期范围分区
CREATE TABLE orders (
    order_id BIGINT,
    user_id BIGINT,
    order_date DATE,
    amount DECIMAL(10,2),
    ...
)
PARTITION BY RANGE(order_date) (
    PARTITION p202401 VALUES LESS THAN ('2024-02-01'),
    PARTITION p202402 VALUES LESS THAN ('2024-03-01'),
    PARTITION p202403 VALUES LESS THAN ('2024-04-01'),
    PARTITION p202404 VALUES LESS THAN ('2024-05-01')
);

-- 分区裁剪优化
SELECT * FROM orders 
WHERE order_date BETWEEN '2024-01-01' AND '2024-01-31';
-- 只扫描 p202401 分区
```

### 动态分区

```sql
-- 自动创建和删除分区
CREATE TABLE events (
    event_id BIGINT,
    event_time DATETIME,
    event_type VARCHAR(50),
    ...
)
PARTITION BY RANGE(event_time) ()
DISTRIBUTED BY HASH(event_id) BUCKETS 10
PROPERTIES (
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-7",       -- 保留 7 天
    "dynamic_partition.end" = "3",          -- 预创建 3 天
    "dynamic_partition.prefix" = "p",
    "dynamic_partition.buckets" = "10"
);
```

### List 分区

```sql
-- 按地区分区
CREATE TABLE sales (
    sale_id BIGINT,
    region VARCHAR(50),
    amount DECIMAL(10,2),
    ...
)
PARTITION BY LIST(region) (
    PARTITION p_north VALUES IN ('北京', '天津', '河北'),
    PARTITION p_east VALUES IN ('上海', '江苏', '浙江'),
    PARTITION p_south VALUES IN ('广州', '深圳', '福建')
);
```

### 分区设计原则

| 原则 | 说明 |
|------|------|
| 分区列选择 | 选择查询常用的过滤列 |
| 分区粒度 | 根据数据量选择，一般按天/月 |
| 分区数量 | 单表不超过 1000 个分区 |
| 数据均匀 | 每个分区数据量尽量均匀 |

---

## 三、分桶策略

### Hash 分桶

```sql
-- 按 user_id 分桶
CREATE TABLE users (
    user_id BIGINT,
    user_name VARCHAR(100),
    ...
)
DISTRIBUTED BY HASH(user_id) BUCKETS 32;

-- 分桶列选择原则
-- 1. 高基数列
-- 2. 常用于 Join 的列
-- 3. 常用于 Group By 的列
```

### 分桶数选择

```
┌─────────────────────────────────────────────────────────────┐
│                    分桶数选择指南                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  数据量          分桶数         说明                         │
│  ─────────────────────────────────────────────────────────  │
│  < 100万        1-10          小表，少量分桶                │
│  100万-1000万   10-32         中表，适中分桶                │
│  1000万-1亿     32-64         大表，较多分桶                │
│  1亿-10亿       64-128        超大表，大量分桶              │
│  > 10亿         128-256       海量表，分桶数 = BE数 * N     │
│                                                              │
│  注意事项：                                                  │
│  - 每个 Tablet 数据量建议 100MB-1GB                         │
│  - 分桶数 = BE 节点数 * N (N 为每节点 Tablet 数)            │
│  - 分桶数不宜过多，避免小文件问题                            │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Colocate Group

```sql
-- 创建 Colocate Group
CREATE TABLE orders (
    order_id BIGINT,
    user_id BIGINT,
    ...
)
DISTRIBUTED BY HASH(user_id) BUCKETS 32
PROPERTIES (
    "colocate_with" = "group1"
);

CREATE TABLE users (
    user_id BIGINT,
    user_name VARCHAR(100),
    ...
)
DISTRIBUTED BY HASH(user_id) BUCKETS 32
PROPERTIES (
    "colocate_with" = "group1"
);

-- 相同 Colocate Group 的表，相同 hash 值的数据在同一 BE
-- Join 时无需网络传输，性能大幅提升
```

---

## 四、排序键设计

### 排序键原理

```
┌─────────────────────────────────────────────────────────────┐
│                    排序键 (Sort Key)                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  数据存储时按排序键排序，查询时可以利用：                     │
│                                                              │
│  1. 前缀索引                                                 │
│     ┌─────────────────────────────────────────────────┐     │
│     │  排序键的前几列自动创建前缀索引                  │     │
│     │  加速前缀匹配查询                                │     │
│     └─────────────────────────────────────────────────┘     │
│                                                              │
│  2. Zone Map                                                 │
│     ┌─────────────────────────────────────────────────┐     │
│     │  每个 Segment 记录 min/max 值                    │     │
│     │  加速范围查询                                    │     │
│     └─────────────────────────────────────────────────┘     │
│                                                              │
│  3. 数据压缩                                                 │
│     ┌─────────────────────────────────────────────────┐     │
│     │  有序数据压缩率更高                              │     │
│     │  减少存储空间                                    │     │
│     └─────────────────────────────────────────────────┘     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 排序键选择

```sql
-- 好的设计：查询常用列作为排序键
CREATE TABLE orders (
    order_id BIGINT,           -- 排序键第一列
    user_id BIGINT,            -- 排序键第二列
    order_date DATE,           -- 排序键第三列
    ...
)
DUPLICATE KEY(order_id, user_id, order_date);

-- 查询优化
SELECT * FROM orders WHERE order_id = 123;           -- 命中前缀索引
SELECT * FROM orders WHERE order_id = 123 AND user_id = 456;  -- 命中前缀索引
SELECT * FROM orders WHERE user_id = 456;            -- 未命中前缀索引（性能差）
```

### 排序键设计原则

| 原则 | 说明 |
|------|------|
| 高选择性 | 选择区分度高的列 |
| 查询匹配 | 与常用查询条件匹配 |
| 列顺序 | 高选择性列放前面 |
| 列数量 | 建议 2-4 列 |

---

## 五、索引设计

### 前缀索引（自动）

```sql
-- 前缀索引自动创建
CREATE TABLE users (
    user_id BIGINT,        -- 前缀索引第一列
    user_name VARCHAR(100), -- 前缀索引第二列
    age INT,
    ...
)
DUPLICATE KEY(user_id, user_name);

-- 前缀索引最多支持 36 字节
-- VARCHAR 类型只取前缀部分
```

### Bloom Filter 索引

```sql
-- 创建 Bloom Filter 索引
CREATE TABLE orders (
    order_id BIGINT,
    user_id BIGINT,
    product_id BIGINT,
    ...
)
DUPLICATE KEY(order_id)
DISTRIBUTED BY HASH(order_id) BUCKETS 32
PROPERTIES (
    "bloom_filter_columns" = "user_id,product_id",
    "bloom_filter_fpp" = "0.01"  -- 假阳性率
);

-- Bloom Filter 适用于等值查询
SELECT * FROM orders WHERE user_id = 123;
```

### Bitmap 索引

```sql
-- 创建 Bitmap 索引
CREATE TABLE users (
    user_id BIGINT,
    gender VARCHAR(10),
    city VARCHAR(50),
    ...
);

-- 为低基数列创建 Bitmap 索引
CREATE INDEX idx_gender ON users(gender) USING BITMAP;
CREATE INDEX idx_city ON users(city) USING BITMAP;

-- Bitmap 索引适用于低基数列的等值查询
SELECT * FROM users WHERE gender = '男' AND city = '北京';
```

### 倒排索引

```sql
-- 创建倒排索引
CREATE TABLE logs (
    log_id BIGINT,
    content STRING,
    ...
);

-- 创建倒排索引支持全文搜索
CREATE INDEX idx_content ON logs(content) USING INVERTED
PROPERTIES (
    "parser" = "standard",
    "support_phrase" = "true"
);

-- 全文搜索
SELECT * FROM logs WHERE content MATCH 'error';
SELECT * FROM logs WHERE content MATCH_PHRASE 'system error';
```

---

## 六、存储优化

### 压缩策略

```sql
-- 指定压缩算法
CREATE TABLE orders (
    ...
)
PROPERTIES (
    "compression" = "LZ4"  -- LZ4 / ZSTD / SNAPPY
);

-- 压缩算法对比
-- LZ4: 压缩速度快，压缩率中等
-- ZSTD: 压缩速度中等，压缩率高
-- SNAPPY: 压缩速度快，压缩率低
```

### 编码策略

```sql
-- 指定列编码
CREATE TABLE users (
    user_id BIGINT,
    user_name VARCHAR(100) PROPERTIES ("encoding" = "DICT"),
    age INT PROPERTIES ("encoding" = "BIT_SHUFFLE"),
    city VARCHAR(50) PROPERTIES ("encoding" = "DICT"),
    ...
);

-- 编码类型
-- DICT: 字典编码，适合低基数列
-- BIT_SHUFFLE: 位洗牌编码，适合数值列
-- RLE: 游程编码，适合重复值多的列
```

### 副本数设置

```sql
-- 设置副本数
CREATE TABLE orders (
    ...
)
PROPERTIES (
    "replication_num" = "3"  -- 默认 3 副本
);

-- 不同场景的副本数
-- 开发/测试: 1 副本
-- 生产环境: 3 副本
-- 高可用要求: 5 副本
```

---

## 七、表设计最佳实践

### 订单表设计示例

```sql
CREATE TABLE orders (
    order_id BIGINT COMMENT '订单ID',
    user_id BIGINT COMMENT '用户ID',
    product_id BIGINT COMMENT '商品ID',
    order_date DATE COMMENT '订单日期',
    order_time DATETIME COMMENT '订单时间',
    amount DECIMAL(12,2) COMMENT '订单金额',
    status VARCHAR(20) COMMENT '订单状态',
    province VARCHAR(50) COMMENT '省份',
    city VARCHAR(50) COMMENT '城市'
)
DUPLICATE KEY(order_id, user_id, order_date)
COMMENT '订单表'
PARTITION BY RANGE(order_date) (
    PARTITION p202401 VALUES LESS THAN ('2024-02-01'),
    PARTITION p202402 VALUES LESS THAN ('2024-03-01'),
    PARTITION p202403 VALUES LESS THAN ('2024-04-01')
)
DISTRIBUTED BY HASH(user_id) BUCKETS 32
PROPERTIES (
    "replication_num" = "3",
    "bloom_filter_columns" = "product_id",
    "compression" = "LZ4",
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "MONTH",
    "dynamic_partition.start" = "-12",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p"
);

-- 创建 Bitmap 索引
CREATE INDEX idx_status ON orders(status) USING BITMAP;
CREATE INDEX idx_province ON orders(province) USING BITMAP;
```

### 用户行为表设计示例

```sql
CREATE TABLE user_behavior (
    user_id BIGINT COMMENT '用户ID',
    event_time DATETIME COMMENT '事件时间',
    event_type VARCHAR(50) COMMENT '事件类型',
    page_id VARCHAR(100) COMMENT '页面ID',
    device_id VARCHAR(100) COMMENT '设备ID',
    session_id VARCHAR(100) COMMENT '会话ID',
    extra_info STRING COMMENT '扩展信息'
)
DUPLICATE KEY(user_id, event_time)
COMMENT '用户行为表'
PARTITION BY RANGE(event_time) ()
DISTRIBUTED BY HASH(user_id) BUCKETS 64
PROPERTIES (
    "replication_num" = "3",
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-30",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "compression" = "ZSTD"
);

-- 创建倒排索引支持事件类型搜索
CREATE INDEX idx_event_type ON user_behavior(event_type) USING INVERTED;
```

---

## 下一步

- [分区分桶策略](./02-partition-bucket.md) - 深入学习分区分桶
- [索引深入](./03-index-deep-dive.md) - 深入学习索引优化
- [查询优化](./04-query-optimization.md) - 学习查询优化
