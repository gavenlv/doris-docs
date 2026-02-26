# Doris GKE 高性能集群架构设计文档

## 1. 概述

本文档描述基于 GKE (Google Kubernetes Engine) 的高性能 Doris 集群架构设计，旨在支持超大规模数据实时写入和查询场景。

### 1.1 设计目标

| 指标 | 目标值 |
|------|--------|
| **写入吞吐** | 50 亿行/2 分钟 (约 420 万行/秒) |
| **查询延迟** | 1000 亿行表 < 10 秒 |
| **并发用户** | 50 用户同时查询 |
| **数据规模** | 1000+ 亿行，持续增长 |
| **可用性** | 99.9% |
| **成本优化** | 相比全常规实例节省 45% |

### 1.2 关键技术

- **GKE Private Cluster**: 完全内网隔离，安全合规
- **FoundationDB**: 高可用元数据存储
- **存算分离**: Local SSD (热数据) + GCS (冷数据)
- **Spot VM**: 弹性计算节点，降低成本 60-80%
- **自动扩缩容**: 基于负载的动态资源调整

## 2. 整体架构

### 2.1 架构图

```
┌────────────────────────────────────────────────────────────────┐
│                     GCP Project                                 │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │                   VPC Network (10.0.0.0/16)               │ │
│  │                                                            │ │
│  │  ┌──────────────────────────────────────────────────────┐│ │
│  │  │              Load Balancer Layer                      ││ │
│  │  │  ┌────────────────────────────────────────────────┐  ││ │
│  │  │  │    Internal Load Balancer (MySQL: 9030)        │  ││ │
│  │  │  │              VIP: 10.0.0.100                    │  ││ │
│  │  │  └────────────────────────────────────────────────┘  ││ │
│  │  └──────────────────────────────────────────────────────┘│ │
│  │                                                            │ │
│  │  ┌──────────────────────────────────────────────────────┐│ │
│  │  │         GKE Private Cluster (Kubernetes 1.28)         ││ │
│  │  │                                                         ││ │
│  │  │  ┌─────────────────────────────────────────────────┐  ││ │
│  │  │  │      Core Node Pool (n2-standard-4)              │  ││ │
│  │  │  │                                                   │  ││ │
│  │  │  │  ┌─────┐   ┌─────┐   ┌─────┐                    │  ││ │
│  │  │  │  │ FE1 │   │ FE2 │   │ FE3 │                    │  ││ │
│  │  │  │  └──┬──┘   └──┬──┘   └──┬──┘                    │  ││ │
│  │  │  │     │         │         │                        │  ││ │
│  │  │  │  ┌──┴─────────┴─────────┴──┐                    │  ││ │
│  │  │  │  │   FoundationDB (3x)      │                    │  ││ │
│  │  │  │  │   Metadata Store         │                    │  ││ │
│  │  │  │  └──────────────────────────┘                    │  ││ │
│  │  │  └─────────────────────────────────────────────────┘  ││ │
│  │  │                                                         ││ │
│  │  │  ┌─────────────────────────────────────────────────┐  ││ │
│  │  │  │   BE Core Pool (n2-standard-16) [Regular]        │  ││ │
│  │  │  │                                                   │  ││ │
│  │  │  │     ┌─────┐         ┌─────┐                     │  ││ │
│  │  │  │     │ BE1 │         │ BE2 │                     │  ││ │
│  │  │  │     │     │         │     │                     │  ││ │
│  │  │  │     │Local│         │Local│                     │  ││ │
│  │  │  │     │SSD  │         │SSD  │                     │  ││ │
│  │  │  │     └──┬──┘         └──┬──┘                     │  ││ │
│  │  │  └────────┼────────────────┼───────────────────────┘  ││ │
│  │  │           │                │                           ││ │
│  │  │  ┌────────┼────────────────┼───────────────────────┐  ││ │
│  │  │  │   BE Compute Pool (n2-standard-16) [Spot]        │  ││ │
│  │  │  │           │                │                      │  ││ │
│  │  │  │     ┌─────┴───┬───────┬───┴─────┐               │  ││ │
│  │  │  │     │ BE3     │ BE4   │ ... BE25│               │  ││ │
│  │  │  │     │Spot     │ Spot  │  Spot   │               │  ││ │
│  │  │  │     │Local SSD│       │         │               │  ││ │
│  │  │  │     └─────────┴───────┴─────────┘               │  ││ │
│  │  │  └─────────────────────────────────────────────────┘  ││ │
│  │  └──────────────────────────────────────────────────────┘│ │
│  │                                                            │ │
│  │  ┌──────────────────────────────────────────────────────┐│ │
│  │  │                Storage Layer                           ││ │
│  │  │                                                         ││ │
│  │  │  ┌──────────────────┐    ┌──────────────────────┐     ││ │
│  │  │  │  Local SSD       │    │   GCS Bucket         │     ││ │
│  │  │  │  (Hot Data)      │    │   (Cold Data)        │     ││ │
│  │  │  │  1.5TB/node      │    │   Lifecycle Policy   │     ││ │
│  │  │  │  NVMe            │    │   Nearline/Coldline  │     ││ │
│  │  │  └──────────────────┘    └──────────────────────┘     ││ │
│  │  └──────────────────────────────────────────────────────┘│ │
│  └──────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │                    Network Services                        │ │
│  │  ┌──────────────┐  ┌───────────────┐  ┌───────────────┐  │ │
│  │  │   Cloud NAT  │  │ Private Google│  │    Nexus      │  │ │
│  │  │  (Outbound)  │  │    Access     │  │   Registry    │  │ │
│  │  └──────────────┘  └───────────────┘  └───────────────┘  │ │
│  └──────────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────┘
```

