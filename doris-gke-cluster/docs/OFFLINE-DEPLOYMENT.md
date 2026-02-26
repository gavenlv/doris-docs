# Doris GKE 集群离线部署指南

## 概述

本指南说明如何在完全离线的环境中部署 Doris GKE 集群。适用于无法访问外网的企业内网环境。

## 适用场景

- 公司内网完全隔离，无法访问 Docker Hub
- GKE Private Cluster，无公网访问
- 安全要求高的生产环境
- 需要完全控制镜像版本的部署

## 离线部署架构

```
┌─────────────────────────────────────────┐
│         公司内网（完全隔离）              │
│                                         │
│  ┌──────────────┐      ┌─────────────┐ │
│  │ Nexus Docker │◄─────┤ GKE Private │ │
│  │   Registry   │      │   Cluster   │ │
│  └──────────────┘      └─────────────┘ │
│        ▲                               │
│        │                               │
│  ┌─────┴──────┐                        │
│  │ Admin 工作站│                       │
│  │ (有外网访问) │                       │
│  └────────────┘                        │
└─────────────────────────────────────────┘
```

## 阶段 1: 准备阶段（需要外网访问）

### 1.1 准备管理工作站

准备工作站，该工作站需要：
- 能访问外网（用于下载镜像）
- 能访问公司内网 Nexus
- Docker 客户端已安装
- kubectl 已安装

### 1.2 下载镜像并保存为离线包

```bash
cd doris-gke-cluster

# 方式 1: 使用准备脚本
./scripts/prepare-offline.sh prepare

# 这将在 offline-images/ 目录生成所有镜像的 tar.gz 文件
```

或者手动下载：

```bash
# 拉取镜像
docker pull apache/doris:fe-3.1.4
docker pull apache/doris:be-3.1.4
docker pull foundationdb/foundationdb:7.1.37
docker pull apache/doris-operator:v1.1.0

# 保存为 tar 文件
docker save apache/doris:fe-3.1.4 -o doris-fe-3.1.4.tar
docker save apache/doris:be-3.1.4 -o doris-be-3.1.4.tar
docker save foundationdb/foundationdb:7.1.37 -o fdb-7.1.37.tar
docker save apache/doris-operator:v1.1.0 -o doris-operator-v1.1.0.tar

# 压缩
gzip doris-fe-3.1.4.tar
gzip doris-be-3.1.4.tar
gzip fdb-7.1.37.tar
gzip doris-operator-v1.1.0.tar
```

### 1.3 传输到离线环境

将以下文件传输到离线环境：

```bash
# 传输整个项目目录
doris-gke-cluster/
├── offline-images/          # 镜像 tar.gz 文件
├── scripts/                 # 部署脚本
├── kubernetes/             # K8s 配置
├── terraform/              # Terraform 配置
└── configs/                # 配置文件
```

传输方式：
- USB 移动硬盘
- 内网文件共享
- 公司内部文件传输系统

## 阶段 2: 镜像导入到 Nexus

### 2.1 加载镜像到本地 Docker

在离线环境的工作站上：

```bash
cd doris-gke-cluster

# 使用脚本加载
./scripts/prepare-offline.sh load

# 或手动加载
gunzip -c offline-images/doris-fe-3.1.4.tar.gz | docker load
gunzip -c offline-images/doris-be-3.1.4.tar.gz | docker load
gunzip -c offline-images/fdb-7.1.37.tar.gz | docker load
gunzip -c offline-images/doris-operator-v1.1.0.tar.gz | docker load
```

### 2.2 重新打标签

```bash
# 标记为 Nexus 地址
docker tag apache/doris:fe-3.1.4 nexus.company.com:8082/doris/fe:3.1.4
docker tag apache/doris:be-3.1.4 nexus.company.com:8082/doris/be:3.1.4
docker tag foundationdb/foundationdb:7.1.37 nexus.company.com:8082/foundationdb:7.1.37
docker tag apache/doris-operator:v1.1.0 nexus.company.com:8082/doris-operator:v1.1.0
```

### 2.3 推送到 Nexus

```bash
# 登录 Nexus
docker login nexus.company.com:8082

# 推送镜像
docker push nexus.company.com:8082/doris/fe:3.1.4
docker push nexus.company.com:8082/doris/be:3.1.4
docker push nexus.company.com:8082/foundationdb:7.1.37
docker push nexus.company.com:8082/doris-operator:v1.1.0
```

### 2.4 验证镜像

```bash
# 列出 Nexus 中的镜像
curl -u admin:password http://nexus.company.com:8082/v2/_catalog

# 列出特定镜像的标签
curl -u admin:password http://nexus.company.com:8082/v2/doris/fe/tags/list
```

## 阶段 3: 部署 GKE 集群

### 3.1 创建 Private GKE Cluster

```bash
cd doris-gke-cluster/terraform

# 初始化
terraform init

# 创建计划
terraform plan -var-file=terraform.tfvars.prod -out=tfplan

# 应用
terraform apply tfplan
```

**注意**: Private Cluster 创建时，需要通过 Cloud NAT 或其他方式访问 GCS。

### 3.2 配置 kubectl

