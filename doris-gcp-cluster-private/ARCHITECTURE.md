# Doris + FoundationDB 存算分离架构详解

## 整体架构

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              GCP Project                                     │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │                         VPC Network                                   │  │
│  │                        (10.x.0.0/16)                                 │  │
│  │                                                                       │  │
│  │  ┌────────────────────────────────────────────────────────────────┐  │  │
│  │  │                    Load Balancer Layer                          │  │  │
│  │  │  ┌──────────────────────────────────────────────────────────┐  │  │  │
│  │  │  │        Doris Internal Load Balancer (MySQL: 9030)        │  │  │  │
│  │  │  │                    VIP: 10.x.x.10                        │  │  │  │
│  │  │  └──────────────────────────────────────────────────────────┘  │  │  │
│  │  └────────────────────────────────────────────────────────────────┘  │  │
│  │                                                                       │  │
│  │  ┌────────────────────────────────────────────────────────────────┐  │  │
│  │  │                 FE Layer (High Availability)                    │  │  │
│  │  │                                                                  │  │  │
│  │  │   ┌─────────────┐    ┌─────────────┐    ┌─────────────┐       │  │  │
│  │  │   │    FE-1     │    │    FE-2     │    │    FE-3     │       │  │  │
│  │  │   │   (Active)  │◄──►│   (Active)  │◄──►│   (Active)  │       │  │  │
│  │  │   │             │    │             │    │             │       │  │  │
│  │  │   │  Stateless  │    │  Stateless  │    │  Stateless  │       │  │  │
│  │  │   │  (No Data)  │    │  (No Data)  │    │  (No Data)  │       │  │  │
│  │  │   └──────┬──────┘    └──────┬──────┘    └──────┬──────┘       │  │  │
│  │  │          │                  │                  │               │  │  │
│  │  │          └──────────────────┼──────────────────┘               │  │  │
│  │  │                             │                                  │  │  │
│  │  │                             ▼                                  │  │  │
│  │  │   ┌─────────────────────────────────────────────────────────┐ │  │  │
│  │  │   │              FoundationDB Cluster                        │ │  │  │
│  │  │   │         (Distributed Metadata Store)                     │ │  │  │
│  │  │   │                                                          │ │  │  │
│  │  │   │   ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌────────┐ │ │  │  │
│  │  │   │   │ FDB-1   │◄─►│ FDB-2   │◄─►│ FDB-3   │◄─►│ FDB-N  │ │ │  │  │
│  │  │   │   │(Coord+  │   │(Coord+  │   │(Storage)│   │(Storage│ │ │  │  │
│  │  │   │   │ Storage)│   │ Storage)│   │         │   │)       │ │ │  │  │
│  │  │   │   └────┬────┘   └────┬────┘   └────┬────┘   └───┬────┘ │ │  │  │
│  │  │   │        └─────────────┴─────────────┴─────────────┘      │ │  │  │
│  │  │   │                          │                              │ │  │  │
│  │  │   │   ┌──────────────────────┴──────────────────────┐       │ │  │  │
│  │  │   │   │  Features:                                   │       │ │  │  │
│  │  │   │   │  - ACID Transactions                         │       │ │  │  │
│  │  │   │   │  - Strong Consistency                        │       │ │  │  │
│  │  │   │   │  - Auto Failover (RPO=0, RTO<5s)            │       │ │  │  │
│  │  │   │   │  - Horizontal Scaling                        │       │ │  │  │
│  │  │   │   │  - Data Replication (3x by default)          │       │ │  │  │
│  │  │   │   └──────────────────────────────────────────────┘       │ │  │  │
│  │  │   └─────────────────────────────────────────────────────────┘ │  │  │
│  │  └────────────────────────────────────────────────────────────────┘  │  │
│  │                                                                       │  │
│  │  ┌────────────────────────────────────────────────────────────────┐  │  │
│  │  │                 BE Layer (Compute + Hot Storage)                │  │  │
│  │  │                                                                  │  │  │
│  │  │   ┌─────────────┐    ┌─────────────┐    ┌─────────────┐       │  │  │
│  │  │   │    BE-1     │    │    BE-2     │    │    BE-N     │       │  │  │
│  │  │   │  (Compute)  │    │  (Compute)  │    │  (Compute)  │       │  │  │
│  │  │   │             │    │             │    │             │       │  │  │
│  │  │   │ ┌─────────┐ │    │ ┌─────────┐ │    │ ┌─────────┐ │       │  │  │
│  │  │   │ │ SSD Disk│ │    │ │ SSD Disk│ │    │ │ SSD Disk│ │       │  │  │
│  │  │   │ │(Hot    │ │    │ │(Hot    │ │    │ │(Hot    │ │       │  │  │
│  │  │   │ │ Data)  │ │    │ │ Data)  │ │    │ │ Data)  │ │       │  │  │
│  │  │   │ └─────────┘ │    │ └─────────┘ │    │ └─────────┘ │       │  │  │
│  │  │   └──────┬──────┘    └──────┬──────┘    └──────┬──────┘       │  │  │
│  │  │          │                  │                  │               │  │  │
│  │  │          └──────────────────┼──────────────────┘               │  │  │
│  │  │                             │                                  │  │  │
│  │  │                             ▼                                  │  │  │
│  │  │   ┌─────────────────────────────────────────────────────────┐ │  │  │
│  │  │   │          Instance Group Manager (Auto Scaling)           │ │  │  │
│  │  │   │                                                          │ │  │  │
│  │  │   │   - Min Instances: 2-5 (env dependent)                   │ │  │  │
│  │  │   │   - Max Instances: 5-20 (env dependent)                  │ │  │  │
│  │  │   │   - Scale Trigger: CPU > 70%                             │ │  │  │
│  │  │   │   - Health Check: TCP 9050                               │ │  │  │
│  │  │   │   - Auto Healing: Replace unhealthy instances            │ │  │  │
│  │  │   └─────────────────────────────────────────────────────────┘ │  │  │
│  │  └────────────────────────────────────────────────────────────────┘  │  │
│  │                                                                       │  │
│  │  ┌────────────────────────────────────────────────────────────────┐  │  │
│  │  │                    Cold Storage Layer                           │  │  │
│  │  │                                                                  │  │  │
│  │  │   ┌─────────────────────────────────────────────────────────┐  │  │  │
│  │  │   │              GCS Bucket (Object Storage)                 │  │  │  │
│  │  │   │                                                          │  │  │  │
│  │  │   │   Bucket: doris-{env}-separation-storage                 │  │  │  │
│  │  │   │   Location: us-central1 / us-east1                       │  │  │  │
│  │  │   │   Storage Class: Standard / Nearline / Coldline          │  │  │  │
│  │  │   │                                                          │  │  │  │
│  │  │   │   Lifecycle Policy:                                      │  │  │  │
│  │  │   │   - Auto-delete after retention period                   │  │  │  │
│  │  │   │   - Versioning: Disabled                                 │  │  │  │
│  │  │   │   - Encryption: Google-managed                           │  │  │  │
│  │  │   │                                                          │  │  │  │
│  │  │   │   Data Path: gs://bucket/doris-data/                     │  │  │  │
│  │  │   │                                                          │  │  │  │
│  │  │   │   Access Methods:                                        │  │  │  │
│  │  │   │   - gcsfuse (mounted as local filesystem)               │  │  │  │
│  │  │   │   - GCS API (direct access)                             │  │  │  │
│  │  │   └─────────────────────────────────────────────────────────┘  │  │  │
│  │  └────────────────────────────────────────────────────────────────┘  │  │
│  │                                                                       │  │
│  │  ┌────────────────────────────────────────────────────────────────┐  │  │
│  │  │                    Data Flow                                    │  │  │
│  │  │                                                                  │  │  │
│  │  │   Write Path:                                                   │  │  │
│  │  │   Client → LB → FE → FDB (metadata) + BE (data) → SSD         │  │  │
│  │  │                                                                  │  │  │
│  │  │   Read Path (Hot):                                              │  │  │
│  │  │   Client → LB → FE → FDB (metadata) → BE → SSD                │  │  │
│  │  │                                                                  │  │  │
│  │  │   Read Path (Cold):                                             │  │  │
│  │  │   Client → LB → FE → FDB (metadata) → BE → GCS                │  │  │
│  │  │                                                                  │  │  │
│  │  │   Data Tiering:                                                 │  │  │
│  │  │   SSD (Hot) ──[7 days no access]──► GCS (Cold)                │  │  │
│  │  │                                                                  │  │  │
│  │  └────────────────────────────────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 组件详解

