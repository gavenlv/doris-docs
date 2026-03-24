# Doris Local Kubernetes 配置 (Docker Desktop)

本目录包含在本地 Docker Desktop Kubernetes 环境中部署 Doris 存算分离集群的配置。

## 架构

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Docker Desktop K8s                                │
│                                                                      │
│  ┌───────────────────────────────────────────────────────────────┐   │
│  │                 doris-operator-system                           │   │
│  │                    (Doris Operator 1.4.0)                     │   │
│  └───────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌───────────────────────────────────────────────────────────────┐   │
│  │                     foundationdb                                 │   │
│  │  ┌─────────────────┐    ┌─────────────────┐                  │   │
│  │  │  fdb-cluster-0  │    │  minio-0        │                  │   │
│  │  │  (FDB 7.1.37)  │    │  (MinIO)       │                  │   │
│  │  └─────────────────┘    └─────────────────┘                  │   │
│  │        MetaDB                    S3 Storage                    │   │
│  └───────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌───────────────────────────────────────────────────────────────┐   │
│  │                        doris                                    │   │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐ │   │
│  │  │  doris-disagg-  │  │  doris-disagg-  │  │  doris-     │ │   │
│  │  │  cluster-fe-*   │  │  cluster-becn-* │  │  disagg-    │ │   │
│  │  │    (FE x 3)     │◄─┤    (BECN x 3)  │  │  cluster-   │ │   │
│  │  │                 │  │                 │  │  meta-      │ │   │
│  │  └─────────────────┘  └─────────────────┘  │  service-*  │ │   │
│  │                                           └─────────────┘ │   │
│  └───────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

## 组件说明

### 存算分离架构

| 组件 | 说明 | 副本数 | 资源 |
|------|------|--------|------|
| FE | Frontend, SQL 解析/查询协调 | 3 | 1-2 CPU, 4-8Gi |
| BECN | Backend Compute Node, 仅计算 | 3 | 2-4 CPU, 8-16Gi |
| MetaService | 存算分离元数据服务 | 3 | 1 CPU, 2-4Gi |
| FoundationDB | MetaService 的底层存储 | 1 | 0.5-1 CPU, 1-2Gi |
| MinIO | S3 兼容对象存储 | 1 | 0.25-1 CPU, 0.5-1Gi |

## 快速开始

### 前提条件

- Docker Desktop with Kubernetes 已启用
- kubectl 已安装并配置
- 资源: 建议 8+ 核 CPU, 16+ GiB 内存
- Docker 镜像已构建 (参考 build-tools/)

### 部署

```bash
cd k8s-local

# 方式 1: 使用一键部署脚本
./deploy.sh

# 方式 2: 手动部署
# 1. 部署 Doris Operator (包含 CRD)
kubectl apply -f operator.yaml

# 2. 等待 Operator 就绪
kubectl wait --for=condition=Ready pods -n doris-operator-system -l app.kubernetes.io/name=doris-operator --timeout=180s

# 3. 部署 FoundationDB Operator
kubectl apply -f fdb-operator.yaml

# 4. 部署 FoundationDB 集群
kubectl apply -f fdbcluster.yaml

# 5. 部署 MinIO
kubectl apply -f minio-statefulset.yaml

# 6. 部署 Doris 存算分离集群
kubectl apply -f 00-namespace.yaml
kubectl apply -f secret.yaml
kubectl apply -f configmap.yaml
sed -e 's|\${NEXUS_REGISTRY}|localhost:5000/doris|g' doris-disaggregated-cluster.yaml | kubectl apply -f -
```

### 验证部署

```bash
# 查看 Pod 状态
kubectl get pods -n doris
kubectl get pods -n foundationdb

# 查看 Services
kubectl get svc -n doris
kubectl get svc -n foundationdb

# 获取节点 IP
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo "Node IP: $NODE_IP"
```

### 访问集群

```bash
# FE MySQL 连接 (NodePort)
mysql -h <节点IP> -P 30632 -u root

# MinIO Console
# http://<节点IP>:30090
# 账号: minioadmin / minioadmin
```

### 验证集群状态

