# Doris GCP 集群 Terraform 企业级部署指南

## 概述

本部署方案提供企业级 Apache Doris 集群在 Google Cloud Platform (GCP) 上的完整解决方案，支持：

- **多环境管理**: DEV / SIT / UAT / PROD 四套独立配置
- **存算分离**: SSD 热存储 + GCS 冷存储，实现计算与存储分离
- **数据持久化**: 独立持久化磁盘，集群销毁不丢失数据
- **自动扩缩容**: 基于 CPU 利用率的自动水平扩展
- **负载均衡**: Internal Load Balancer 实现高可用访问
- **原生部署**: 无 Docker 容器，直接在 VM 上部署，性能最优

## 架构特性

### 1. 多环境隔离

| 环境 | GCP Project | FE 节点 | BE 节点 | 用途 |
|------|-------------|---------|---------|------|
| DEV  | doris-dev-project  | 1 | 2 (→5)  | 开发测试 |
| SIT  | doris-sit-project  | 2 | 3 (→8)  | 系统集成测试 |
| UAT  | doris-uat-project  | 2 | 4 (→10) | 用户验收测试 |
| PROD | doris-prod-project | 3 | 5 (→20) | 生产环境 |

### 2. 存算分离架构

```
┌─────────────────┐
│  FE Cluster    │ (Metadata & Query)
│  (pd-balanced)  │
└────────┬────────┘
         │
         ├─── Internal Load Balancer (MySQL Port: 9030)
         │
┌────────┴────────┐
│  BE Cluster    │ (Hot Storage: SSD)
│  (Instance     │
│   Group Mgr)   │
└────────┬────────┘
         │
         ├─── Automatic Scaling (CPU > 70%)
         │
┌────────┴────────┐
│  GCS Bucket    │ (Cold Storage)
│  (Object Store)│
└─────────────────┘
```

### 3. 数据持久化

- **FE 元数据磁盘**: 独立持久化磁盘，销毁实例后保留
- **BE 存储磁盘**: 独立持久化磁盘，销毁实例后保留
- **GCS 冷存储**: 数据自动分层，保留策略可配置

### 4. 自动扩缩容

- **触发条件**: CPU 利用率 > 70% (可配置)
- **扩容策略**: 每 5 分钟增加实例
- **缩容策略**: 负载降低后自动减少实例
- **手动控制**: 支持脚本手动扩缩容

## 前置要求

### 1. 安装 Terraform

```bash
# Windows (使用 Chocolatey)
choco install terraform

# 验证安装
terraform version
```

### 2. 配置 GCP 认证

```bash
# 安装 gcloud CLI
# 下载: https://cloud.google.com/sdk/docs/install

# 认证
gcloud auth login

# 设置项目
gcloud config set project YOUR_PROJECT_ID
```

### 3. 准备 SSH 密钥

```bash
# 生成 SSH 密钥对
ssh-keygen -t rsa -b 4096 -C "your-email@example.com"

# Windows 使用 PowerShell 或 Git Bash
# 公钥位置: ~/.ssh/id_rsa.pub
# 私钥位置: ~/.ssh/id_rsa
```

### 4. 创建 GCP 项目

为每个环境创建独立的 GCP 项目：

- DEV: `doris-dev-project`
- SIT: `doris-sit-project`
- UAT: `doris-uat-project`
- PROD: `doris-prod-project`

并启用以下 API：
- Compute Engine API
- Cloud Storage API
- Resource Manager API

## 快速开始

### Windows 用户

#### 1. 部署集群

```cmd
REM 部署到 DEV 环境
deploy.bat dev

REM 部署到 PROD 环境
deploy.bat prod
```

#### 2. 查看状态

```cmd
REM 查看集群状态
status.bat
```

#### 3. 销毁集群

```cmd
REM 销毁 DEV 环境 (保留磁盘和 GCS)
destroy.bat dev

REM 完全删除所有资源 (包括数据)
clean-all.bat dev
```

### Linux/macOS 用户

```bash
# 赋予脚本执行权限
chmod +x *.sh

# 部署集群
./deploy.sh dev

# 查看状态
./status.sh

# 销毁集群
./destroy.sh dev

# 完全清理
./clean-all.sh dev
```

## 配置说明

### 环境配置文件

每个环境都有独立的配置文件：

- `terraform.tfvars.dev` - 开发环境
- `terraform.tfvars.sit` - 系统集成测试环境
- `terraform.tfvars.uat` - 用户验收测试环境
- `terraform.tfvars.prod` - 生产环境