### 1. FoundationDB (元数据存储)

**角色**: 替代 BDBJE，为 Doris FE 提供分布式元数据存储

**核心特性**:
- **分布式**: 多节点组成集群，数据自动分片
- **强一致性**: 严格的 ACID 事务保证
- **高可用**: 自动故障检测和恢复
- **水平扩展**: 可通过增加节点扩展容量和性能

**部署架构**:
```
┌─────────────────────────────────────────┐
│         FoundationDB Cluster            │
│                                         │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐ │
│  │  FDB-1  │  │  FDB-2  │  │  FDB-3  │ │
│  │ (Coord) │  │ (Coord) │  │(Storage)│ │
│  │+Storage │  │+Storage │  │         │ │
│  └────┬────┘  └────┬────┘  └────┬────┘ │
│       └─────────────┴─────────────┘     │
│                 │                       │
│                 ▼                       │
│  ┌─────────────────────────────────┐   │
│  │      Distributed Transaction    │   │
│  │         Layer (ACID)            │   │
│  └─────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

**数据复制**:
- 默认 3 副本
- 使用 Paxos 协议保证一致性
- 自动故障转移

### 2. Doris FE (无状态)

**角色**: SQL 解析、查询优化、元数据访问

**特性**:
- **无状态**: 不存储任何数据，所有状态在 FDB
- **可替换**: 任意 FE 节点故障可随时替换
- **水平扩展**: 多个 FE 可同时处理查询
- **负载均衡**: 通过 Internal LB 分发请求

**配置要点**:
```properties
# 使用 FoundationDB 作为元数据存储
meta_store_type = foundationdb
fdb_cluster_file_path = /etc/foundationdb/fdb.cluster
```

### 3. Doris BE (计算 + 热存储)

**角色**: 数据存储、查询执行

**存储分层**:
```
┌─────────────────────────────────────────┐
│              BE Node                     │
│                                         │
│  ┌─────────────────────────────────┐   │
│  │     Compute Layer               │   │
│  │  - Query Execution              │   │
│  │  - Data Processing              │   │
│  └─────────────────────────────────┘   │
│                   │                     │
│                   ▼                     │
│  ┌─────────────────────────────────┐   │
│  │     Hot Storage (SSD)           │   │
│  │  - Recent Data                  │   │
│  │  - Frequently Accessed          │   │
│  │  - High Performance             │   │
│  └─────────────────────────────────┘   │
│                   │                     │
│                   ▼                     │
│  ┌─────────────────────────────────┐   │
│  │     Cold Storage (GCS)          │   │
│  │  - Historical Data              │   │
│  │  - Infrequently Accessed        │   │
│  │  - Cost Effective               │   │
│  └─────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

