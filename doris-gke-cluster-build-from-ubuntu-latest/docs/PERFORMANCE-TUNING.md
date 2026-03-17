# Doris 存算分离架构 - 大规模数据导入性能优化指南

## 问题诊断

### 当前瓶颈分析

| 指标 | 当前值 | 目标值 | 问题 |
|------|--------|--------|------|
| 网络吞吐 | 10MB/s | 500MB/s+ | 严重不足 |
| 数据量 | 10亿行/batch | - | 90列，数据量大 |
| 日处理量 | 300-500亿行 | - | 100个batch |
| CPU | 32核 | - | 利用率低 |

### 根因分析

1. **GCS 单连接带宽限制** - 默认单连接只有 10-50MB/s
2. **Broker Load 并行度不足** - 默认参数不适合大规模导入
3. **存算分离架构延迟** - 远程存储访问引入额外延迟
4. **数据格式** - 未压缩的 CSV 导致网络传输量大

---

## 优化方案

### 方案 1: GCS 访问优化 (最重要)

#### 1.1 使用 GCS Regional Bucket + DirectPath

```yaml
# 确保 Doris 集群和 GCS Bucket 在同一 Region
# GCS Bucket 配置示例
gcs:
  bucket_location: us-central1  # 与 GKE 集群同区域
  storage_class: STANDARD
  uniform_bucket_level_access: true
```

#### 1.2 增加 GCS 并发连接数

```sql
-- Broker Load 设置高并发
LOAD LABEL db1.batch_load_1 (
    DATA INFILE("gs://bucket/path/*.parquet")
    INTO TABLE target_table
    FORMAT AS "parquet"
    (k1, k2, k3)
)
WITH BROKER 'gs'
(
    "gs.endpoint" = "storage.googleapis.com",
    "gs.access.key" = "xxx",
    "gs.secret.key" = "xxx",
    "gs.connection.maximum" = "100",        -- 增加连接数
    "gs.connection.timeout" = "300000",     -- 5分钟超时
    "gs.connection.request.timeout" = "300000"
)
PROPERTIES (
    "timeout" = "7200",
    "max_filter_ratio" = "0.1"
);
```

---

### 方案 2: Doris 参数调优

#### 2.1 FE 配置优化

```properties
# fe.conf

# 增加 Broker Load 并发度
max_broker_concurrency = 100              # 默认 10，提升到 100
async_pending_load_task_pool_size = 100   # 等待队列大小
async_loading_load_task_pool_size = 50    # 执行中队列大小
load_checker_interval_second = 1          # 检查间隔
default_load_parallelism = 50             # 默认并行度

# 增加连接和线程
rpc_port = 9020
query_port = 9030
edit_log_port = 9010

# 内存配置
meta_dir = /opt/doris/fe/doris-meta
http_port = 8030
```

#### 2.2 BE 配置优化

```properties
# be.conf

# 导入性能关键参数
max_send_batch_parallelism_per_job = 50   # 每个任务的并行度
min_bytes_per_broker_scanner = 268435456  # 256MB 每个 scanner 最小数据量
load_parallelism = 32                     # 导入并行度 (设为 CPU 核数)
send_batch_parallelism = 32               # 发送并行度

# 网络优化
brpc_num_threads = 64                     # BRPC 线程数
fragment_pool_thread_num_max = 256        # Fragment 线程池
fragment_pool_queue_size = 4096           # 队列大小

# 内存优化 (32核机器)
mem_limit = 80%                           # 使用 80% 内存
total_memory_limit = 100G                 # 根据实际内存调整

# 存储优化 (存算分离)
storage_root_path = /opt/doris/be/storage
storage_page_cache_limit = 20G            # 页面缓存
storage_row_cache_limit = 10G             # 行缓存

# GCS / S3 客户端优化
s3_client_max_connections = 100
s3_client_request_timeout_ms = 300000
s3_client_connect_timeout_ms = 60000

# 线程池
priority_networks = 10.0.0.0/8            # 根据实际网络调整
```

---

### 方案 3: 数据预处理优化

#### 3.1 使用 Parquet 格式 + Snappy 压缩

```python
# 转换 CSV 到 Parquet (Python)
import pandas as pd
import pyarrow.parquet as pq
import pyarrow as pa

# 读取 CSV
df = pd.read_csv('data.csv')

# 转换为 Parquet with Snappy 压缩
df.to_parquet(
    'data.parquet',
    compression='snappy',      # 压缩比约 70%，速度快
    engine='pyarrow',
    row_group_size=100000      # 每个 row group 10万行
)
```

