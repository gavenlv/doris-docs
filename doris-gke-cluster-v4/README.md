# Doris Kubernetes 部署项目

在 Kubernetes 环境中部署 Apache Doris 4.0.4 存算分离集群，支持本地开发和 GKE 生产环境。

## 特性

- **存算分离架构**: FE + BECN，数据存储在 MinIO (本地) / GCS (GKE)
- **高可用**: 3 副本 Raft 组，支持自动故障恢复
- **自动扩缩容**: HPA 支持，基于 CPU/内存指标
- **离线构建**: 基于本地包构建镜像，不依赖外网

## 版本

| 组件 | 版本 |
|------|------|
| Apache Doris | 4.0.4 |
| Doris Operator | 1.4.0 |
| FoundationDB | 7.1.37 |

## 目录结构

```
doris-gke-cluster-v4/
├── build-tools/                 # 构建工具：镜像构建 + Nexus 推送
│   ├── build-all.sh             # 完整构建流程
│   ├── pre-build.sh             # 下载离线包
│   ├── nexus-docker-compose.yaml # 本地 Nexus
│   └── README.md
│
├── offline-packages/            # 离线包目录（需手动下载或运行 pre-build.sh）
│   └── foundationdb/            # FDB DEB 包
│
├── docker/                      # Dockerfiles
│   ├── fe/Dockerfile            # FE 镜像
│   ├── be/Dockerfile            # BE 镜像
│   └── fdb/Dockerfile           # FDB 镜像
│
├── k8s-local/                   # 本地 Docker Desktop K8s 配置
│   ├── doris-disaggregated-cluster.yaml  # 存算分离集群 CRD
│   ├── operator.yaml             # Doris Operator
│   ├── fdb-operator.yaml        # FDB Operator
│   ├── fdbcluster.yaml           # FDB 集群
│   ├── minio-statefulset.yaml   # MinIO 存储
│   ├── configmap.yaml           # FE/BE 配置
│   ├── secret.yaml              # 密钥配置
│   ├── hpa.yaml                 # 自动扩缩容
│   ├── deploy.sh                # 部署脚本
│   └── undeploy.sh              # 卸载脚本
│
├── k8s-gke/                     # GKE 生产配置
│   ├── doriscluster.yaml         # DorisCluster CRD
│   ├── operator.yaml             # Doris Operator
│   ├── configmap.yaml           # FE 配置
│   ├── configmap-be.yaml        # BE 配置
│   ├── services.yaml            # 负载均衡服务
│   ├── hpa.yaml                 # 自动扩缩容
│   ├── monitoring.yaml          # Prometheus 监控
│   ├── network-policy.yaml      # 网络策略
│   ├── deploy.sh                # 部署脚本
│   └── undeploy.sh              # 卸载脚本
│
└── ARCHITECTURE.md             # 架构详解
```

## 快速开始

### 步骤 1: 下载离线包

```bash
cd build-tools
./pre-build.sh
```

### 步骤 2: 构建镜像并推送到 Nexus

```bash
./build-all.sh
```

### 步骤 3: 部署到 Kubernetes

**本地 (Docker Desktop K8s)**:

```bash
cd ../k8s-local
./deploy.sh
```

**GKE 生产环境**:

```bash
cd ../k8s-gke
# 设置环境变量
export PROJECT_ID="your-project-id"
export CLUSTER_NAME="doris-cluster"
export REGION="us-central1"
export NEXUS_REGISTRY="nexus.company.com:5000/doris"

./deploy.sh
```

## 架构说明

### 存算分离 (Storage-Compute Separation)

```
┌─────────────────────────────────────────────────────────────┐
│                    DorisDisaggregatedCluster                  │
│                                                             │
│  ┌──────────┐   ┌──────────┐   ┌──────────┐               │
│  │    FE    │   │    FE    │   │    FE    │  (3 副本)    │
│  │ (Query)  │◄──│ (Query)  │◄──│ (Query)  │               │
│  └────┬─────┘   └────┬─────┘   └────┬─────┘               │
│       │              │              │                       │
│       └──────────────┼──────────────┘                       │
│                      ▼                                      │
│               ┌────────────┐                               │
│               │MetaService │ (3 副本)                      │
│               │ (FDB 存储) │                               │
│               └─────┬──────┘                               │
│                     │                                       │
│       ┌─────────────┼─────────────┐                        │
│       ▼             ▼             ▼                        │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐                    │
│  │   BECN   │ │   BECN   │ │   BECN   │  (N 副本)        │
│  │ (Compute)│ │ (Compute)│ │ (Compute)│                    │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘                   │
│       │            │            │                           │
│       └────────────┼────────────┘                           │
│                    ▼                                        │
│               ┌────────────┐                               │
│               │ MinIO/GCS  │  (S3 兼容对象存储)             │
│               └────────────┘                               │
└─────────────────────────────────────────────────────────────┘
```

### 本地 vs GKE

| 特性 | k8s-local | k8s-gke |
|------|-----------|---------|
| 存储后端 | MinIO | GCS |
| 部署环境 | Docker Desktop K8s | Google GKE |
| 访问方式 | NodePort | LoadBalancer |
| 高可用 | 3 副本 | 3 副本 |

## 扩缩容

### 手动扩缩容

```bash
# FE
kubectl scale statefulset doris-disagg-cluster-fe --replicas=5 -n doris

# BECN
kubectl scale statefulset doris-disagg-cluster-becn --replicas=10 -n doris
```

### 自动扩缩容 (HPA)

HPA 已配置在 `k8s-local/hpa.yaml` 和 `k8s-gke/hpa.yaml`：

- **FE**: 3-10 副本，CPU 70% 触发扩容
- **BECN**: 3-20 副本，CPU 70% 触发扩容

启用 HPA：

```bash
kubectl apply -f hpa.yaml
```

## 验证集群

```bash
# 查看 Pod 状态
kubectl get pods -n doris

# 查看 FE 日志
kubectl logs -n doris -l app.kubernetes.io/component=fe --tail=100

# 连接 MySQL
mysql -h <FE_IP> -P 9030 -u root

# 验证集群状态
SHOW FRONTENDS;
SHOW BACKENDS;
SHOW PROC '/frontends';
```

## 清理

**本地环境**:

```bash
cd k8s-local
./undeploy.sh
```

**GKE 环境**:

```bash
cd k8s-gke
./undeploy.sh
```

## 故障排查

### Pod 无法启动

```bash
# 查看事件
kubectl describe pod <pod-name> -n doris

# 查看日志
kubectl logs <pod-name> -n doris --previous
```

### 镜像拉取失败

```bash
# 检查 imagePullSecrets
kubectl get secret doris-registry -n doris

# 重新创建
kubectl create secret docker-registry doris-registry \
  --namespace=doris \
  --docker-server=localhost:5000 \
  --docker-username=admin \
  --docker-password=admin123
```

### 存储挂载问题

```bash
# 检查 PVC
kubectl get pvc -n doris

# 检查 StorageClass
kubectl get storageclass
```