### 4. GCS (冷存储)

**角色**: 低成本存储不常访问的数据

**优势**:
- 成本比 SSD 低 80%
- 自动数据分层
- 透明访问

## 高可用设计

### FE 高可用

```
Before (BDBJE):              After (FoundationDB):
┌─────────┐                  ┌─────────┐ ┌─────────┐
│  FE-1   │                  │  FE-1   │ │  FE-2   │
│(Master) │───故障──► 不可用  │(Active) │ │(Active) │
│ 单点    │                  │         │ │         │
└─────────┘                  └────┬────┘ └────┬────┘
                                  └─────┬─────┘
                                        │
                                        ▼
                               ┌─────────────────┐
                               │  FoundationDB   │
                               │  (Always HA)    │
                               └─────────────────┘
```

**故障场景**:
1. **FE 节点故障**: LB 自动将流量切换到其他 FE 节点
2. **FDB 节点故障**: 自动选举新 Coordinator，服务不中断
3. **BE 节点故障**: IGM 自动创建新实例，数据从 GCS 恢复

### 数据持久化

| 组件 | 数据位置 | 持久化策略 |
|------|----------|-----------|
| FE | FDB 集群 | 3 副本，自动故障转移 |
| BE 热数据 | SSD 磁盘 | 独立磁盘，销毁保留 |
| BE 冷数据 | GCS | 对象存储，永久保留 |

## 性能优化

### 1. FoundationDB 优化

```bash
# FDB 配置
[fdbserver]
memory = 8GiB              # 根据实例内存调整
storage_memory = 4GiB      # 存储引擎内存
knob_min_available_space_ratio = 0.01
```

### 2. 存储分层策略