### 关键配置项

```hcl
# 项目和区域
project_id = "doris-dev-project"
region = "us-central1"
zone = "us-central1-a"

# 集群配置
cluster_name = "doris"
environment = "dev"

# FE 配置
fe_count = 1
fe_machine_type = "e2-medium"
fe_disk_size = 50
fe_disk_type = "pd-balanced"

# BE 配置
be_count = 2
be_machine_type = "e2-standard-2"
be_disk_size = 100
be_disk_type = "pd-ssd"

# 存算分离配置
enable_compute_storage_separation = true
gcs_bucket_name = "doris-dev-storage"
hot_storage_type = "pd-ssd"
hot_storage_size = 200
cold_storage_retention_days = 7

# 自动扩缩容配置
enable_autoscaling = true
be_min_count = 2
be_max_count = 5
autoscaling_cpu_target = 70

# 负载均衡配置
enable_load_balancer = true

# 网络配置
subnet_cidr = "10.0.0.0/16"
allowed_source_ranges = ["0.0.0.0/0"]
```

## 高级功能

### 1. 存算分离

启用存算分离后，Doris 会自动将冷数据移动到 GCS：

```sql
-- 创建表时指定存储策略
CREATE TABLE example_table (
    id INT,
    data VARCHAR(100)
) PROPERTIES (
    "storage_policy" = "cooldown_to_cold"
);

-- 查看存储分布
SHOW DATA SKEW;
```

### 2. 动态扩缩容

#### 自动扩缩容

当启用 `enable_autoscaling = true` 时，BE 节点会根据 CPU 利用率自动扩缩容。

#### 手动扩缩容

```bash
# Linux/macOS
./scale.sh prod up 3    # 增加 3 个 BE 节点
./scale.sh prod down 2  # 减少 2 个 BE 节点
./scale.sh prod set 10  # 设置为 10 个 BE 节点

# Windows (使用 Terraform 直接操作)
terraform apply -var-file=terraform.tfvars.prod -var="be_count=10"
```

### 3. 负载均衡

启用负载均衡后，使用内部 IP 连接：

```bash
# 获取 Load Balancer IP
terraform output lb_internal_ip

# 连接到集群
mysql -h <LB_INTERNAL_IP> -P 9030 -u root -p
```

### 4. 数据持久化

集群销毁时，持久化磁盘和 GCS 存储会保留：

```bash
# 销毁计算实例，保留数据
destroy.bat dev

# 重新部署，数据不会丢失
deploy.bat dev
```

## 连接和管理

### 连接到 FE

```bash
# 使用 Load Balancer (推荐)
LB_IP=$(terraform output -json | jq -r '.lb_internal_ip.value')
mysql -h $LB_IP -P 9030 -u root

# 或直接连接到 FE 实例
FE_IP=$(terraform output -json | jq -r '.fe_ips.value[0]')
mysql -h $FE_IP -P 9030 -u root
```

### 查看集群状态

```sql
-- 查看 FE 节点
SHOW FRONTENDS;

-- 查看 BE 节点
SHOW BACKENDS;

-- 查看集群信息
SHOW PROC '/cluster_info';

-- 查看存储统计
SHOW DATA SKEW;
```

### SSH 连接到实例

```bash
# 连接到 FE 实例
ssh -i ~/.ssh/id_rsa ubuntu@<FE_IP>

# 连接到 BE 实例
ssh -i ~/.ssh/id_rsa ubuntu@<BE_IP>
```

### 查看日志

```bash
# FE 日志
tail -f /opt/doris/fe/log/fe.log

# BE 日志
tail -f /opt/doris/be/log/be.INFO

# Systemd 日志
journalctl -u doris-fe -f
journalctl -u doris-be -f
```

## 成本优化

### 1. 使用抢占式实例

```hcl
fe_preemptible = true
be_preemptible = true
```

**注意**: 抢占式实例可能随时被回收，仅适用于 BE 节点，不建议用于 FE。

### 2. 选择合适的机器类型

| 机器类型 | vCPU | 内存 | 适用场景 |
|---------|------|------|---------|
| e2-medium | 2 | 4GB | DEV 测试 |
| e2-standard-2 | 2 | 8GB | DEV/SIT FE |
| e2-standard-4 | 4 | 16GB | UAT/PROD FE |
| e2-standard-8 | 8 | 32GB | SIT BE |
| e2-standard-16 | 16 | 64GB | PROD BE |

