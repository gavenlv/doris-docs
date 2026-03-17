# Doris 极端性能导入方案 - 50亿行/10分钟

## 目标分析

```
数据规模: 50亿行 × 90列
估算大小: 
  - 原始数据: ~2.5TB (按每行500字节)
  - Parquet+Zstd: ~500GB (压缩率80%)
  
目标时间: 10分钟 = 600秒
所需吞吐: 500GB / 600s = 850MB/s

网络要求: 850MB/s × 8 = 6.8Gbps (持续)
```

---

## 核心策略: 水平扩展 + 极致并行

### 架构设计

```
┌─────────────────────────────────────────────────────────────┐
│                    GCS Bucket (Same Region)                  │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐           │
│  │ 50 Files    │ │ 50 Files    │ │ 50 Files    │  × 4      │
│  │ 10GB each   │ │ 10GB each   │ │ 10GB each   │           │
│  └─────────────┘ └─────────────┘ └─────────────┘           │
└─────────────────────────────────────────────────────────────┘
                              │
                    200 Parallel Connections
                              │
┌─────────────────────────────────────────────────────────────┐
│                   Doris Cluster (GKE)                        │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐           │
│  │  BE-1   │ │  BE-2   │ │  BE-3   │ │  BE-4   │  ... × 16 │
│  │ 32 Core │ │ 32 Core │ │ 32 Core │ │ 32 Core │           │
│  │ 128GB   │ │ 128GB   │ │ 128GB   │ │ 128GB   │           │
│  └─────────┘ └─────────┘ └─────────┘ └─────────┘           │
│                                                              │
│  Total: 16 BE × 32 Core = 512 Cores                         │
│         16 BE × 128GB = 2TB RAM                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 方案 1: 超大规模集群方案 (推荐)

### 1.1 集群规模

| 组件 | 配置 | 数量 | 说明 |
|------|------|------|------|
| FE | 16 Core / 64GB | 3 | 高可用部署 |
| BE | 32 Core / 128GB / 2TB SSD | 16 | 计算主力 |
| Broker | 8 Core / 32GB | 4 | GCS 连接专用 |

### 1.2 数据准备

```python
# Python: 将数据分成 200 个文件，并行预处理
import pandas as pd
import pyarrow.parquet as pq
import multiprocessing as mp
from concurrent.futures import ProcessPoolExecutor

def process_batch(batch_id, input_files):
    """处理一个批次的数据"""
    # 读取多个 CSV 文件
    df = pd.concat([pd.read_csv(f) for f in input_files])
    
    # 写入 Parquet with Zstd 压缩（比 Snappy 压缩率更高）
    output_path = f'gs://bucket/partitions/batch_{batch_id:04d}.parquet'
    df.to_parquet(
        output_path,
        compression='zstd',       # 比 Snappy 压缩率高 20%
        compression_level=3,      # 平衡速度和压缩率
        row_group_size=100000,    # 每个 row group 10万行
        engine='pyarrow'
    )
    return output_path

# 并行处理 - 使用 32 进程
with ProcessPoolExecutor(max_workers=32) as executor:
    futures = []
    for i in range(200):
        batch_files = get_files_for_batch(i)  # 每批 2500万行
        futures.append(executor.submit(process_batch, i, batch_files))
    
    results = [f.result() for f in futures]
```

### 1.3 表设计优化

```sql
-- 极致分区策略
CREATE TABLE extreme_load_table (
    batch_id BIGINT,           -- 用于分桶
    row_id BIGINT,             -- 行ID
    -- 90列数据...
    col1 VARCHAR(100),
    col2 INT,
    -- ...
    col90 DOUBLE
)
DUPLICATE KEY(batch_id, row_id)
-- 分桶数 = BE数量 × 4 = 64
DISTRIBUTED BY HASH(batch_id) BUCKETS 64
PROPERTIES (
    "replication_num" = "3",
    "storage_format" = "V2",
    "enable_unique_key_merge_on_write" = "true",
    "light_schema_change" = "true",
    "disable_auto_compaction" = "false"
);
```

### 1.4 并行导入脚本

```python
#!/usr/bin/env python3
"""
Doris 极端并行导入脚本
50亿行数据 10分钟导入
"""

