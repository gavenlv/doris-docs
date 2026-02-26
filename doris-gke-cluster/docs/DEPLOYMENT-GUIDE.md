# Doris GKE 集群详细部署指南

## 文档概述

本指南提供 Doris GKE 集群的完整部署流程，包括环境准备、集群创建、组件部署和验证测试。

**目标**：
- 50 亿行数据/2 分钟导入
- 1000 亿行表查询 < 10 秒
- 50 并发用户
- 成本优化（Spot VM + 自动扩缩容）

## 部署架构

```
GKE Private Cluster
├── Core Node Pool (n2-standard-4)
│   ├── FE x 3 (Doris Frontend)
│   └── FDB x 3 (FoundationDB)
├── BE Core Pool (n2-standard-16)
│   └── BE x 2-3 (基线容量)
└── BE Compute Pool (n2-standard-16 Spot)
    └── BE x 2-20 (弹性扩容)

Storage:
├── Local SSD (1.5TB/BE节点) - 热数据
└── GCS Bucket - 冷数据

Network:
├── VPC Native
├── Private Cluster (无公网)
└── Private Google Access
```

## 前置条件

### 工具要求

| 工具 | 版本 | 用途 |
|------|------|------|
| gcloud CLI | 最新版 | GCP 资源管理 |
| kubectl | 1.28+ | Kubernetes 管理 |
| Terraform | 1.0+ | 基础设施即代码 |
| Docker | 20.10+ | 镜像管理 |
| MySQL Client | 8.0+ | Doris 连接 |

### 权限要求

- GCP 项目所有者或编辑者权限
- Nexus Docker 仓库管理员权限（首次部署）
- 公司网络访问权限

### 资源配额

确保 GCP 项目有足够配额：

- Compute Engine: 30+ vCPUs
- Persistent Disk: 5TB+
- Cloud NAT: 1 个网关

## 步骤 1: 环境准备

### 1.1 安装必要工具

```bash
# 安装 gcloud CLI
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
gcloud init

# 安装 kubectl
gcloud components install kubectl

# 安装 Terraform
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# 安装 Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# 验证安装
gcloud version
kubectl version --client
terraform version
docker --version
```

### 1.2 配置 GCP 项目

```bash
# 设置项目
export PROJECT_ID="your-project-id"
gcloud config set project $PROJECT_ID

# 启用必要的 API
gcloud services enable compute.googleapis.com
gcloud services enable container.googleapis.com
gcloud services enable storage.googleapis.com
gcloud services enable servicenetworking.googleapis.com

# 配置默认区域
gcloud config set compute/region us-central1
gcloud config set compute/zone us-central1-a
```

### 1.3 克隆项目

```bash
git clone <repository-url>
cd doris-gke-cluster
```

## 步骤 2: 镜像准备

### 2.1 配置 Nexus 访问

```bash
# 登录 Nexus
export NEXUS_URL="nexus.company.com:8082"
export NEXUS_USER="admin"
export NEXUS_PASS="your-password"

docker login $NEXUS_URL
```

### 2.2 同步镜像

```bash
# 运行镜像同步脚本
./scripts/sync-images.sh
```

验证镜像已同步：

```bash
curl -u $NEXUS_USER:$NEXUS_PASS \
  https://$NEXUS_URL/v2/_catalog
```

## 步骤 3: 创建 GKE 集群

### 3.1 配置 Terraform 变量

编辑 `terraform/terraform.tfvars.prod`:

```bash
project_id = "your-project-id"
gcs_bucket_name = "doris-prod-cold-storage-your-company"
nexus_url = "nexus.company.com:8082"

# 根据需求调整
core_pool_min_nodes = 3
be_compute_pool_max_nodes = 20
```

### 3.2 执行 Terraform 部署

```bash
cd terraform

# 初始化
terraform init

# 创建执行计划
terraform plan -var-file=terraform.tfvars.prod -out=tfplan

# 应用
terraform apply tfplan
```

**预计时间**: 10-15 分钟

### 3.3 获取集群凭证

```bash
# 自动配置 kubectl
gcloud container clusters get-credentials doris-prod \
  --region us-central1 \
  --project your-project-id

# 验证连接
kubectl cluster-info
kubectl get nodes
```

## 步骤 4: 部署 Doris 组件

### 4.1 创建命名空间

```bash
kubectl apply -f kubernetes/namespace.yaml
```

### 4.2 创建 Docker Secret

