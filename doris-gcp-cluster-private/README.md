# Doris GCP 存算分离 + FE 高可用集群部署 (内网版本)

## 概述

这是一个企业级的 **GCP 存算分离 Doris 集群** 部署方案（内网版本），实现了：

### 核心特性

- **计算与存储完全分离**: BE 节点只负责计算，数据存储在独立磁盘和 GCS
- **热数据**: SSD 本地磁盘 (高性能)
- **冷数据**: GCS 对象存储 (低成本)
- **自动数据分层**: 根据访问频率自动在热/冷存储间迁移
- **动态扩缩容**: BE 计算节点可根据负载自动扩展
- **数据持久化**: 集群销毁不丢失数据

### FE 高可用 (NEW)

- **FoundationDB 集群**: 作为 Doris FE 的分布式元数据存储
- **强一致性**: FoundationDB 提供 ACID 事务保证
- **自动故障转移**: FE 节点故障时自动切换
- **水平扩展**: 支持多个 FE 节点同时读写
- **数据不丢失**: FDB 数据持久化到多副本

### 网络模式

**本版本使用内网部署模式（无公网访问）：**
- VM **不能**直接访问互联网
- 所有安装包从内部 GCS Bucket 下载
- 需要先运行 `upload-artifacts.sh` 上传安装包
- 更高的安全性，适合生产环境

**如需公网版本，请使用 `doris-gcp-cluster-public` 目录。**

## 架构图