import concurrent.futures
import pymysql
import time
import json

class ExtremeLoader:
    def __init__(self, fe_host, db_name, table_name):
        self.fe_host = fe_host
        self.db_name = db_name
        self.table_name = table_name
        self.conn = pymysql.connect(
            host=fe_host,
            port=9030,
            user='root',
            password='',
            database=db_name,
            charset='utf8mb4'
        )
        
    def submit_load_job(self, batch_id, file_pattern):
        """提交单个导入任务"""
        label = f"extreme_batch_{batch_id}_{int(time.time())}"
        
        sql = f"""
        LOAD LABEL {self.db_name}.{label} (
            DATA INFILE("{file_pattern}")
            INTO TABLE {self.table_name}
            FORMAT AS "parquet"
            (batch_id, row_id, col1, col2, ..., col90)
        )
        WITH BROKER 'gs' (
            "gs.endpoint" = "storage.googleapis.com",
            "gs.access.key" = "{GCS_ACCESS_KEY}",
            "gs.secret.key" = "{GCS_SECRET_KEY}",
            "gs.connection.maximum" = "50",
            "gs.connection.timeout" = "600000",
            "gs.max_connections_per_route" = "50"
        )
        PROPERTIES (
            "timeout" = "600",
            "max_filter_ratio" = "0.01",
            "strict_mode" = "false",
            "max_error_number" = "1000000"
        );
        """
        
        cursor = self.conn.cursor()
        cursor.execute(sql)
        return label
    
    def wait_for_completion(self, labels, timeout=600):
        """等待所有导入任务完成"""
        start_time = time.time()
        pending = set(labels)
        
        while pending and (time.time() - start_time) < timeout:
            for label in list(pending):
                cursor = self.conn.cursor()
                cursor.execute(f"SHOW LOAD WHERE LABEL = '{label}'")
                result = cursor.fetchone()
                
                if result:
                    state = result[2]  # State 列
                    if state == 'FINISHED':
                        pending.remove(label)
                        print(f"✓ {label} completed")
                    elif state == 'CANCELLED':
                        raise Exception(f"Load {label} failed: {result}")
            
            time.sleep(1)
            print(f"Progress: {len(labels) - len(pending)}/{len(labels)} "
                  f"Elapsed: {time.time() - start_time:.0f}s")
        
        return len(pending) == 0
    
    def run_extreme_load(self):
        """执行极端导入"""
        print("=" * 60)
        print("Starting Extreme Load: 5B rows in 10 minutes")
        print("=" * 60)
        
        start_time = time.time()
        labels = []
        
        # Phase 1: 提交 200 个并行导入任务
        print("\n[Phase 1] Submitting 200 parallel load jobs...")
        with concurrent.futures.ThreadPoolExecutor(max_workers=50) as executor:
            futures = []
            for i in range(200):
                file_pattern = f"gs://bucket/partitions/batch_{i:04d}.parquet"
                future = executor.submit(self.submit_load_job, i, file_pattern)
                futures.append(future)
            
            for future in concurrent.futures.as_completed(futures):
                labels.append(future.result())
        
        submit_time = time.time() - start_time
        print(f"All jobs submitted in {submit_time:.1f}s")
        
        # Phase 2: 等待完成
        print("\n[Phase 2] Waiting for all jobs to complete...")
        success = self.wait_for_completion(labels, timeout=600)
        
        total_time = time.time() - start_time
        print(f"\n{'=' * 60}")
        print(f"Total time: {total_time:.1f}s")
        print(f"Rows imported: 5,000,000,000")
        print(f"Throughput: {5000000000/total_time:,.0f} rows/s")
        print(f"{'=' * 60}")
        
        return success

if __name__ == '__main__':
    loader = ExtremeLoader('fe-host', 'db1', 'extreme_load_table')
    loader.run_extreme_load()