```bash
kubectl create secret docker-registry nexus-secret \
  --docker-server=nexus.company.com:8082 \
  --docker-username=admin \
  --docker-password=your-password \
  -n doris
```

### 4.3 创建存储类

```bash
# 更新 GCS bucket 名称
sed -i 's/doris-prod-cold-storage/your-bucket-name/g' \
  kubernetes/storage/storage-class.yaml

kubectl apply -f kubernetes/storage/storage-class.yaml
```

### 4.4 部署 FoundationDB

```bash
kubectl apply -f kubernetes/doris-cluster/fdb.yaml

# 等待就绪
kubectl wait --for=condition=ready pod -l app=fdb -n doris --timeout=300s

# 验证
kubectl get pods -n doris -l app=fdb
```

### 4.5 部署 Doris FE

```bash
kubectl apply -f kubernetes/doris-cluster/fe.yaml

# 等待就绪（首次启动较慢）
sleep 60
kubectl wait --for=condition=ready pod -l app=fe -n doris --timeout=600s

# 验证
kubectl get pods -n doris -l app=fe
kubectl get svc -n doris
```

### 4.6 部署 Doris BE

```bash
kubectl apply -f kubernetes/doris-cluster/be.yaml

# 等待就绪
sleep 60
kubectl wait --for=condition=ready pod -l app=be -n doris --timeout=600s || true

# 验证
kubectl get pods -n doris -l app=be
```

### 4.7 配置自动扩缩容

```bash
kubectl apply -f kubernetes/autoscaling/hpa-be.yaml

# 验证 HPA
kubectl get hpa -n doris
```

## 步骤 5: 验证部署

### 5.1 检查整体状态

```bash
# 查看所有资源
kubectl get all -n doris

# 查看 Pod 详细信息
kubectl describe pods -n doris
```

### 5.2 连接到 Doris

```bash
# 获取 FE IP
FE_IP=$(kubectl get svc fe-lb -n doris \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "FE IP: $FE_IP"

# 连接
mysql -h $FE_IP -P 9030 -u root
```

### 5.3 验证集群状态

```sql
-- 查看 FE 节点
SHOW FRONTENDS;

-- 查看 BE 节点
SHOW BACKENDS;

-- 创建测试数据库
CREATE DATABASE test_db;
USE test_db;

-- 创建测试表
CREATE TABLE test_table (
    id INT,
    name VARCHAR(100)
) DISTRIBUTED BY HASH(id) BUCKETS 10;

-- 插入测试数据
INSERT INTO test_table VALUES (1, 'test'), (2, 'test2');

-- 查询
SELECT * FROM test_table;

-- 清理
DROP DATABASE test_db;
```

## 步骤 6: 性能测试

### 6.1 运行负载测试

```bash
cd doris-gke-cluster

# 设置 FE 地址
export FE_HOST=$FE_IP
export FE_PORT=9030

# 运行测试
./scripts/test-load.sh
```

### 6.2 性能指标

验证是否满足目标：

- ✅ 导入性能: 50 亿行 < 2 分钟
- ✅ 查询性能: 1000 亿行表 < 10 秒
- ✅ 并发能力: 50 用户同时查询

## 步骤 7: 监控和日志

### 7.1 查看监控指标

```bash
# 查看 HPA 状态
kubectl get hpa -n doris -w

# 查看节点资源使用
kubectl top nodes

# 查看 Pod 资源使用
kubectl top pods -n doris
```

### 7.2 查看日志

```bash
# FE 日志
kubectl logs -n doris -l app=fe --tail=100

# BE 日志
kubectl logs -n doris -l app=be --tail=100

# FDB 日志
kubectl logs -n doris -l app=fdb --tail=100
```

## 步骤 8: 日常运维

### 8.1 扩缩容

```bash
# 手动扩容
./scripts/scale.sh up 20

# 查看状态
./scripts/scale.sh status

# 手动缩容
./scripts/scale.sh down 10
```

### 8.2 备份数据

```sql
-- 连接到 Doris
mysql -h $FE_IP -P 9030 -u root

-- 备份表
BACKUP TABLE db_name.table_name TO "gs://backup-bucket/doris-backup/";

-- 恢复表
RESTORE TABLE db_name.table_name FROM "gs://backup-bucket/doris-backup/";
```

### 8.3 升级集群

```bash
# 1. 准备新版本镜像
# 2. 更新 Kubernetes 配置中的镜像版本
# 3. 滚动升级

kubectl set image statefulset/fe fe=nexus.company.com/doris/fe:3.1.5 -n doris
kubectl set image statefulset/be be=nexus.company.com/doris/be:3.1.5 -n doris
```