```
┌─────────────────────────────────────────────────────────────────┐
│                        GCP Project                              │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                   VPC Network                             │  │
│  │  (Subnet: 10.x.0.0/16)                                   │  │
│  │                                                           │  │
│  │  ┌────────────────────────────────────────────────────┐  │  │
│  │  │           Internal Load Balancer                   │  │  │
│  │  │  - VIP: 10.x.x.x                                   │  │  │
│  │  │  - Port: 9030 (MySQL)                              │  │  │
│  │  └────────────────────┬───────────────────────────────┘  │  │
│  │                       │                                   │  │
│  │  ┌────────────────────┴───────────────────────────────┐  │  │
│  │  │              FE Cluster (High Availability)        │  │  │
│  │  │  ┌─────────┐  ┌─────────┐  ┌─────────┐           │  │  │
│  │  │  │  FE-1   │  │  FE-2   │  │  FE-3   │ (PROD)    │  │  │
│  │  │  │ (Active)│  │ (Active)│  │ (Active)│           │  │  │
│  │  │  └────┬────┘  └────┬────┘  └────┬────┘           │  │  │
│  │  │       └─────────────┴─────────────┘                │  │  │
│  │  │                     │                              │  │  │
│  │  │                     ▼                              │  │  │
│  │  │  ┌────────────────────────────────────────────┐   │  │  │
│  │  │  │     FoundationDB Cluster (Metadata)        │   │  │  │
│  │  │  │  ┌─────────┐ ┌─────────┐ ┌─────────┐      │   │  │  │
│  │  │  │  │ FDB-1   │ │ FDB-2   │ │ FDB-3   │      │   │  │  │
│  │  │  │  │(Coordinator)        │ │(Storage)│      │   │  │  │
│  │  │  │  └─────────┘ └─────────┘ └─────────┘      │   │  │  │
│  │  │  │  - Distributed, Strongly Consistent        │   │  │  │
│  │  │  │  - ACID Transactions                       │   │  │  │
│  │  │  │  - Auto Failover                           │   │  │  │
│  │  │  └────────────────────────────────────────────┘   │  │  │
│  │  └───────────────────────────────────────────────────┘  │  │
│  │                                                          │  │
│  │  ┌───────────────────────────────────────────────────┐  │  │
│  │  │           BE Cluster (Compute Only)               │  │  │
│  │  │                                                   │  │  │
│  │  │  ┌─────────┐  ┌─────────┐  ┌─────────┐          │  │  │
│  │  │  │  BE-1   │  │  BE-2   │  │  BE-n   │          │  │  │
│  │  │  │(Compute)│  │(Compute)│  │(Compute)│          │  │  │
│  │  │  └────┬────┘  └────┬────┘  └────┬────┘          │  │  │
│  │  │       └─────────────┴─────────────┘               │  │  │
│  │  │                     │                             │  │  │
│  │  │  ┌──────────────────┴──────────────────┐         │  │  │
│  │  │  │     Instance Group Manager          │         │  │  │
│  │  │  │  - Auto-scaling: CPU > 70%          │         │  │  │
│  │  │  │  - Min/Max: Configurable            │         │  │  │
│  │  │  └─────────────────────────────────────┘         │  │  │
│  │  └──────────────────────────────────────────────────┘  │  │
│  │                                                          │  │
│  │  ┌───────────────────────────────────────────────────┐  │  │
│  │  │              Storage Layer                        │  │  │
│  │  │                                                   │  │  │
│  │  │  ┌─────────────────────────────────────────┐     │  │  │
│  │  │  │   Hot Storage (SSD - Local Disk)        │     │  │  │
│  │  │  │  - Type: pd-ssd                         │     │  │  │
│  │  │  │  - Size: 200GB-1000GB                   │     │  │  │
│  │  │  │  - Data: Frequently accessed            │     │  │  │
│  │  │  │  - Lifecycle: 保留 (Destroy不删除)       │     │  │  │
│  │  │  └─────────────────────────────────────────┘     │  │  │
│  │  │                      │                            │  │  │
│  │  │                      ▼                            │  │  │
│  │  │  ┌─────────────────────────────────────────┐     │  │  │
│  │  │  │   Cold Storage (GCS - Object Store)     │     │  │  │
│  │  │  │  - Bucket: doris-{env}-separation       │     │  │  │
│  │  │  │  - Data: Infrequently accessed          │     │  │  │
│  │  │  │  - Retention: 7-90 days                 │     │  │  │
│  │  │  │  - Lifecycle: 保留 (Destroy不删除)       │     │  │  │
│  │  │  └─────────────────────────────────────────┘     │  │  │
│  │  │                      │                            │  │  │
│  │  │                      ▼                            │  │  │
│  │  │  ┌─────────────────────────────────────────┐     │  │  │
│  │  │  │   Data Tiering (Automatic)              │     │  │  │
│  │  │  │  - Hot → Cold: 7 days no access         │     │  │  │
│  │  │  │  - Cold → Hot: On demand access         │     │  │  │
│  │  │  └─────────────────────────────────────────┘     │  │  │
│  │  └──────────────────────────────────────────────────┘  │  │
│  └─────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## 架构图

```
┌─────────────────────────────────────────────────────────────────┐
│                        GCP Project                              │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                   VPC Network                             │  │
│  │  (Subnet: 10.x.0.0/16)                                   │  │
│  │                                                           │  │
│  │  ┌────────────────────────────────────────────────────┐  │  │
│  │  │           Internal Load Balancer                   │  │  │
│  │  │  - VIP: 10.x.x.x                                   │  │  │
│  │  │  - Port: 9030 (MySQL)                              │  │  │
│  │  └────────────────────┬───────────────────────────────┘  │  │
│  │                       │                                   │  │
│  │  ┌────────────────────┴───────────────────────────────┐  │  │
│  │  │              FE Cluster (Metadata)                 │  │  │
│  │  │  ┌─────────┐  ┌─────────┐  ┌─────────┐           │  │  │
│  │  │  │  FE-1   │  │  FE-2   │  │  FE-3   │ (PROD)    │  │  │
│  │  │  │ (Master)│  │(Follower│  │(Follower│           │  │  │
│  │  │  └────┬────┘  └────┬────┘  └────┬────┘           │  │  │
│  │  │       └─────────────┴─────────────┘                │  │  │
│  │  │                     │                              │  │  │
│  │  │  ┌──────────────────┴──────────────────┐          │  │  │
│  │  │  │     Persistent Disk (Meta)          │          │  │  │
│  │  │  │  - Type: pd-balanced/pd-ssd        │          │  │  │
│  │  │  │  - Lifecycle: 保留                  │          │  │  │
│  │  │  └─────────────────────────────────────┘          │  │  │
│  │  └───────────────────────────────────────────────────┘  │  │
│  │                                                          │  │
│  │  ┌───────────────────────────────────────────────────┐  │  │
│  │  │           BE Cluster (Compute Only)               │  │  │
│  │  │                                                   │  │  │
│  │  │  ┌─────────┐  ┌─────────┐  ┌─────────┐          │  │  │
│  │  │  │  BE-1   │  │  BE-2   │  │  BE-n   │          │  │  │
│  │  │  │(Compute)│  │(Compute)│  │(Compute)│          │  │  │
│  │  │  └────┬────┘  └────┬────┘  └────┬────┘          │  │  │
│  │  │       └─────────────┴─────────────┘               │  │  │
│  │  │                     │                             │  │  │
│  │  │  ┌──────────────────┴──────────────────┐         │  │  │
│  │  │  │     Instance Group Manager          │         │  │  │
│  │  │  │  - Auto-scaling: CPU > 70%          │         │  │  │
│  │  │  │  - Min/Max: Configurable            │         │  │  │
│  │  │  └─────────────────────────────────────┘         │  │  │
│  │  └──────────────────────────────────────────────────┘  │  │
│  │                                                          │  │
│  │  ┌───────────────────────────────────────────────────┐  │  │
│  │  │              Storage Layer                        │  │  │
│  │  │                                                   │  │  │
│  │  │  ┌─────────────────────────────────────────┐     │  │  │
│  │  │  │   Hot Storage (SSD - Local Disk)        │     │  │  │
│  │  │  │  - Type: pd-ssd                         │     │  │  │
│  │  │  │  - Size: 200GB-1000GB                   │     │  │  │
│  │  │  │  - Data: Frequently accessed            │     │  │  │
│  │  │  │  - Lifecycle: 保留 (Destroy不删除)       │     │  │  │
│  │  │  └─────────────────────────────────────────┘     │  │  │
│  │  │                      │                            │  │  │
│  │  │                      ▼                            │  │  │
│  │  │  ┌─────────────────────────────────────────┐     │  │  │
│  │  │  │   Cold Storage (GCS - Object Store)     │     │  │  │
│  │  │  │  - Bucket: doris-{env}-separation       │     │  │  │
│  │  │  │  - Data: Infrequently accessed          │     │  │  │
│  │  │  │  - Retention: 7-90 days                 │     │  │  │
│  │  │  │  - Lifecycle: 保留 (Destroy不删除)       │     │  │  │
│  │  │  └─────────────────────────────────────────┘     │  │  │
│  │  │                      │                            │  │  │
│  │  │                      ▼                            │  │  │
│  │  │  ┌─────────────────────────────────────────┐     │  │  │
│  │  │  │   Data Tiering (Automatic)              │     │  │  │
│  │  │  │  - Hot → Cold: 7 days no access         │     │  │  │
│  │  │  │  - Cold → Hot: On demand access         │     │  │  │
│  │  │  └─────────────────────────────────────────┘     │  │  │
│  │  └──────────────────────────────────────────────────┘  │  │
│  └─────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## 核心特性

### 1. FE 高可用 (FoundationDB)

**为什么选择 FoundationDB？**
- **强一致性**: ACID 事务保证，数据永不丢失
- **高可用**: 自动故障检测和恢复，RPO=0, RTO<5s
- **水平扩展**: 支持多 FE 节点并发读写
- **云原生**: 专为分布式环境设计

**架构优势**:
```
传统 Doris FE:          FoundationDB + Doris FE:
┌─────────┐             ┌─────────┐ ┌─────────┐
│  FE-1   │             │  FE-1   │ │  FE-2   │  (Stateless)
│(Master) │             │(Active) │ │(Active) │
└────┬────┘             └────┬────┘ └────┬────┘
     │                       └─────┬─────┘
     │                             │
     ▼                             ▼
┌─────────┐             ┌─────────────────────┐
│BDBJE    │             │   FoundationDB      │
│(Single) │             │ (Distributed, HA)   │
└─────────┘             └─────────────────────┘
  单点故障风险                  高可用、强一致
```

### 2. 存算分离

| 存储类型 | 介质 | 用途 | 性能 | 成本 |
|---------|------|------|------|------|
| 热存储 | SSD (pd-ssd) | 频繁访问数据 | 高 | 中 |
| 冷存储 | GCS | 不常访问数据 | 中 | 低 |

**自动分层策略**:
- 新数据默认写入热存储 (SSD)
- 7天未访问的数据自动迁移到冷存储 (GCS)
- 访问冷数据时自动加载回热存储

### 3. 动态扩缩容

- **扩容触发**: CPU > 70%
- **缩容触发**: CPU < 30% (持续5分钟)
- **最小实例**: 2-5 (根据环境)
- **最大实例**: 5-20 (根据环境)
- **数据不丢失**: 存储与计算分离，扩容不影响数据

### 4. 数据持久化

集群销毁时保留：
- ✅ FoundationDB 数据磁盘
- ✅ FE 配置磁盘
- ✅ BE 热存储磁盘
- ✅ GCS 冷存储 Bucket
- ❌ 计算实例
- ❌ 负载均衡器

## 环境配置

| 环境 | FE | FDB | BE (初始) | BE (最大) | 热存储 | 冷存储保留 |
|------|----|-----|-----------|-----------|--------|-----------|
| DEV  | 2  | 3   | 2         | 5         | 200GB  | 7天       |
| SIT  | 2  | 3   | 3         | 8         | 400GB  | 30天      |
| UAT  | 3  | 5   | 4         | 10        | 600GB  | 30天      |
| PROD | 3  | 5   | 5         | 20        | 1000GB | 90天      |

### FoundationDB 配置

| 环境 | FDB 节点 | FDB 机器类型 | FDB 磁盘 |
|------|----------|--------------|----------|
| DEV  | 3        | e2-standard-2 | 50GB     |
| SIT  | 3        | e2-standard-4 | 100GB    |
| UAT  | 5        | e2-standard-8 | 200GB    |
| PROD | 5        | e2-standard-16| 500GB    |

## 快速开始

### 1. 前置要求

```bash
# 安装 Terraform
choco install terraform  # Windows
brew install terraform   # macOS

# 安装 gcloud CLI
# https://cloud.google.com/sdk/docs/install

# 认证
gcloud auth login

# 生成 SSH 密钥
ssh-keygen -t rsa -b 4096 -C "your-email@example.com"
```

### 2. 配置项目

编辑对应环境的配置文件：

```bash
# 修改 GCP Project ID 和 SSH 密钥路径
vi terraform.tfvars.dev
```

### 3. 部署

```bash
# 赋予执行权限 (Linux/macOS)
chmod +x *.sh

# 部署到 DEV 环境
./deploy.sh dev

# 部署到 PROD 环境
./deploy.sh prod
```

### 4. 连接集群

```bash
# 获取连接信息
terraform output connection_info

# 连接
mysql -h <LB_IP> -P 9030 -u root
```

## 使用存算分离

### 创建带存储策略的表

```sql
-- 创建使用存算分离策略的表
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
    PARTITION p202402 VALUES [('2024-02-01'), ('2024-03-01'))
)
DISTRIBUTED BY HASH(user_id) BUCKETS 16
PROPERTIES (
    "storage_policy" = "hot_to_cold",
    "hot_partition_num" = "3",
    "storage_cooldown_time" = "7 day"
);
```

### 查看存储分布

```sql
-- 查看表的数据分布
SHOW DATA SKEW FROM user_events;

-- 查看分区存储位置
SHOW PARTITIONS FROM user_events;

-- 查看存储策略
SHOW STORAGE POLICY;
```

### 手动迁移数据

```sql
-- 手动将数据迁移到冷存储
ALTER TABLE user_events MODIFY PARTITION p202401 
SET ("storage_policy" = "move_to_cold");

-- 手动将数据迁移回热存储
ALTER TABLE user_events MODIFY PARTITION p202401 
SET ("storage_policy" = "move_to_hot");
```

## 管理操作

### 查看状态

```bash
./status.sh
```

### 扩缩容

```bash
# 扩容到 10 个 BE 节点
./scale.sh dev 10

# 缩容到 3 个 BE 节点
./scale.sh dev 3
```

### 销毁集群 (保留数据)

```bash
./destroy.sh dev
```

### 完全清理 (删除所有数据)

```bash
./clean-all.sh dev
```

## 成本分析

### 存储成本对比

| 存储方案 | 成本/GB/月 | 1TB/月成本 |
|---------|-----------|-----------|
| 全 SSD (pd-ssd) | $0.17 | $170 |
| 全 HDD (pd-standard) | $0.04 | $40 |
| **存算分离** (20%热+80%冷) | **$0.05** | **$50** |

**节省**: 存算分离比全 SSD 节省约 **70%** 存储成本！

### 计算成本优化

- **自动扩缩容**: 低峰期自动减少实例，节省计算成本
- **抢占式实例**: BE 节点可使用抢占式实例，节省 80% 成本

## 性能优化

### 热存储优化

```sql
-- 调整热数据保留时间
ALTER TABLE user_events SET ("storage_cooldown_time" = "3 day");

-- 增加热分区数量
ALTER TABLE user_events SET ("hot_partition_num" = "5");
```

### 查询优化

```sql
-- 查看冷数据访问统计
SHOW TABLET STORAGE FORMAT;

-- 分析查询性能
EXPLAIN SELECT * FROM user_events WHERE created_at > '2024-01-01';
```

## 监控指标

### 关键指标

```bash
# 查看 BE 节点状态
gcloud compute instance-groups managed list-instances doris-separation-dev-be-igm --region=us-central1

# 查看 GCS 存储使用情况
gsutil du -sh gs://doris-dev-separation-storage/

# 查看磁盘使用情况
gcloud compute disks list --filter="name:doris-separation-dev"
```

### Doris 系统表

```sql
-- 查看 BE 存储使用情况
SHOW BACKENDS;

-- 查看数据分布
SHOW DATA SKEW;

-- 查看存储策略
SHOW STORAGE POLICY;

-- 查看表统计信息
SHOW TABLE STATUS;
```

## 故障排查

### FoundationDB 连接问题

```bash
# SSH 到 FE 节点
ssh -i ~/.ssh/id_rsa ubuntu@<FE_IP>

# 检查 FDB 客户端安装
fdbcli --version

# 检查 FDB 集群文件
cat /etc/foundationdb/fdb.cluster

# 测试 FDB 连接
fdbcli --exec "status"

# 查看 FDB 状态详情
fdbcli --exec "status details"
```

### FE 无法启动 (FDB 相关)

```bash
# 检查 FE 日志中的 FDB 错误
tail -f /opt/doris/fe/log/fe.log | grep -i foundationdb

# 检查 FDB 集群健康状态
fdbcli --exec "status"

# 如果 FDB 集群不健康，检查 FDB 节点
ssh -i ~/.ssh/id_rsa ubuntu@<FDB_IP>
fdbcli --exec "status"

# 查看 FDB 日志
tail -f /var/log/foundationdb/fdbserver.log
```

### BE 无法挂载 GCS

```bash
# SSH 到 BE 节点
ssh -i ~/.ssh/id_rsa ubuntu@<BE_IP>

# 检查 GCS 挂载
mount | grep gcs

# 手动挂载测试
gcsfuse doris-dev-separation-storage /mnt/gcs-cold-storage

# 检查权限
gcloud auth list
gcloud projects get-iam-policy <PROJECT_ID>
```

### 数据未自动分层

```bash
# 检查存储策略配置
cat /opt/doris/be/conf/storage_policy.conf

# 查看 BE 日志
tail -f /opt/doris/be/log/be.INFO | grep -i storage

# 手动触发分层
# (在 Doris 中执行)
ALTER TABLE table_name SET ("storage_policy" = "hot_to_cold");
```

### 扩缩容失败

```bash
# 查看 Instance Group 状态
gcloud compute instance-groups managed describe doris-separation-dev-be-igm --region=us-central1

# 查看 Autoscaler 状态
gcloud compute instance-groups managed describe doris-separation-dev-be-igm --region=us-central1 --format="yaml(autoscaler)"

# 查看健康检查
gcloud compute health-checks describe doris-separation-dev-be-health-check --region=us-central1
```

## 最佳实践

### 1. 表设计

```sql
-- 按时间分区，便于分层
CREATE TABLE events (
    event_time DATETIME,
    user_id INT,
    event_type VARCHAR(50)
)
PARTITION BY RANGE(event_time) (
    PARTITION p_current VALUES LESS THAN ('2024-02-01'),
    PARTITION p_history VALUES LESS THAN ('2024-01-01')
)
PROPERTIES ("storage_policy" = "hot_to_cold");
```

### 2. 存储策略选择

| 数据类型 | 建议策略 |
|---------|---------|
| 实时数据 (7天内) | 热存储 |
| 近期数据 (7-30天) | 自动分层 |
| 历史数据 (>30天) | 冷存储 |
| 归档数据 (>90天) | 冷存储 + 压缩 |

### 3. 扩缩容策略

- **定时扩缩容**: 业务高峰期前扩容，低峰期缩容
- **基于负载**: 设置合理的 CPU 阈值
- **预留缓冲**: 最小实例数要满足基本查询需求

## 技术支持

- Doris 官方文档: https://doris.apache.org/docs/
- GCP 存储文档: https://cloud.google.com/storage/docs
- Terraform GCP Provider: https://registry.terraform.io/providers/hashicorp/google/latest

## 许可证

Apache License 2.0
