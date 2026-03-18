# Doris 数据工程师完整指南

## 目录

1. [快速入门](#快速入门)
2. [核心概念](#核心概念)
3. [数据建模](#数据建模)
4. [数据导入](#数据导入)
5. [查询优化](#查询优化)
6. [性能调优](#性能调优)
7. [生产最佳实践](#生产最佳实践)

---

## 快速入门

### 5 分钟上手 Doris

```sql
-- 1. 连接 Doris
mysql -h 127.0.0.1 -P 9030 -u root

-- 2. 创建数据库
CREATE DATABASE demo;
USE demo;

-- 3. 创建表
CREATE TABLE events (
    event_time DATETIME,
    user_id BIGINT,
    event_type VARCHAR(50),
    properties JSON
)
DUPLICATE KEY(event_time, user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 10;

-- 4. 插入数据
INSERT INTO events VALUES 
(NOW(), 1, 'click', '{"page": "home"}'),
(NOW(), 2, 'view', '{"page": "product"}');

-- 5. 查询数据
SELECT event_type, COUNT(*) as cnt 
FROM events 
GROUP BY event_type;
```

---

## 核心概念

### 数据模型

Doris 提供三种数据模型，选择适合的模型至关重要：

| 模型 | 特点 | 适用场景 |
|------|------|---------|
| **明细模型 (Duplicate)** | 保留所有原始数据 | 日志、事件流 |
| **聚合模型 (Aggregate)** | 预聚合，节省存储 | 报表、统计 |
| **更新模型 (Unique/MoW)** | 支持数据更新 | 维度表、状态表 |

```sql
-- 明细模型 - 原始数据保留
CREATE TABLE user_events (
    event_time DATETIME,
    user_id BIGINT,
    event_type VARCHAR(50),
    cost DECIMAL(10,2)
)
DUPLICATE KEY(event_time, user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 16;

-- 聚合模型 - 预聚合存储
CREATE TABLE sales_stats (
    dt DATE,
    product_id BIGINT,
    total_amount SUM(DECIMAL(10,2)),
    count_users COUNT(DISTINCT user_id)
)
AGGREGATE KEY(dt, product_id)
DISTRIBUTED BY HASH(product_id) BUCKETS 16;

-- Unique MoW 模型 - 支持更新
CREATE TABLE user_profile (
    user_id BIGINT,
    name VARCHAR(100),
    age INT,
    update_time DATETIME
)
UNIQUE KEY(user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 16
PROPERTIES ("enable_unique_key_merge_on_write" = "true");
```

### 分区分桶策略

```sql
-- 时间分区 + 哈希分桶
CREATE TABLE logs (
    dt DATE,
    hour INT,
    user_id BIGINT,
    message VARCHAR(500)
)
PARTITION BY RANGE(dt) (
    PARTITION p202401 VALUES LESS THAN ("2024-02-01"),
    PARTITION p202402 VALUES LESS THAN ("2024-03-01"),
    PARTITION p202403 VALUES LESS THAN ("2024-04-01"),
    PARTITION pother VALUES LESS THAN MAXVALUE
)
DISTRIBUTED BY HASH(user_id) BUCKETS 32;
```

**分桶数计算公式**：
```
单分区数据量 ≈ 1GB → buckets = 8-16
单分区数据量 ≈ 10GB → buckets = 16-32
单分区数据量 ≈ 100GB → buckets = 32-64

原则：buckets = BE节点数 × 2
```

---

## 数据建模

### 实战建模案例

#### 案例 1：用户行为分析平台

```sql
-- 事件表（海量数据）
CREATE TABLE user_events (
    -- 时间字段放最前面
    event_time DATETIME,
    dt DATE,
    
    -- 用户维度
    user_id BIGINT,
    device_id VARCHAR(50),
    
    -- 事件属性
    event_name VARCHAR(100),
    event_category VARCHAR(50),
    
    -- 地理位置
    country VARCHAR(50),
    city VARCHAR(50),
    
    -- 设备信息
    platform VARCHAR(20),
    os VARCHAR(20),
    app_version VARCHAR(20),
    
    -- 业务属性
    session_id VARCHAR(50),
    page_url VARCHAR(500),
    referrer_url VARCHAR(500),
    
    -- 扩展属性（JSON）
    properties JSON,
    
    -- 数值指标
    duration_ms INT,
    value DECIMAL(10,2)
)
DUPLICATE KEY(dt, event_time, user_id)
PARTITION BY RANGE(dt) (
    FROM ("2024-01-01") TO ("2025-01-01") INTERVAL 1 MONTH
)
DISTRIBUTED BY HASH(user_id) BUCKETS 64
PROPERTIES (
    "replication_num" = "3",
    "storage_format" = "V2",
    "light_schema_change" = "true",
    "dynamic_partition.enable" = "true",
    "dynamic_partition.create_history_partition" = "true",
    "dynamic_partition.history_partition_num" = "12",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p"
);

-- 用户维度表（可更新）
CREATE TABLE dim_users (
    user_id BIGINT,
    register_date DATE,
    first_visit_date DATE,
    channel VARCHAR(50),
    country VARCHAR(50),
    city VARCHAR(50),
    age_group VARCHAR(20),
    gender VARCHAR(10),
    membership_level INT,
    update_time DATETIME
)
UNIQUE KEY(user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 16
PROPERTIES (
    "enable_unique_key_merge_on_write" = "true",
    "replication_num" = "3"
);

-- 物化视图：日活统计
CREATE MATERIALIZED VIEW mv_daily_active AS
SELECT 
    dt,
    COUNT(DISTINCT user_id) as dau,
    COUNT(*) as total_events,
    COUNT(DISTINCT session_id) as sessions
FROM user_events
GROUP BY dt;

-- 物化视图：留存分析
CREATE MATERIALIZED VIEW mv_retention AS
SELECT 
    dt,
    first_visit_date,
    COUNT(DISTINCT user_id) as users,
    DATEDIFF(dt, first_visit_date) as retention_day
FROM (
    SELECT 
        dt,
        user_id,
        MIN(dt) OVER (PARTITION BY user_id) as first_visit_date
    FROM user_events
) t
GROUP BY dt, first_visit_date, retention_day;
```

#### 案例 2：电商实时分析

```sql
-- 订单表（实时写入）
CREATE TABLE orders (
    order_id BIGINT,
    order_time DATETIME,
    dt DATE,
    
    -- 用户
    user_id BIGINT,
    
    -- 商品
    product_id BIGINT,
    category_id INT,
    brand_id INT,
    
    -- 金额
    original_amount DECIMAL(12,2),
    discount_amount DECIMAL(12,2),
    final_amount DECIMAL(12,2),
    
    -- 状态
    order_status TINYINT COMMENT '0:待支付 1:已支付 2:已发货 3:已完成 4:已取消',
    pay_time DATETIME,
    
    -- 扩展
    properties JSON,
    
    INDEX idx_order_time (order_time) USING INVERTED,
    INDEX idx_user_id (user_id) USING INVERTED
)
UNIQUE KEY(order_id)
PARTITION BY RANGE(dt) (
    FROM ("2024-01-01") TO ("2025-01-01") INTERVAL 1 DAY
)
DISTRIBUTED BY HASH(order_id) BUCKETS 32
PROPERTIES (
    "enable_unique_key_merge_on_write" = "true",
    "dynamic_partition.enable" = "true",
    "dynamic_partition.end" = "7"
);

-- 商品维度表
CREATE TABLE dim_products (
    product_id BIGINT,
    product_name VARCHAR(200),
    category_id INT,
    category_name VARCHAR(100),
    brand_id INT,
    brand_name VARCHAR(100),
    price DECIMAL(10,2),
    cost DECIMAL(10,2),
    status TINYINT,
    create_time DATETIME,
    update_time DATETIME
)
UNIQUE KEY(product_id)
DISTRIBUTED BY HASH(product_id) BUCKETS 16;
```

---

## 数据导入

### 导入方式对比

| 方式 | 适用场景 | 速度 | 复杂度 |
|------|---------|------|--------|
| **Stream Load** | 实时流、小文件 | 快 | 低 |
| **Broker Load** | 批量、云存储 | 快 | 中 |
| **Routine Load** | Kafka 流 | 快 | 中 |
| **Insert Into** | 小批量 | 慢 | 低 |
| **TVF** | 直接查询文件 | 中 | 低 |

### Stream Load 实战

```python
#!/usr/bin/env python3
"""
Doris Stream Load 批量导入工具
"""

import requests
import pandas as pd
import json
from concurrent.futures import ThreadPoolExecutor

class DorisStreamLoader:
    def __init__(self, be_hosts, database, table, username='root', password=''):
        self.be_hosts = be_hosts  # ['be1:8040', 'be2:8040', ...]
        self.database = database
        self.table = table
        self.auth = (username, password)
        self.be_index = 0
        
    def get_be(self):
        """轮询选择 BE"""
        be = self.be_hosts[self.be_index % len(self.be_hosts)]
        self.be_index += 1
        return be
    
    def load_json(self, data_list, label_prefix='batch'):
        """导入 JSON 数据"""
        be = self.get_be()
        url = f"http://{be}/{self.database}/{self.table}/_stream_load"
        
        headers = {
            'Content-Type': 'application/json',
            'label': f"{label_prefix}_{pd.Timestamp.now().strftime('%Y%m%d%H%M%S')}_{self.be_index}",
            'format': 'json',
            'jsonpaths': '["$._timestamp", "$.user_id", "$.event_type", "$.properties"]',
            'strip_outer_array': 'true',
            'max_filter_ratio': '0.1'
        }
        
        response = requests.put(
            url, 
            data=json.dumps(data_list),
            headers=headers,
            auth=self.auth
        )
        return response.json()
    
    def load_csv(self, csv_data, columns, label_prefix='batch'):
        """导入 CSV 数据"""
        be = self.get_be()
        url = f"http://{be}/{self.database}/{self.table}/_stream_load"
        
        headers = {
            'Content-Type': 'text/plain; charset=UTF-8',
            'label': f"{label_prefix}_{pd.Timestamp.now().strftime('%Y%m%d%H%M%S')}_{self.be_index}",
            'column_separator': ',',
            'columns': ','.join(columns),
            'max_filter_ratio': '0.1'
        }
        
        response = requests.put(
            url,
            data=csv_data,
            headers=headers,
            auth=self.auth
        )
        return response.json()
    
    def parallel_load(self, data_chunks, max_workers=10):
        """并行导入"""
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures = []
            for i, chunk in enumerate(data_chunks):
                future = executor.submit(self.load_json, chunk, f'batch_{i}')
                futures.append(future)
            
            results = [f.result() for f in futures]
        return results

# 使用示例
loader = DorisStreamLoader(
    be_hosts=['127.0.0.1:8040'],
    database='demo',
    table='events'
)

# 单条导入
data = [
    {'_timestamp': '2024-01-01 10:00:00', 'user_id': 1, 'event_type': 'click', 'properties': '{}'},
    {'_timestamp': '2024-01-01 10:01:00', 'user_id': 2, 'event_type': 'view', 'properties': '{}'}
]
result = loader.load_json(data)
print(result)
```

### Broker Load 批量导入

```sql
-- 从 S3/GCS 批量导入
LOAD LABEL demo.batch_load_20240101 (
    DATA INFILE("s3://bucket/path/*.parquet")
    INTO TABLE events
    FORMAT AS "parquet"
    (event_time, user_id, event_type, properties)
)
WITH S3 (
    "AWS_ENDPOINT" = "s3.us-west-2.amazonaws.com",
    "AWS_ACCESS_KEY" = "your_key",
    "AWS_SECRET_KEY" = "your_secret",
    "AWS_REGION" = "us-west-2"
)
PROPERTIES (
    "timeout" = "3600",
    "max_filter_ratio" = "0.1"
);

-- 查看导入状态
SHOW LOAD WHERE LABEL = 'batch_load_20240101';

-- 取消导入
CANCEL LOAD WHERE LABEL = 'batch_load_20240101';
```

### Routine Load Kafka 流

```sql
-- 创建 Kafka 例行导入
CREATE ROUTINE LOAD demo.kafka_load ON events
COLUMNS(event_time, user_id, event_type, properties)
PROPERTIES (
    "desired_concurrent_number" = "3",
    "max_batch_interval" = "20",
    "max_batch_rows" = "300000",
    "max_batch_size" = "209715200"
)
FROM KAFKA (
    "kafka_broker_list" = "kafka1:9092,kafka2:9092",
    "kafka_topic" = "user_events",
    "kafka_partitions" = "0,1,2,3",
    "kafka_offsets" = "OFFSET_BEGINNING",
    "property.security.protocol" = "SASL_SSL",
    "property.sasl.mechanism" = "PLAIN",
    "property.sasl.username" = "user",
    "property.sasl.password" = "pass"
);

-- 查看例行导入任务
SHOW ROUTINE LOAD;

-- 暂停/恢复/停止
PAUSE ROUTINE LOAD FOR kafka_load;
RESUME ROUTINE LOAD FOR kafka_load;
STOP ROUTINE LOAD FOR kafka_load;
```

---

## 查询优化

### 执行计划分析

```sql
-- 查看执行计划
EXPLAIN SELECT * FROM events WHERE dt = '2024-01-01';

-- 查看详细执行计划
EXPLAIN VERBOSE SELECT * FROM events WHERE dt = '2024-01-01';

-- 查看图形化执行计划
EXPLAIN GRAPH SELECT * FROM events WHERE dt = '2024-01-01';
```

### 查询优化技巧

```sql
-- 1. 分区裁剪 - 必须带分区条件
-- ✅ 好：带分区条件
SELECT * FROM events 
WHERE dt = '2024-01-01' AND event_time >= '2024-01-01 10:00:00';

-- ❌ 差：不带分区条件会全表扫描
SELECT * FROM events WHERE event_time >= '2024-01-01 10:00:00';

-- 2. 分桶裁剪 - 使用分桶列作为 JOIN/过滤条件
-- ✅ 好：user_id 是分桶列
SELECT * FROM events WHERE user_id = 12345;

-- 3. 物化视图自动匹配
-- 创建物化视图后，查询会自动匹配
CREATE MATERIALIZED VIEW mv_event_stats AS
SELECT dt, event_type, COUNT(*) as cnt
FROM events GROUP BY dt, event_type;

-- 查询会自动使用物化视图
SELECT dt, event_type, COUNT(*) 
FROM events 
GROUP BY dt, event_type;

-- 4. 使用索引（Inverted Index）
-- 创建索引
CREATE INDEX idx_event_type ON events(event_type) USING INVERTED;

-- 查询会使用索引
SELECT * FROM events WHERE event_type = 'click';

-- 5. 避免 SELECT *
-- ✅ 好：只查询需要的列
SELECT user_id, event_time FROM events WHERE dt = '2024-01-01';

-- ❌ 差：查询所有列
SELECT * FROM events WHERE dt = '2024-01-01';

-- 6. JOIN 优化
-- ✅ 好：小表 join 大表
SELECT /*+ BROADCAST(d) */ *
FROM events e
JOIN dim_users d ON e.user_id = d.user_id;

-- 7. 使用 Colocate Join
-- 创建表时指定 Colocate Group
CREATE TABLE orders (...)
DISTRIBUTED BY HASH(user_id) BUCKETS 16
PROPERTIES ("colocate_with" = "user_group");

CREATE TABLE payments (...)
DISTRIBUTED BY HASH(user_id) BUCKETS 16
PROPERTIES ("colocate_with" = "user_group");
-- 这样 orders 和 payments 的 JOIN 会在本地执行，无需 Shuffle
```

---

## 性能调优

### 系统参数优化

```sql
-- 会话级别参数设置
SET query_timeout = 600;
SET enable_pipeline_engine = true;
SET runtime_filter_mode = "GLOBAL";
SET enable_cost_based_join_reorder = true;

-- 查看当前会话参数
SHOW VARIABLES;
```

### 常用性能参数

| 参数 | 默认值 | 建议值 | 说明 |
|------|--------|--------|------|
| query_timeout | 300 | 600 | 查询超时时间(秒) |
| enable_pipeline_engine | true | true | 启用 Pipeline 引擎 |
| runtime_filter_mode | OFF | GLOBAL | 运行时过滤 |
| runtime_filter_wait_time_ms | 1000 | 2000 | 运行时过滤等待时间 |
| enable_cost_based_join_reorder | true | true | CBO Join 重排 |
| parallel_fragment_exec_instance_num | 1 | 4 | 并行度 |
| join_batch_size | 32768 | 131072 | Join 批次大小 |
| enable_local_exchange | true | true | 启用 Local Exchange |

---

## 生产最佳实践

### 开发规范

1. **命名规范**
   ```sql
   -- 数据库：小写 + 下划线
   CREATE DATABASE user_behavior;
   
   -- 表：模块_表名
   CREATE TABLE ub_events (...);
   
   -- 列：小写 + 下划线
   user_id, event_time, create_time
   ```

2. **必须添加注释**
   ```sql
   CREATE TABLE orders (
       order_id BIGINT COMMENT '订单ID',
       user_id BIGINT COMMENT '用户ID',
       amount DECIMAL(10,2) COMMENT '订单金额(元)'
   )
   COMMENT '订单主表';
   ```

3. **时间字段规范**
   ```sql
   -- 必须包含分区字段 dt
   dt DATE COMMENT '分区日期',
   create_time DATETIME COMMENT '创建时间',
   update_time DATETIME COMMENT '更新时间'
   ```

### 监控查询

```sql
-- 查看慢查询
SHOW QUERY STATS ORDER BY QueryTime DESC LIMIT 20;

-- 查看正在执行的查询
SHOW PROCESSLIST;

-- 杀查询
KILL QUERY <query_id>;

-- 查看表统计
ANALYZE TABLE events;
SHOW TABLE STATS events;
SHOW COLUMN STATS events;

-- 查看数据分布
SELECT 
    dt,
    COUNT(*) as row_count,
    COUNT(DISTINCT user_id) as user_count
FROM events
GROUP BY dt
ORDER BY dt DESC;
```

### 备份策略

```sql
-- 导出表结构
SHOW CREATE TABLE events;

-- 导出数据（通过 EXPORT）
EXPORT TABLE events TO "s3://bucket/backup/events/"
PROPERTIES (
    "column_separator" = ",",
    "line_delimiter" = "\n"
);

-- 查看导出任务
SHOW EXPORT;
```

---

## 常见问题解决

### 问题 1: 导入速度慢

**诊断**：
```sql
-- 查看 BE 负载
SHOW PROC '/backends';

-- 查看导入任务状态
SHOW LOAD ORDER BY CreateTime DESC LIMIT 10;
```

**解决**：
- 增加 BE 数量
- 调整 `load_parallelism` 参数
- 使用批量导入代替单条插入

### 问题 2: 查询超时

**诊断**：
```sql
-- 查看执行计划
EXPLAIN SELECT ...;

-- 查看慢查询日志
tail -f fe/log/fe.audit.log | grep QueryTime
```

**解决**：
- 增加 `query_timeout`
- 优化 SQL（分区裁剪、索引）
- 增加物化视图

### 问题 3: 数据倾斜

**诊断**：
```sql
-- 检查分桶分布
SELECT 
    user_id % 16 as bucket,
    COUNT(*) as cnt
FROM events
GROUP BY bucket
ORDER BY cnt DESC;
```

**解决**：
- 更换分桶列（选择高基数列）
- 使用 `DISTRIBUTED BY RANDOM`

---

## 学习资源

- [Doris 官方文档](https://doris.apache.org/docs/)
- [Doris SQL 手册](https://doris.apache.org/docs/sql-manual/)
- [Doris 最佳实践](https://doris.apache.org/docs/get-started/best-practice/)