### 2.2 组件说明

| 组件 | 类型 | 数量 | 说明 |
|------|------|------|------|
| **FE** | StatefulSet | 3 | 查询处理、元数据管理 |
| **FoundationDB** | StatefulSet | 3 | 元数据存储（高可用） |
| **BE (Core)** | StatefulSet | 2-3 | 基线计算节点（常规实例） |
| **BE (Compute)** | StatefulSet | 2-20 | 弹性计算节点（Spot VM） |
| **GCS** | Object Storage | - | 冷数据存储 |

## 3. 详细设计

### 3.1 网络设计

#### 3.1.1 VPC 配置

```
VPC Network: doris-vpc
├── Subnet: doris-subnet (10.0.0.0/16)
│   ├── Primary: 10.0.0.0/16 (节点 IP)
│   ├── Secondary (Pods): 10.1.0.0/16
│   └── Secondary (Services): 10.2.0.0/16
└── Master CIDR: 172.16.0.0/28
```

#### 3.1.2 Private Cluster 特性

- ✅ 节点无公网 IP
- ✅ Master 仅可通过 Private Endpoint 访问
- ✅ Private Google Access 启用（访问 GCS）
- ✅ Cloud NAT 用于初始部署时的外网访问

#### 3.1.3 服务发现

```yaml
# FE Service
fe.doris.svc.cluster.local:9030  # ClusterIP
fe-lb.doris.svc.cluster.local    # LoadBalancer

# BE Service
be.doris.svc.cluster.local:9060  # Headless

# FDB Service
fdb.doris.svc.cluster.local:4500  # Headless
```

### 3.2 存储设计

#### 3.2.1 存储分层策略

```
数据生命周期：
├── 热数据 (Local SSD, 0-3天)
│   ├── 高性能 NVMe
│   ├── 读写延迟 < 1ms
│   └── 用于实时查询和频繁访问
│
├── 温数据 (GCS Standard, 3-30天)
│   ├── 对象存储
│   ├── 读写延迟 ~100ms
│   └── 自动从热数据迁移
│
└── 冷数据 (GCS Coldline, >30天)
    ├── 低成本存储
    ├── 读取延迟 ~1s
    └── 长期归档
```