```sql
-- 查看 FE 状态
SHOW FRONTENDS;

-- 查看 BE 状态
SHOW BACKENDS;

-- 查看详细状态
SHOW PROC '/frontends';
SHOW PROC '/backends';
```

### 卸载

```bash
cd k8s-local

# 方式 1: 使用脚本 (会提示确认)
./undeploy.sh

# 方式 2: 手动卸载
kubectl delete -f doris-disaggregated-cluster.yaml
kubectl delete -f minio-statefulset.yaml
kubectl delete -f fdbcluster.yaml
kubectl delete -f fdb-operator.yaml
kubectl delete -f operator.yaml
kubectl delete namespace doris foundationdb
kubectl delete -f 00-namespace.yaml
```

## 配置文件说明

| 文件 | 说明 |
|------|------|
| `00-namespace.yaml` | 命名空间、StorageClass、RBAC 定义 |
| `operator.yaml` | Doris Operator 部署配置 (含 CRD) |
| `fdb-operator.yaml` | FoundationDB Operator 配置 |
| `fdbcluster.yaml` | FoundationDB 集群定义 |
| `minio-statefulset.yaml` | MinIO StatefulSet + Service |
| `doris-disaggregated-cluster.yaml` | DorisDisaggregatedCluster CRD |
| `configmap.yaml` | FE/BE 配置文件 |
| `secret.yaml` | MinIO 凭证 Secret |
| `hpa.yaml` | HorizontalPodAutoscaler 配置 |
| `deploy.sh` | 一键部署脚本 |
| `undeploy.sh` | 卸载脚本 |

## HPA 自动扩缩容

### FE HPA

```yaml
minReplicas: 3
maxReplicas: 10
metrics:
  - cpu: 70%
  - memory: 80%
```

### BECN HPA

```yaml
minReplicas: 3
maxReplicas: 20
metrics:
  - cpu: 70%
  - memory: 80%
```

### 查看 HPA 状态

```bash
kubectl get hpa -n doris
kubectl describe hpa doris-fe-hpa -n doris
```

## 端口映射

| 服务 | 内部端口 | NodePort | 说明 |
|------|----------|----------|------|
| FE MySQL | 9030 | 30632 | SQL 连接 |
| FE HTTP | 8030 | 30389 | Web UI |
| FE RPC | 9010 | 32280 | FE 间通信 |
| MinIO API | 9000 | 30000 | S3 API |
| MinIO Console | 9001 | 30090 | Web Console |

## 常见问题

### 1. Operator 启动失败

```bash
# 检查 Operator 状态
kubectl get pods -n doris-operator-system
kubectl logs -n doris-operator-system -l app.kubernetes.io/name=doris-operator

# 常见问题: 镜像拉取失败
# 确保镜像已构建并推送到 Nexus
docker images | grep doris
```

### 2. FDB 集群启动缓慢

```bash
# FDB 初始化可能需要 5-10 分钟
kubectl get fdbcluster -n foundationdb
kubectl logs -n foundationdb -l app.kubernetes.io/name=foundationdb --tail=100
```

### 3. FE/BE 启动失败

```bash
# 查看日志
kubectl logs -n doris -l app.kubernetes.io/component=fe --tail=100
kubectl logs -n doris -l app.kubernetes.io/component=becn --tail=100

# 检查 events
kubectl get events -n doris --sort-by='.lastTimestamp'
```

### 4. 存储挂载问题

```bash
# 确认 StorageClass 存在
kubectl get storageclass

# 确认 PVC 状态
kubectl get pvc -n doris
kubectl get pvc -n foundationdb
```

## 生产环境注意事项

1. **资源**: 增加 FE/BECN 副本数到 3+
2. **高可用**: 3 副本满足 Raft 协议要求
3. **存储**: 使用云存储 (GCE PD / AWS EBS) 替代 host-path
4. **监控**: 配置 Prometheus + Grafana
5. **网络**: 使用 LoadBalancer 替代 NodePort

## 扩展阅读

- [Doris Operator 官方文档](https://github.com/apache/doris-operator)
- [Doris 存算分离架构](https://doris.apache.org/zh-CN/docs/data-lake/doris-storage-compute-separation)
- [FoundationDB 官方文档](https://apple.github.io/foundationdb/)
- [MinIO 官方文档](https://min.io/docs)