## 故障排查

### 常见问题

**问题 1: Pod 无法启动**

```bash
# 查看 Pod 状态
kubectl describe pod <pod-name> -n doris

# 查看日志
kubectl logs <pod-name> -n doris

# 常见原因:
# - 镜像拉取失败: 检查 nexus-secret
# - 资源不足: 检查节点资源
# - 存储挂载失败: 检查 PV/PVC
```

**问题 2: FE 无法连接 FDB**

```bash
# 检查 FDB 连接
kubectl exec -n doris -it fdb-0 -- fdbcli

# 在 fdbcli 中执行
status

# 检查网络连接
kubectl exec -n doris -it fe-0 -- ping fdb-0.fdb.doris.svc.cluster.local
```

**问题 3: BE 节点未注册**

```bash
# 手动添加 BE 节点
mysql -h $FE_IP -P 9030 -u root

ALTER SYSTEM ADD BACKEND "be-pod-ip:9050";
```

### 性能调优

**优化 1: 增加并行度**

```sql
-- 设置查询并行度
SET GLOBAL parallel_fragment_exec_instance_num = 16;
```

**优化 2: 调整缓存**

```sql
-- 查看缓存配置
SHOW VARIABLES LIKE '%cache%';

-- 启用查询缓存
SET GLOBAL enable_query_cache = true;
```

**优化 3: 表设计优化**

```sql
-- 使用合适的分区
CREATE TABLE large_table (
    id BIGINT,
    date DATE,
    ...
) PARTITION BY RANGE(date) (
    PARTITION p202601 VALUES [('2026-01-01'), ('2026-02-01')),
    PARTITION p202602 VALUES [('2026-02-01'), ('2026-03-01'))
)
DISTRIBUTED BY HASH(id) BUCKETS 128;

-- 使用 Colocate Group 优化 Join
CREATE TABLE dim_table (
    id BIGINT,
    ...
) DISTRIBUTED BY HASH(id) BUCKETS 128
PROPERTIES ("colocate_with" = "group1");
```

## 安全加固

### 网络安全

```bash
# 配置 VPC 防火墙规则
gcloud compute firewall-rules create doris-allow-internal \
  --network doris-vpc \
  --allow tcp,udp,icmp \
  --source-ranges 10.0.0.0/8

# 限制 Master 访问
# 在 Terraform 中配置 master_authorized_networks
```

### 访问控制

```sql
-- 创建用户
CREATE USER 'analyst'@'%' IDENTIFIED BY 'password';

-- 授权
GRANT SELECT ON database.* TO 'analyst'@'%';

-- 创建角色
CREATE ROLE 'read_only';
GRANT SELECT ON *.* TO 'read_only';
GRANT 'read_only' TO 'analyst'@'%';
```

## 成本优化

### 使用 Spot VM

```bash
# Spot VM 已在 Terraform 中配置
# BE Compute Pool 使用 Spot 实例
# 节省 60-80% 成本
```

### 承诺使用折扣

```bash
# 申请 CUD (Committed Use Discounts)
# 1 年承诺: 降低 20%
# 3 年承诺: 降低 40%
```

### 监控成本

```bash
# 查看集群成本
gcloud billing accounts list

# 设置预算告警
gcloud billing budgets create \
  --billing-account=ACCOUNT_ID \
  --display-name="Doris Cluster Budget" \
  --budget-amount=5000USD
```

## 附录

### 配置清单

- [ ] GCP 项目已创建
- [ ] Nexus 镜像仓库已配置
- [ ] Terraform 变量已更新
- [ ] GCS bucket 名称已配置
- [ ] Kubernetes Secret 已创建
- [ ] 所有组件已部署
- [ ] 性能测试已通过

### 性能基准

| 指标 | 目标 | 测试方法 |
|------|------|---------|
| 导入吞吐 | 50 亿行/2 分钟 | Stream Load |
| 查询延迟 | < 10 秒 (1000 亿行) | Star Schema Query |
| 并发用户 | 50 | Concurrent Connections |
| 可用性 | 99.9% | Health Checks |

### 联系支持

- 技术支持: doris-support@company.com
- 运维团队: doris-ops@company.com
- 紧急联系: +86-xxx-xxxx-xxxx

---

**部署完成！** 🎉

继续参考：
- [架构文档](ARCHITECTURE.md)
- [性能调优指南](TUNING.md)
- [成本优化说明](COST-OPTIMIZATION.md)