```bash
# 获取集群凭证
gcloud container clusters get-credentials doris-prod \
  --region us-central1 \
  --project your-project-id
```

### 3.3 验证集群连接

```bash
kubectl cluster-info
kubectl get nodes
```

## 阶段 4: 部署 Doris 组件

### 4.1 创建命名空间和 Secret

```bash
cd doris-gke-cluster/kubernetes

# 创建命名空间
kubectl apply -f namespace.yaml

# 创建 Nexus Secret
kubectl create secret docker-registry nexus-secret \
  --docker-server=nexus.company.com:8082 \
  --docker-username=admin \
  --docker-password=your-password \
  -n doris
```

### 4.2 创建存储类

```bash
kubectl apply -f storage/storage-class.yaml
```

**注意**: 更新 `storage-class.yaml` 中的 GCS bucket 名称。

### 4.3 部署 FoundationDB

```bash
kubectl apply -f doris-cluster/fdb.yaml

# 等待 FDB 就绪
kubectl wait --for=condition=ready pod -l app=fdb -n doris --timeout=300s
```

### 4.4 部署 Doris FE

```bash
kubectl apply -f doris-cluster/fe.yaml

# 等待 FE 就绪
sleep 60
kubectl wait --for=condition=ready pod -l app=fe -n doris --timeout=600s
```

### 4.5 部署 Doris BE

```bash
kubectl apply -f doris-cluster/be.yaml

# 等待 BE 就绪
sleep 60
kubectl wait --for=condition=ready pod -l app=be -n doris --timeout=600s || true
```

### 4.6 配置自动扩缩容

```bash
kubectl apply -f autoscaling/hpa-be.yaml
```

## 阶段 5: 验证部署

### 5.1 检查 Pod 状态

```bash
kubectl get pods -n doris -o wide
```

期望输出：
- 3 个 FDB Pod: `Running`
- 3 个 FE Pod: `Running`
- 5-25 个 BE Pod: `Running`

### 5.2 检查服务

```bash
kubectl get services -n doris
```

### 5.3 连接到 Doris

```bash
# 获取 FE Load Balancer IP
FE_IP=$(kubectl get svc fe-lb -n doris -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# 连接
mysql -h $FE_IP -P 9030 -u root
```

### 5.4 验证集群状态

```sql
-- 连接到 Doris 后执行
SHOW FRONTENDS;
SHOW BACKENDS;
SHOW DATABASES;
```

## 故障排查

### 问题 1: 镜像拉取失败

**症状**: `ImagePullBackOff`

**排查步骤**:
```bash
# 检查 Pod 详细信息
kubectl describe pod <pod-name> -n doris

# 检查 Secret
kubectl get secret nexus-secret -n doris -o yaml

# 测试 Nexus 连接
curl -u admin:password http://nexus.company.com:8082/v2/_catalog
```

### 问题 2: Private Cluster 无法访问 GCS

**解决方案**:
```bash
# 启用 Private Google Access
gcloud compute networks subnets update doris-subnet \
  --region us-central1 \
  --enable-private-ip-google-access
```

### 问题 3: Pod 无法启动

**排查步骤**:
```bash
# 查看 Pod 日志
kubectl logs <pod-name> -n doris

# 查看事件
kubectl get events -n doris --sort-by='.lastTimestamp'
```

## 安全加固

1. **网络安全**:
   - 配置 VPC 防火墙规则
   - 限制访问 GKE Master 的 IP 范围
   - 使用 Cloud NAT 控制出站流量

2. **访问控制**:
   - 使用 Workload Identity
   - 配置 RBAC 规则
   - 定期轮换密钥

3. **监控审计**:
   - 启用 Cloud Audit Logs
   - 配置监控告警
   - 定期审查访问日志

## 性能验证

### 导入性能测试

```bash
# 运行负载测试
./scripts/test-load.sh
```

目标：
- 50 亿行数据导入 < 2 分钟
- 查询响应 < 10 秒

## 日常维护

### 扩容

```bash
# 手动扩容 BE
./scripts/scale.sh up 20

# 查看状态
./scripts/scale.sh status
```

### 备份

```bash
# 备份 GCS 数据
gsutil -m cp -r gs://doris-prod-cold-storage gs://doris-backup/

# 备份 FDB 数据
kubectl exec -n doris fdb-0 -- fdbbackup start -d file:///backup
```

### 升级

```bash
# 准备新版本镜像
# 更新镜像版本号
# 滚动升级
```

## 附录

### 离线镜像清单

- `apache/doris:fe-3.1.4`
- `apache/doris:be-3.1.4`
- `foundationdb/foundationdb:7.1.37`
- `apache/doris-operator:v1.1.0`
- `prom/prometheus:v2.45.0` (可选)
- `grafana/grafana:10.2.0` (可选)

### 依赖工具

- Docker 20.10+
- kubectl 1.28+
- Terraform 1.0+
- gcloud CLI
- MySQL Client 8.0+

### 联系支持

- Doris 部署团队: doris-team@company.com
- Nexus 管理员: nexus-admin@company.com
- GCP 平台支持: gcp-support@company.com