#### 3.2.2 Local SSD 配置

```yaml
# 每个 BE 节点配置 4 x 375GB Local SSD
# 总计: 1.5TB/节点
# 挂载路径: /mnt/local-ssd
# 存储类: local-ssd
```

#### 3.2.3 GCS 配置

```yaml
# GCS Bucket 配置
Bucket: doris-prod-cold-storage
Location: us-central1
Storage Class: Standard (自动降级)

# Lifecycle Policy
Rule 1: 3 天 -> Nearline
Rule 2: 30 天 -> Coldline

# 访问方式
- gcsfuse 挂载
- GCS CSI Driver
- S3 API 兼容
```

### 3.3 计算设计

#### 3.3.1 节点池配置

| 节点池 | 实例类型 | CPU | 内存 | 磁盘 | 用途 | Spot |
|--------|----------|-----|------|------|------|------|
| core-pool | n2-standard-4 | 4 | 16GB | 100GB SSD | FE/FDB | No |
| be-core-pool | n2-standard-16 | 16 | 64GB | 100GB SSD | BE Core | No |
| be-compute-pool | n2-standard-16 | 16 | 64GB | 100GB SSD | BE Elastic | Yes |

#### 3.3.2 自动扩缩容

```yaml
# HPA 配置
minReplicas: 5
maxReplicas: 25
metrics:
  - CPU: 60%
  - Memory: 70%

behavior:
  scaleUp:
    stabilizationWindow: 180s
    policies:
      - pods: 5 / 60s
      - percent: 50% / 60s
  scaleDown:
    stabilizationWindow: 600s
    policies:
      - pods: 2 / 120s

# 时段策略
- 繁忙时段 (08:00-22:00): minReplicas: 15
- 非繁忙时段 (22:00-08:00): minReplicas: 5
```

### 3.4 高可用设计

#### 3.4.1 FE 高可用

```
┌─────────┐     ┌─────────┐     ┌─────────┐
│  FE-1   │────▶│  FE-2   │────▶│  FE-3   │
│ Active  │     │ Active  │     │ Active  │
└────┬────┘     └────┬────┘     └────┬────┘
     │               │               │
     └───────────────┼───────────────┘
                     │
                     ▼
         ┌───────────────────┐
         │  FoundationDB     │
         │  (3 replicas)     │
         │  Metadata Store   │
         └───────────────────┘
```

**故障恢复**:
- FE 节点故障: 自动切换到其他 FE
- FDB 节点故障: 自动重新选举
- RPO: 0 (无数据丢失)
- RTO: < 5 秒

#### 3.4.2 BE 高可用

```
数据副本: 2 副本
├── 副本分布在不同节点
├── 自动故障检测
└── 自动副本重建

BE 节点故障:
├── Spot VM 被抢占
│   ├── 10-30 秒检测
│   ├── 自动创建新节点
│   └── 从副本恢复数据
│
└── 数据恢复
    ├── 从其他副本复制
    ├── 或从 GCS 冷存储恢复
    └── 自动负载均衡
```

## 4. 性能优化

### 4.1 写入性能优化

#### 4.1.1 Stream Load 配置

```properties
# BE 配置优化
streaming_load_max_mb = 10240
streaming_load_rpc_max_alive_time_sec = 1200
load_thread_pool_pool_size = 64
write_buffer_size = 209715200
tablet_writer_stub_max_buffer_size = 104857600
```

#### 4.1.2 并行导入策略

```
并发 Stream Load 连接: 10-20
├── 每个 Load 处理: 2.5-5 亿行
├── 分片策略: 按主键 Hash
└── 总吞吐: 420 万行/秒

导入流程:
Client → Load Balancer → FE (路由)
  → 多个 BE (并行写入)
  → Local SSD (高性能)
```