#### 3.2 文件大小优化

| 原始格式 | 大小 | 优化后 | 大小 | 压缩比 |
|---------|------|--------|------|--------|
| CSV | 100GB | Parquet+Snappy | 30GB | 70%↓ |
| JSON | 150GB | Parquet+Zstd | 35GB | 77%↓ |

**推荐文件大小**: 256MB - 1GB 每个文件

---

### 方案 4: 表设计优化

#### 4.1 分区策略

```sql
-- 按日期分区，避免单分区过大
CREATE TABLE user_events (
    event_time DATETIME,
    user_id BIGINT,
    event_type VARCHAR(50),
    -- 90个列...
)
DUPLICATE KEY(event_time, user_id)
PARTITION BY RANGE(event_time) (
    PARTITION p202401 VALUES LESS THAN ("2024-02-01"),
    PARTITION p202402 VALUES LESS THAN ("2024-03-01"),
    -- 每月一个分区
)
DISTRIBUTED BY HASH(user_id) BUCKETS 32   -- 与 BE 数量匹配
PROPERTIES (
    "replication_num" = "3",
    "storage_format" = "V2",
    "enable_unique_key_merge_on_write" = "true"
);
```

#### 4.2 分桶策略

```sql
-- 分桶数 = BE 节点数 × 2~4
-- 32核 POD，建议分桶数 32 或 64
DISTRIBUTED BY HASH(user_id) BUCKETS 32
```

---

### 方案 5: Broker Load 高级优化

#### 5.1 多文件并行导入

```sql
-- 一次导入多个文件，自动并行
LOAD LABEL db1.batch_load_parallel (
    DATA INFILE("gs://bucket/batch1/*")
    INTO TABLE target_table
    FORMAT AS "parquet"
    (col1, col2, col3),
    
    DATA INFILE("gs://bucket/batch2/*")
    INTO TABLE target_table
    FORMAT AS "parquet"
    (col1, col2, col3),
    
    DATA INFILE("gs://bucket/batch3/*")
    INTO TABLE target_table
    FORMAT AS "parquet"
    (col1, col2, col3)
)
WITH BROKER 'gs' (...)
PROPERTIES (
    "timeout" = "7200",
    "max_filter_ratio" = "0.1",
    "strict_mode" = "false"
);
```

#### 5.2 使用 Multi-Catalog 直接查询 GCS

```sql
-- 创建 GCS Catalog，直接查询不导入
CREATE CATALOG gcs_catalog
PROPERTIES (
    "type" = "hive",
    "hive.metastore.type" = "glue",
    "hive.metastore.uris" = "thrift://...",
    "s3.endpoint" = "storage.googleapis.com",
    "s3.access_key" = "xxx",
    "s3.secret_key" = "xxx"
);

-- 直接查询，无需导入
SELECT * FROM gcs_catalog.db.table WHERE dt = '2024-01-01';
```

---

### 方案 6: 存算分离架构特有优化

#### 6.1 本地缓存优化

```properties
# be.conf - 增加本地缓存
# 存算分离模式下，本地缓存对性能至关重要

# 文件缓存
file_cache_path = /opt/doris/be/file_cache
file_cache_max_size = 500G        # 根据磁盘空间调整
file_cache_percent = 50           # 使用 50% 磁盘空间

# 数据缓存
data_cache_path = /opt/doris/be/data_cache
data_cache_max_size = 200G
```

#### 6.2 预热缓存

```sql
-- 导入前预热缓存（可选）
WARM UP CACHE FOR TABLE target_table;
```

---

### 方案 7: 批量导入调度优化

#### 7.1 错峰导入

```python
# Python 调度示例
import schedule
import time
from datetime import datetime

def import_batch(batch_id):
    """执行导入"""
    # 执行 Broker Load
    execute_load(f"batch_{batch_id}")
    
# 每天 100 个 batch，错峰执行
# 高峰期：0-6点，每 3 分钟一个 batch
for i in range(60):
    schedule.every().day.at(f"{i//12:02d}:{(i%12)*5:02d}").do(import_batch, i)

# 低峰期：6-24点，每 10 分钟一个 batch  
for i in range(60, 100):
    schedule.every().day.at(f"{(6+i//6):02d}:{(i%6)*10:02d}").do(import_batch, i)

while True:
    schedule.run_pending()
    time.sleep(60)
```