```

---

## 方案 2: 流式导入方案 (Stream Load 并行)

如果 Broker Load 无法满足，使用 Stream Load 直接从多个客户端并行推送：

```python
#!/usr/bin/env python3
"""
Stream Load 极端并行导入
"""

import requests
import concurrent.futures
import pandas as pd
import io
import time

class StreamLoadExtreme:
    def __init__(self, be_hosts):
        self.be_hosts = be_hosts  # 16 个 BE 的列表
        self.be_index = 0
        
    def get_be_host(self):
        """轮询选择 BE"""
        host = self.be_hosts[self.be_index % len(self.be_hosts)]
        self.be_index += 1
        return host
    
    def stream_load_batch(self, batch_data, label):
        """Stream Load 一批数据"""
        be_host = self.get_be_host()
        url = f"http://{be_host}:8040/api/db1/extreme_load_table/_stream_load"
        
        # 转换为 CSV
        csv_buffer = io.StringIO()
        batch_data.to_csv(csv_buffer, index=False, header=False)
        csv_data = csv_buffer.getvalue()
        
        headers = {
            'Content-Type': 'text/plain; charset=UTF-8',
            'label': label,
            'column_separator': ',',
            'columns': 'batch_id,row_id,col1,col2,...,col90',
            'max_filter_ratio': '0.01',
            'strict_mode': 'false'
        }
        
        response = requests.put(url, data=csv_data, headers=headers)
        return response.json()
    
    def run(self, data_generator):
        """执行导入"""
        start_time = time.time()
        total_rows = 0
        
        with concurrent.futures.ThreadPoolExecutor(max_workers=100) as executor:
            futures = []
            batch_id = 0
            
            for batch_df in data_generator:
                label = f"stream_{batch_id}_{int(time.time() * 1000)}"
                future = executor.submit(self.stream_load_batch, batch_df, label)
                futures.append(future)
                batch_id += 1
                total_rows += len(batch_df)
                
                # 每 100 个任务检查一次
                if batch_id % 100 == 0:
                    completed = sum(1 for f in futures if f.done())
                    print(f"Submitted: {batch_id}, Completed: {completed}, "
                          f"Rows: {total_rows}")
            
            # 等待所有任务
            results = [f.result() for f in futures]
        
        elapsed = time.time() - start_time
        print(f"Stream Load complete: {total_rows} rows in {elapsed:.1f}s")
        print(f"Throughput: {total_rows/elapsed:,.0f} rows/s")
        
        return results

# 使用
be_hosts = ['be1', 'be2', ..., 'be16']  # 16 个 BE
loader = StreamLoadExtreme(be_hosts)
loader.run(data_generator())
```

---

## 方案 3: 预处理 + 直接文件拷贝 (最快)

### 3.1 绕过网络，直接磁盘操作

```bash
#!/bin/bash
# extreme-load.sh
# 最快方案：GCS Fuse + 本地文件导入

# 1. 在 BE 节点挂载 GCS Bucket
# 每个 BE 挂载相同的 bucket
mkdir -p /mnt/gcs-data
gcsfuse --implicit-dirs --limit-ops-per-sec -1 \
    --limit-bytes-per-sec -1 \
    your-bucket /mnt/gcs-data

# 2. 使用 TVF (Table Value Function) 直接读取本地文件
# Doris 3.0+ 支持直接查询 Parquet 文件
```

```sql
-- 使用 TVF 直接查询并插入
INSERT INTO extreme_load_table
SELECT * FROM local(
    "file_path" = "/mnt/gcs-data/partitions/*.parquet",
    "format" = "parquet",
    "columns" = "batch_id,row_id,col1,col2,...,col90"
);
```

---

## 关键参数配置

### FE 配置 (fe.conf)

```properties
# 极端导入配置
max_broker_concurrency = 200
async_pending_load_task_pool_size = 200
async_loading_load_task_pool_size = 100
load_checker_interval_second = 1
default_load_parallelism = 64
max_running_txn_num_per_db = 200

# 内存和连接
http_backlog_num = 1024
max_connections = 4096