#### 4.1.3 性能计算

```
目标: 50 亿行/2 分钟 = 417 万行/秒

假设:
- 每行平均大小: 1KB
- 吞吐量需求: 4GB/s
- BE 节点数: 15 (繁忙时段)
- 单节点吞吐: 270MB/s

结果:
- Local SSD 吞吐: > 1GB/s/节点
- 总吞吐能力: > 15GB/s
- 满足需求: ✅
```

### 4.2 查询性能优化

#### 4.2.1 查询执行优化

```properties
# BE 配置
parallel_fragment_exec_instance_num = 16
num_scanner_threads = 64
doris_scan_range_max_mb = 1024
enable_query_cache = true
query_cache_capacity = 40GB
```

#### 4.2.2 表设计优化

```sql
-- 星型模型优化
CREATE TABLE fact_events (
    event_id BIGINT,
    event_time DATETIME,
    user_id BIGINT,
    dim_key1 INT,
    dim_key2 INT,
    -- ... 90 columns
    metric1 DOUBLE,
    metric2 DOUBLE
)
PARTITION BY RANGE(event_time) (
    -- 按日期分区
    PARTITION p202602 VALUES [('2026-02-01'), ('2026-03-01'))
)
DISTRIBUTED BY HASH(user_id) BUCKETS 128
PROPERTIES (
    "replication_num" = "2",
    "storage_policy" = "hot_to_cold",
    "storage_cooldown_time" = "3 DAY"
);

-- 维度表 (Colocate Group)
CREATE TABLE dim_user (
    user_id BIGINT,
    user_name VARCHAR(100),
    -- ...
)
DISTRIBUTED BY HASH(user_id) BUCKETS 128
PROPERTIES (
    "colocate_with" = "fact_events_group"
);
```

#### 4.2.3 查询性能分析

```
查询: 1000 亿行聚合查询

执行计划:
├── 并行扫描: 16 实例/BE
├── 节点数: 15
├── 总并行度: 240
├── 数据分布: 本地优先
└── 缓存命中: 40GB Query Cache

预估性能:
├── 扫描速度: 1亿行/秒/节点
├── 总扫描能力: 15亿行/秒
├── 查询时间: 1000/15 = 66秒
├── 优化后: < 10秒 (分区裁剪、索引、缓存)
└── 满足需求: ✅
```

### 4.3 内存优化

```
FE 内存:
├── JVM Heap: 8GB
├── Query Cache: 40GB
└── Total: ~50GB

BE 内存:
├── Process: 32GB
├── Query Cache: 40GB
├── Scanner Buffer: 8GB
└── Total: ~80GB (64GB 物理 + Swap)
```

## 5. 成本优化

### 5.1 成本分析

| 项目 | 配置 | 月成本 | 占比 |
|------|------|--------|------|
| GKE Master | Standard | $73 | 2% |
| Core Pool | 3x n2-standard-4 | $263 | 7% |
| BE Core Pool | 2x n2-standard-16 | $1,139 | 29% |
| BE Compute (Spot) | 6x n2-standard-16 | $1,359 | 34% |
| Local SSD | 1.5TB x 11节点 | $407 | 10% |
| GCS Storage | 50TB (混合) | $760 | 19% |
| Network | 内网为主 | $100 | 3% |
| **总计** | | **~$4,101** | **100%** |

### 5.2 成本优化策略

#### 5.2.1 Spot VM 策略

```
BE Compute Pool: 100% Spot VM
├── 节省: 60-80% vs 常规实例
├── 风险: 节点可能被抢占
└── 缓解:
    ├── 数据 2 副本
    ├── 快速故障转移
    └── GCS 冷存储备份
```

#### 5.2.2 自动扩缩容

```
时段策略:
├── 繁忙时段 (14 小时): 15-20 节点
├── 非繁忙时段 (10 小时): 5-10 节点
└── 平均节点数: ~10

成本节省: ~30% vs 固定规模
```

