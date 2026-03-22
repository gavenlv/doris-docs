# Doris GKE 生产环境部署

本目录包含在 Google Kubernetes Engine (GKE) 上部署生产级 Doris 集群的配置。

## 架构

```
                              ┌─────────────────────────────────────────────────────────┐
                              │                      GKE Cluster                        │
                              │                                                         │
┌──────────────┐              │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │
│   Internet   │──────────────│  │  doris-fe-0 │  │  doris-fe-1 │  │  doris-fe-2 │    │
│              │              │  │    (FE)     │  │    (FE)     │  │    (FE)     │    │
└──────────────┘              │  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘    │
                              │         │                │                │           │
                              │         └────────────────┼────────────────┘           │
                              │                          │                            │
                              │         ┌────────────────┴────────────────┐           │
                              │         │                             │           │
                              │  ┌──────▼──────┐  ┌─────────────┐  ┌─────────────┐ │
                              │  │  doris-be-0 │  │  doris-be-1 │  │  doris-be-2 │ │
                              │  │    (BE)     │  │    (BE)     │  │    (BE)     │ │
                              │  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘ │
                              │         │                │                │         │
                              │         └────────────────┼────────────────┘         │
                              │                          │                          │
                              │  ┌────────────────────────▼────────────────────────┐ │
                              │  │              GCE Persistent Disk                │ │
                              │  │     (Regional PD - SSD for BE, Standard for FE) │ │
                              │  └─────────────────────────────────────────────────┘ │
                              │                                                         │
                              └─────────────────────────────────────────────────────────┘
```

## 生产级特性

### 高可用

- **FE**: 3 副本 + LoadBalancer + PodDisruptionBudget
- **BE**: 3 副本 + PodDisruptionBudget
- **Regional PD**: 跨区域数据保护

### 性能优化

- **FE**: 4-8 核 / 16-32 GiB
- **BE**: 8-16 核 / 32-64 GiB
- **SSD 存储**: BE 数据盘使用 SSD

### 安全

- NetworkPolicy 限制组件间通信
- Secret 管理敏感信息
- TLS 加密 (Ingress)

### 监控

- Prometheus + Grafana 集成
- ServiceMonitor 自动服务发现
- 告警规则

### 自动扩缩容

- HPA 基于 CPU/内存
- BE 支持 3-20 副本

### 备份

- 定时快照备份到 GCS
- 自动清理过期备份

## 组件配置

### Frontend (FE)

| 配置 | 值 |
|------|-----|
| 副本数 | 3 |
| CPU | 4-8 核 |
| 内存 | 16-32 GiB |
| 元数据存储 | 50 GiB SSD |
| 日志存储 | 20 GiB Standard |
| Service | LoadBalancer |

### Backend (BE)

| 配置 | 值 |
|------|-----|
| 副本数 | 3 |
| CPU | 8-16 核 |
| 内存 | 32-64 GiB |
| 数据存储 | 500 GiB SSD |
| 日志存储 | 50 GiB Standard |
| Service | LoadBalancer |

## 快速开始

### 前提条件

```bash
# 安装 gcloud CLI
curl https://sdk.cloud.google.com | bash
gcloud init

# 设置项目
gcloud config set project YOUR_PROJECT_ID

# 启用 GKE API
gcloud services enable container.googleapis.com
```

### 配置环境变量

```bash
export PROJECT_ID="your-gcp-project"
export CLUSTER_NAME="doris-cluster"
export REGION="us-central1"
```

### 部署集群

```bash
cd k8s-gke

# 部署
./deploy.sh
```

### 访问集群

```bash
# 获取 FE IP
FE_IP=$(kubectl get svc -n doris doriscluster-fe-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# 连接 MySQL
mysql -h $FE_IP -P9030 -uroot -p'your_password'

# Web UI
open http://$FE_IP:8030
```

## 配置文件

| 文件 | 说明 |
|------|------|
| `00-namespace.yaml` | 命名空间, StorageClass, PVC |
| `configmap.yaml` | FE 配置文件 |
| `configmap-be.yaml` | BE 配置文件 |
| `doriscluster.yaml` | DorisCluster 资源定义 |
| `services.yaml` | Ingress 和 BackendConfig |
| `hpa.yaml` | 自动扩缩容配置 |
| `network-policy.yaml` | 网络策略 |
| `monitoring.yaml` | Prometheus 监控 |
| `backup.yaml` | 定时备份任务 |
| `secret.yaml` | Secret 配置 |

## 生产检查清单

- [ ] 使用私有镜像仓库
- [ ] 配置 TLS 证书
- [ ] 设置强密码
- [ ] 配置 VPC 和网络策略
- [ ] 启用自动备份
- [ ] 配置监控和告警
- [ ] 测试故障恢复
- [ ] 文档化运维流程

## 扩展

### 添加 Compute Node

```yaml
# 在 doriscluster.yaml 中添加
cnSpec:
  replicas: 3
  image: apache/doris:be-3.1.4
  resources:
    requests:
      cpu: "8"
      memory: "32Gi"
```

### 使用对象存储

```yaml
beSpec:
  envVars:
    - name: BE_CONF_PATH
      value: "/opt/doris/be/storage"
    - name: BE_CONF_S3_path
      value: "s3://your-bucket/doris-data"
```

## 故障排除

```bash
# 查看 pods 状态
kubectl get pods -n doris

# 查看日志
kubectl logs -n doris doriscluster-fe-0 -c fe

# 查看事件
kubectl describe pod -n doris doriscluster-fe-0

# 进入容器
kubectl exec -it -n doris doriscluster-fe-0 -c fe -- bash
```

## 参考

- [Doris Operator 官方文档](https://github.com/apache/doris-operator)
- [GKE 文档](https://cloud.google.com/kubernetes-engine/docs)
- [Doris 官方文档](https://doris.apache.org)