# 查询调度
enable_pipeline_load = true
pipeline_load_parallelism = 64
```

### BE 配置 (be.conf)

```properties
# 极端性能配置
load_parallelism = 64
send_batch_parallelism = 64
max_send_batch_parallelism_per_job = 64
min_bytes_per_broker_scanner = 536870912    # 512MB

# 网络最大连接
brpc_num_threads = 128
fragment_pool_thread_num_max = 512
fragment_pool_queue_size = 8192

# GCS 客户端极端配置
s3_client_max_connections = 200
s3_client_max_requests_per_host = 200
s3_client_request_timeout_ms = 600000
s3_client_connect_timeout_ms = 120000
s3_client_socket_timeout_ms = 600000

# 内存 - 128GB 机器
mem_limit = 85%
total_memory_limit = 108G

# 本地缓存 - 必须使用 SSD
file_cache_path = /ssd/file_cache
file_cache_max_size = 800G
file_cache_percent = 80
data_cache_path = /ssd/data_cache
data_cache_max_size = 400G

# 线程
priority_networks = 10.0.0.0/8
num_threads_per_core = 2
num_disks = 4
```

---

## 网络优化

### GKE 网络配置

```yaml
# k8s-be-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: doris-be
spec:
  replicas: 16
  template:
    spec:
      nodeSelector:
        cloud.google.com/gke-nodepool: high-network-pool  # 使用高网络带宽节点池
      containers:
      - name: doris-be
        resources:
          requests:
            memory: "128Gi"
            cpu: "32"
            ephemeral-storage: "2Ti"
          limits:
            memory: "128Gi"
            cpu: "32"
        env:
        - name: GCS_CONNECTOR_TIMEOUT
          value: "600000"
        - name: GCS_CONNECTOR_MAX_CONNECTIONS
          value: "200"
      # 使用 hostNetwork 减少网络跳转
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
```

### GCS Bucket 配置

```bash
# 确保 Bucket 与 GKE 集群在同一 Region
gsutil mb -l us-central1 gs://your-extreme-bucket

# 启用均匀访问
gsutil uniformbucketlevelaccess set on gs://your-extreme-bucket

# 调整每对象吞吐量限制（联系 GCP 支持提升）
```

---

## 监控命令

```sql
-- 实时查看导入进度
SHOW LOAD ORDER BY CreateTime DESC LIMIT 20;

-- 查看 BE 负载
SHOW PROC '/backends';

-- 查看表导入行数
SELECT COUNT(*) FROM extreme_load_table;

-- 查看当前导入任务数
SHOW PROC '/current_queries';

-- BE 日志查看瓶颈
tail -f be/log/be.INFO | grep -E "(Load|Scanner|Broker)"
```

---

## 预期结果

| 指标 | 目标值 | 说明 |
|------|--------|------|
| 导入时间 | ≤ 10 分钟 | 50亿行 |
| 网络吞吐 | 800MB/s+ | 持续 |
| 导入速度 | 800万行/秒 | 总计 |
| CPU 利用率 | 70-90% | 所有 BE |
| 内存使用 | < 80% | 避免 OOM |

---

## 风险与应对

| 风险 | 概率 | 应对方案 |
|------|------|---------|
| GCS 带宽不足 | 中 | 使用 Regional Endpoint，申请配额提升 |
| BE OOM | 中 | 降低并行度，增加内存 |
| 网络抖动 | 低 | 增加超时时间，自动重试 |
| FE 成为瓶颈 | 低 | 增加 FE 数量，使用负载均衡 |

---

## 总结

要达到 50亿行/10分钟：

1. **集群规模**: 16+ BE，512+ 核心
2. **数据准备**: 200 个 Parquet 文件，Zstd 压缩
3. **并行度**: 200 并发导入任务
4. **网络**: 10Gbps+，GCS Regional
5. **存储**: 本地 SSD 缓存
6. **监控**: 实时跟踪，快速调整

**立即行动清单**:
- [ ] 扩容到 16 BE
- [ ] 应用上述配置
- [ ] 数据预处理为 200 个 Parquet
- [ ] 运行并行导入脚本