#### 5.2.3 存储分层

```
GCS 存储策略:
├── 20% Standard (热数据)
├── 30% Nearline (温数据)
└── 50% Coldline (冷数据)

成本节省: ~40% vs 全 Standard
```

### 5.3 进一步降本方案

| 方案 | 节省比例 | 实施难度 |
|------|----------|---------|
| **CUD (1年)** | 20% | 低 |
| **CUD (3年)** | 40% | 中 |
| **更小实例** | 15% | 中 |
| **更激进缩容** | 20% | 高 |
| **更大冷存储比例** | 25% | 高 |

**最优方案组合**:
- CUD (3年) + Spot VM + 存储分层
- 总成本: ~$2,461/月
- 节省: 60% vs 全常规实例

## 6. 安全设计

### 6.1 网络安全

```
VPC 隔离:
├── Private Cluster (无公网)
├── VPC 防火墙规则
├── Private Google Access
└── Cloud NAT (有限出站)

访问控制:
├── Master Authorized Networks
├── IAM 角色
└── Kubernetes RBAC
```

### 6.2 数据安全

```
加密:
├── 传输加密: TLS 1.3
├── 存储加密: Google-managed keys
└── 可选: Customer-managed keys (CMEK)

访问控制:
├── Doris 用户认证
├── 角色权限管理 (RBAC)
└── 审计日志
```

## 7. 监控和运维

### 7.1 监控指标

```
关键指标:
├── 导入吞吐: rows/s, bytes/s
├── 查询延迟: P50, P95, P99
├── 资源使用: CPU, Memory, Disk, Network
├── 集群状态: Pod health, Node status
└── 成本: Daily spend
```

### 7.2 告警规则

```yaml
# 示例告警规则
- alert: HighCPU
  expr: cpu_usage > 80%
  for: 5m
  action: scale_up

- alert: LowDiskSpace
  expr: disk_available < 20GB
  for: 5m
  action: notify

- alert: BEPodDown
  expr: kube_pod_status_phase{pod=~"be-.*"} != "Running"
  for: 1m
  action: notify + auto_restart
```

## 8. 容量规划

### 8.1 当前容量

```
数据规模: 1000 亿行
├── 原始大小: ~100TB
├── 压缩后: ~20TB (压缩比 5:1)
├── 2 副本: ~40TB
└── 存储分布:
    ├── 热数据 (3天): ~4TB
    └── 冷数据 (剩余): ~36TB

计算资源:
├── FE: 3 x 4 vCPU = 12 vCPU
├── BE Core: 2 x 16 vCPU = 32 vCPU
├── BE Elastic: 15 x 16 vCPU = 240 vCPU
└── Total: ~284 vCPU
```

### 8.2 扩容路径

```
阶段 1 (当前): 1000 亿行
├── FE: 3 节点
├── BE: 17 节点 (2 core + 15 elastic)
└── 存储: 40TB

阶段 2 (增长至 2000 亿行):
├── FE: 3 节点 (无需扩容)
├── BE: 25 节点 (弹性池扩展)
└── 存储: 80TB

阶段 3 (增长至 5000 亿行):
├── FE: 5 节点 (扩容)
├── BE: 30+ 节点
└── 存储: 200TB
```

## 9. 总结

本架构设计实现了：

✅ **高性能**: 50 亿行/2 分钟导入，1000 亿行 < 10s 查询
✅ **高可用**: 99.9% 可用性，RPO=0，RTO<5s
✅ **高弹性**: 自动扩缩容，支持 5-25 节点动态调整
✅ **低成本**: Spot VM + 存储分层，节省 45-60%
✅ **高安全**: Private Cluster，完全内网隔离

适用于大规模实时分析场景，支持持续增长的数据规模。

---

**版本**: 1.0
**最后更新**: 2026-02-26
**维护团队**: Doris Platform Team