### 3. 存储优化

- **热数据**: 使用 SSD (pd-ssd)
- **冷数据**: 使用 GCS 存储分层
- **保留策略**: 根据业务需求调整 `cold_storage_retention_days`

### 4. 自动扩缩容

合理设置自动扩缩容参数，避免过度配置：

```hcl
be_min_count = 2        # 最小实例数
be_max_count = 5        # 最大实例数
autoscaling_cpu_target = 70  # CPU 阈值
```

## 监控和维护

### 健康检查

```bash
# 使用 Instance Group Manager 健康检查
gcloud compute instance-groups managed list-instances \
    <INSTANCE_GROUP_NAME> --zone=<ZONE>

# 检查磁盘健康
gcloud compute disks list --filter="name~doris*"
```

### 备份策略

1. **FE 元数据备份**

```bash
# 备份 FE 元数据
sudo cp -r /opt/doris/fe/doris-meta /backup/

# 或使用 Doris 工具
mysql -h <FE_IP> -P 9030 -u root -e "BACKUP SNAPSHOT example_snapshot TO repository;"
```

2. **GCS 存储备份**

```bash
# 备份 GCS Bucket
gsutil -m rsync -r gs://doris-dev-storage gs://doris-dev-storage-backup
```

### 更新集群

```bash
# 滚动更新 BE 节点 (使用 Instance Group Manager)
gcloud compute instance-groups managed rolling-action start-update \
    <INSTANCE_GROUP_NAME> --version=template=<NEW_TEMPLATE>

# 手动更新 FE 节点
terraform apply -var-file=terraform.tfvars.dev -replace=google_compute_instance_from_template.fe_instances[0]
```

## 故障排查

### 1. FE 无法启动

```bash
# 检查服务状态
systemctl status doris-fe

# 查看日志
journalctl -u doris-fe -n 100
tail -100 /opt/doris/fe/log/fe.log

# 检查磁盘挂载
lsblk
df -h
```

### 2. BE 无法启动

```bash
# 检查服务状态
systemctl status doris-be

# 查看日志
journalctl -u doris-be -n 100
tail -100 /opt/doris/be/log/be.INFO

# 检查存储磁盘
lsblk
df -h
```

### 3. BE 无法加入集群

```bash
# 检查网络连通性
ping <FE_IP>
telnet <FE_IP> 9030

# 检查 FE 日志
tail -f /opt/doris/fe/log/fe.log

# 检查 BE 状态
mysql -h <FE_IP> -P 9030 -u root -e "SHOW BACKENDS;"
```

### 4. 自动扩缩容不生效

```bash
# 检查 Instance Group Manager
gcloud compute instance-groups managed describe <IGM_NAME> --zone=<ZONE>

# 检查 Autoscaler
gcloud compute instance-groups managed describe <IGM_NAME> --zone=<ZONE> --format="yaml(autoscaler)"

# 检查健康检查
gcloud compute health-checks describe <HEALTH_CHECK_NAME> --region=<REGION>
```

## 安全建议

1. **网络隔离**
   - 使用 VPC Peering 连接不同环境
   - 限制 `allowed_source_ranges` 为特定 IP 段

2. **访问控制**
   - 启用 Doris 认证 (`enable_auth = true`)
   - 使用强密码
   - 定期轮换密钥

3. **数据加密**
   - 启用磁盘加密
   - 启用 GCS Bucket 加密
   - 使用 SSL/TLS 连接

4. **审计日志**
   - 启用 GCP 审计日志
   - 启用 Doris 审计日志

## 技术支持

- Doris 官方文档: https://doris.apache.org/docs/
- Terraform GCP 文档: https://registry.terraform.io/providers/hashicorp/google/latest
- GCP 文档: https://cloud.google.com/docs
- GCP Instance Group Manager: https://cloud.google.com/compute/docs/instance-groups/

## 许可证

Apache License 2.0

## 版本历史

- **v2.0.0** (2026-01-28)
  - 添加 DEV/SIT/UAT/PROD 多环境支持
  - 实现存算分离架构
  - 添加自动扩缩容
  - 添加负载均衡
  - 实现数据持久化

- **v1.0.0** (Initial)
  - 基础 Terraform 部署
  - 支持 1FE+2BE, 2FE+2BE, 3FE+3BE 配置