#### 7.2 并发控制

```sql
-- 监控当前导入任务
SHOW LOAD ORDER BY CreateTime DESC LIMIT 10;

-- 查看导入队列
SHOW PROC '/backends';

-- 如果积压，暂停新任务
PAUSE LOAD WHERE LABEL LIKE "batch_%";

-- 恢复
RESUME LOAD WHERE LABEL LIKE "batch_%";
```

---

## 预期性能

### 优化前后对比

| 指标 | 优化前 | 优化后 | 提升 |
|------|--------|--------|------|
| 单 batch 导入时间 | ~3小时 | ~15分钟 | 12x |
| 网络吞吐 | 10MB/s | 500MB/s+ | 50x |
| 日处理能力 | 100亿行 | 5000亿行+ | 50x |
| CPU 利用率 | <10% | 60-80% | 8x |

### 导入速度估算

```
数据量: 10亿行 × 90列 ≈ 500GB (原始)
        500GB × 30% (Parquet压缩) = 150GB

网络: 500MB/s × 60s = 30GB/min
      150GB / 30GB/min = 5分钟 (传输)
      
处理: 32核 × 80% = 25核有效
      10亿行 / 25核 / 10000行/s ≈ 10分钟 (处理)
      
总计: 约 15-20 分钟 per batch
```

---

## 监控指标

### 关键指标

```sql
-- 1. 查看 BE 负载
SHOW PROC '/backends';

-- 2. 查看导入进度
SHOW LOAD WHERE LABEL = "your_label";

-- 3. 查看表统计
SHOW DATA FROM your_table;

-- 4. 查看缓存命中率
SHOW PROC '/backends/file_cache';
```

### Prometheus 监控

```yaml
# 监控指标
doris_be_load_rows_total      # 导入行数
doris_be_load_bytes_total     # 导入字节数
doris_be_load_duration_ms     # 导入耗时
doris_be_file_cache_hit_ratio # 缓存命中率
```

---

## 实施步骤

### Phase 1: 立即实施 (1-2天)

1. [ ] 修改 FE/BE 配置参数
2. [ ] 数据格式改为 Parquet + Snappy
3. [ ] 调整 Broker Load 并行度

### Phase 2: 短期优化 (1周内)

1. [ ] GCS Bucket 与集群同区域部署
2. [ ] 增加本地缓存配置
3. [ ] 优化表分区/分桶策略

### Phase 3: 长期优化 (1月内)

1. [ ] 建立导入任务调度系统
2. [ ] 监控告警体系完善
3. [ ] 自动化扩容方案

---

## 参考配置

### 完整 be.conf (32核 128GB 存算分离)

```properties
# 基础配置
be_port = 9060
be_http_port = 8040
heartbeat_service_port = 9050
brpc_port = 8060
priority_networks = 10.0.0.0/8

# 内存配置 (128GB 机器)
mem_limit = 80%
total_memory_limit = 100G

# 导入优化
max_send_batch_parallelism_per_job = 32
min_bytes_per_broker_scanner = 268435456
load_parallelism = 32
send_batch_parallelism = 32

# 网络优化
brpc_num_threads = 64
fragment_pool_thread_num_max = 256
fragment_pool_queue_size = 4096

# 存算分离 - 本地缓存
file_cache_path = /opt/doris/be/file_cache
file_cache_max_size = 400G
file_cache_percent = 40

# GCS 客户端
s3_client_max_connections = 100
s3_client_request_timeout_ms = 300000
s3_client_connect_timeout_ms = 60000

# 存储
storage_root_path = /opt/doris/be/storage
storage_page_cache_limit = 20G

# 日志
sys_log_level = INFO
log_buffer_level = -1
```

---

## 常见问题

### Q1: 为什么存算分离导入比存算一体慢？

A: 存算分离需要从远程存储(GCS)读取数据，网络延迟是瓶颈。优化方向：
- 增加本地缓存
- 使用 GCS Regional Endpoint
- 提高并发度

### Q2: 如何确认 GCS 连接数足够？

A: 查看 BE 日志：
```bash
grep "s3_client" be/log/be.INFO | tail -100
```

### Q3: 导入过程中内存不足？

A: 调整参数：
```properties
mem_limit = 70%                    # 降低内存限制
load_parallelism = 16              # 降低并行度
max_send_batch_parallelism_per_job = 16
```