```sql
-- 创建表时指定存储策略
CREATE TABLE events (
    event_time DATETIME,
    user_id INT,
    data STRING
)
PARTITION BY RANGE(event_time) (
    PARTITION p_current VALUES LESS THAN ('2024-02-01'),
    PARTITION p_history VALUES LESS THAN ('2024-01-01')
)
PROPERTIES (
    "storage_policy" = "hot_to_cold",
    "storage_cooldown_time" = "7 day",
    "hot_partition_num" = "3"
);
```

### 3. 查询优化

```sql
-- 查看数据分布
SHOW DATA SKEW FROM events;

-- 查看存储策略
SHOW STORAGE POLICY;

-- 分析查询计划
EXPLAIN SELECT * FROM events WHERE event_time > '2024-01-01';
```

## 成本分析

### 存储成本对比

| 方案 | 1TB/月成本 | 备注 |
|------|-----------|------|
| 全 SSD | $170 | 高性能，高成本 |
| 全 HDD | $40 | 低性能，低成本 |
| **存算分离 (20%热+80%冷)** | **$50** | **最佳性价比** |

### 计算成本

| 组件 | 实例类型 | 数量 | 月成本 |
|------|----------|------|--------|
| FE | e2-standard-2 | 2 | ~$100 |
| FDB | e2-standard-2 | 3 | ~$150 |
| BE | e2-standard-4 | 3-8 | ~$300-800 |

### 总成本估算 (PROD)

- 存储: $50/TB
- 计算: ~$1000/月
- 网络: ~$100/月
- **总计: ~$1150/月 (10TB 数据)**

## 部署架构对比

### 传统 Doris vs 存算分离 + FDB

| 特性 | 传统 Doris | 存算分离 + FDB |
|------|-----------|---------------|
| FE 高可用 | 需要手动切换 | 自动故障转移 |
| 元数据一致性 | 最终一致 | 强一致 (ACID) |
| 扩展性 | 垂直扩展 | 水平扩展 |
| 存储成本 | 高 (全 SSD) | 低 (分层存储) |
| 运维复杂度 | 中 | 低 (自动化) |
| 数据持久化 | 需要备份 | 自动多副本 |

## 最佳实践

### 1. 表设计

```sql
-- 按时间分区，便于分层
CREATE TABLE user_events (
    event_id BIGINT,
    user_id INT,
    event_type VARCHAR(50),
    event_data STRING,
    created_at DATETIME
)
DUPLICATE KEY(event_id)
PARTITION BY RANGE(created_at) (
    PARTITION p202401 VALUES [('2024-01-01'), ('2024-02-01')),
    PARTITION p202402 VALUES [('2024-02-01'), ('2024-03-01')),
    PARTITION p202403 VALUES [('2024-03-01'), ('2024-04-01'))
)
DISTRIBUTED BY HASH(user_id) BUCKETS 16
PROPERTIES (
    "storage_policy" = "hot_to_cold",
    "storage_cooldown_time" = "7 day",
    "hot_partition_num" = "2"
);
```

### 2. 监控指标

```bash
# FoundationDB 健康检查
fdbcli --exec "status"

# Doris 集群状态
mysql -h <LB_IP> -P 9030 -u root -e "SHOW FRONTENDS;"
mysql -h <LB_IP> -P 9030 -u root -e "SHOW BACKENDS;"

# 存储使用情况
mysql -h <LB_IP> -P 9030 -u root -e "SHOW DATA SKEW;"
```

### 3. 故障恢复

```bash
# FE 节点故障
# 1. 自动: LB 将流量切换到其他 FE
# 2. 手动: 创建新 FE 实例
terraform apply -var 'fe_count=2' -var-file=terraform.tfvars.prod

# FDB 节点故障
# 自动恢复，无需干预

# BE 节点故障
# 自动: IGM 创建新实例
# 数据自动从 GCS 恢复
```

## 总结

本架构提供了：

✅ **FE 高可用**: FoundationDB 提供强一致、高可用的元数据存储
✅ **存算分离**: SSD 热存储 + GCS 冷存储，成本优化 70%
✅ **自动扩缩容**: BE 节点根据负载自动扩展
✅ **数据持久化**: 多层级数据保护，集群销毁不丢失数据
✅ **云原生**: 完全基于 GCP 托管服务，运维简单

适用于生产环境的企业级 Doris 部署方案。
