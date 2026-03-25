# Doris 存算分离架构本地 Kubernetes 部署指南

## 版本信息

- **Doris 版本**: 4.0.4
- **Doris Operator 版本**: 1.4.0
- **FoundationDB 版本**: 7.1.37
- **FDB Operator 版本**: 1.12.0

## 概述

本目录包含在本地 Kubernetes 环境中部署 **Doris 4.0.4 存算分离架构** 集群的配置和脚本。

### 部署架构

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Local Kubernetes                              │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                    DorisDisaggregatedCluster                  │   │
│  │                           v4.0.4                              │   │
│  │                                                              │   │
│  │  ┌──────────┐   ┌──────────┐   ┌──────────┐                │   │
│  │  │    FE    │   │    FE    │   │    FE    │  (3 副本)      │   │
│  │  │ Frontend │◄──│ Frontend │◄──│ Frontend │  (Query)      │   │
│  │  └────┬─────┘   └────┬─────┘   └────┬─────┘                │   │
│  │       │              │              │                        │   │
│  │       └──────────────┼──────────────┘                        │   │
│  │                      ▼                                       │   │
│  │               ┌────────────┐                                  │   │
│  │               │MetaService │ (3 副本)                        │   │
│  │               │ (FDB 存储) │                                  │   │
│  │               └─────┬──────┘                                  │   │
│  │                     │                                          │   │
│  │       ┌─────────────┼─────────────┐                           │   │
│  │       ▼             ▼             ▼                           │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐                       │   │
│  │  │   BECN   │ │   BECN   │ │   BECN   │  (N 副本)           │   │
│  │  │ Compute  │ │ Compute  │ │ Compute  │  (仅计算)           │   │
│  │  └────┬─────┘ └────┬─────┘ └────┬─────┘                       │   │
│  │       │            │            │                              │   │
│  │       └────────────┼────────────┘                              │   │
│  │                    ▼                                           │   │
│  │               ┌────────────┐                                   │   │
│  │               │   MinIO    │  (S3 兼容对象存储)                 │   │
│  │               └────────────┘                                   │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌─────────────────┐  ┌─────────────────┐                          │
│  │  FoundationDB   │  │     MinIO       │                          │
│  │  (元数据存储)    │  │   (数据存储)     │                          │
│  └─────────────────┘  └─────────────────┘                          │
└──────────────────────────────────────────────────────────────────────┘
```

### 组件说明

| 组件 | 副本数 | 镜像 | 说明 |
|------|--------|------|------|
| FE (Frontend) | 3 | `apache/doris:4.0.4-secure` | SQL 解析、查询规划、查询协调、元数据管理 |
| MetaService | 3 | `apache/doris:4.0.4-secure` | 存储层元数据 (Tablet 位置、副本信息)，使用 FDB 存储 |
| BECN | 3+ | `apache/doris:4.0.4-secure` | Backend Compute Node，数据计算，不存储数据 |
| MinIO | 1 | `minio/minio:latest` | S3 兼容对象存储，数据持久化 |
| FoundationDB | 3 | `foundationdb/foundationdb:7.1.37` | MetaService 的元数据存储 |
| Doris Operator | 1 | `apache/doris:operator-1.4.0` | 管理 DorisDisaggregatedCluster |
| FDB Operator | 1 | `fdb-kubernetes-operator:1.12.0` | 管理 FoundationDB 集群 |

### 自动扩容 (HPA)

| 组件 | 最小副本 | 最大副本 | CPU 阈值 | 内存阈值 |
|------|----------|----------|----------|----------|
| FE | 1 | 5 | 70% | 80% |
| BECN | 1 | 10 | 70% | 80% |
| MetaService | 1 | 5 | 70% | 80% |

## 前置条件

### 必需条件

- Docker Desktop 已启用 Kubernetes
- kubectl 已配置并连接到集群
- metrics-server 已安装 (用于 HPA)
- 资源需求: **16核CPU + 32GB内存**

### 本地镜像 (必须已加载)

```bash
# 拉取命令 (需要 Docker Hub 访问)
docker pull fdb-kubernetes-operator:1.12.0
docker pull foundationdb/foundationdb:7.1.37
docker pull apache/doris:4.0.4-secure
docker pull apache/doris:operator-1.4.0
docker pull minio/minio:latest
```

| 镜像 | 版本 | 用途 |
|------|------|------|
| `fdb-kubernetes-operator:1.12.0` | 1.12.0 | FDB Operator |
| `foundationdb/foundationdb:7.1.37` | 7.1.37 | FDB 数据库 |
| `apache/doris:4.0.4-secure` | 4.0.4 | FE/BE/MetaService (存算分离) |
| `apache/doris:operator-1.4.0` | 1.4.0 | Doris Operator |
| `minio/minio:latest` | latest | S3 兼容存储 |

### 安装 metrics-server (HPA 需要)

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

## 快速开始

### 部署

```bash
cd k8s-local-disaggregated
./deploy.sh
```

部署时间约 **15-20 分钟**，请耐心等待。

### 验证

```bash
# 检查 Pod 状态
kubectl get pods -n foundationdb
kubectl get pods -n doris

# 检查 Services
kubectl get svc -n doris
kubectl get svc -n foundationdb

# 检查 HPA
kubectl get hpa -n doris

# 查看 HPA 状态
kubectl describe hpa doris-becn-hpa -n doris
```

### 连接

```bash
# 获取节点 IP
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

# 连接 FE
mysql -h $NODE_IP -P 30632 -u root -p'root123456'

# 验证集群
SHOW FRONTENDS;
SHOW BACKENDS;
SHOW PROC '/frontends';
SHOW PROC '/backends';
```

### 卸载

```bash
./undeploy.sh
```

## 文件说明

| 文件 | 说明 |
|------|------|
| `deploy.sh` | 部署脚本 |
| `undeploy.sh` | 卸载脚本 |
| `namespace.yaml` | Namespace 定义 |
| `fdb-operator.yaml` | FDB Operator 部署 |
| `fdb-crd.yaml` | FDB CRD 定义 |
| `fdbcluster.yaml` | FDB 集群配置 |
| `minio.yaml` | MinIO 部署 |
| `doris-operator.yaml` | Doris Operator 部署 |
| `doris-crd.yaml` | Doris CRD 定义 |
| `doris-disaggregated-cluster.yaml` | DorisDisaggregatedCluster 配置 |
| `hpa.yaml` | HPA 配置 |
| `secret.yaml` | Secret 定义 |
| `configmap.yaml` | ConfigMap 定义 |

## 环境变量

部署时可通过环境变量覆盖默认配置：

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `DORIS_VERSION` | `4.0.4` | Doris 版本 |
| `FDB_OPERATOR_IMAGE` | `fdb-kubernetes-operator:1.12.0` | FDB Operator 镜像 |
| `FDB_IMAGE` | `foundationdb/foundationdb:7.1.37` | FDB 镜像 |
| `DORIS_IMAGE` | `apache/doris:4.0.4-secure` | Doris 镜像 |
| `OPERATOR_IMAGE` | `apache/doris:operator-1.4.0` | Doris Operator 镜像 |
| `MINIO_IMAGE` | `minio/minio:latest` | MinIO 镜像 |

示例：

```bash
DORIS_IMAGE=localhost:5000/doris:4.0.4-secure ./deploy.sh
```

## 端口说明

| 服务 | 类型 | 端口 | NodePort |
|------|------|------|----------|
| FE MySQL | NodePort | 9030 | 30632 |
| FE HTTP | NodePort | 8030 | 30389 |
| FE RPC | ClusterIP | 9010 | - |
| BECN | ClusterIP | 9060 | - |
| MetaService | ClusterIP | 5000 | - |
| MinIO API | NodePort | 9000 | 30000 |
| MinIO Console | NodePort | 9001 | 30001 |

## Doris 4.0.4 新特性

Doris 4.0.4 是存算分离架构的成熟版本，包含以下特性：

- **存算分离**: 计算节点无状态，数据存储在对象存储
- **弹性扩缩容**: 仅扩缩容计算节点，不影响数据
- **冷热分层**: 自动将冷数据卸载到对象存储
- **MetaService**: 高性能元数据管理，基于 FoundationDB

## 故障排查

### FDB 集群无法启动

```bash
# 查看 FDB Operator 日志
kubectl logs -n foundationdb -l app.kubernetes.io/component=operator --tail=50

# 查看 FDB 集群日志
kubectl logs -n foundationdb -l app.kubernetes.io/component=database --tail=50

# 检查 FDB 集群状态
kubectl get fdbcluster -n foundationdb
kubectl describe fdbcluster -n foundationdb fdb-cluster
```

### Doris Operator 无法启动

```bash
# 查看 Operator 日志
kubectl logs -n doris-operator-system -l app.kubernetes.io/name=doris-operator --tail=50

# 检查 CRD 是否正确部署
kubectl get crd | grep doris
```

### DorisDisaggregatedCluster 无法启动

```bash
# 查看各组件日志
kubectl logs -n doris -l app.kubernetes.io/component=fe --tail=50
kubectl logs -n doris -l app.kubernetes.io/component=becn --tail=50
kubectl logs -n doris -l app.kubernetes.io/component=meta-service --tail=50

# 检查 FDB 连接
kubectl exec -n foundationdb fdb-cluster-stateless-1 -- fdbcli --exec "status"
```

### HPA 不工作

```bash
# 检查 metrics-server
kubectl get pods -n kube-system -l k8s-app=metrics-server

# 查看 HPA 状态
kubectl describe hpa doris-becn-hpa -n doris

# 检查 Pod metrics
kubectl top pods -n doris
```

## 与传统架构对比

| 特性 | 传统架构 (FE+BE) | 存算分离架构 |
|------|------------------|--------------|
| 数据存储 | BE 本地磁盘 | MinIO (S3) |
| 扩缩容 | 需要数据迁移 | 仅扩缩容计算节点 |
| 成本优化 | - | 冷数据自动卸载到对象存储 |
| 故障恢复 | 较慢 | 快速（计算节点无状态） |
| 适用场景 | 小规模 | 大规模/弹性需求 |

## 下一步

- [Doris 官方文档](https://doris.apache.org/docs/)
- [Doris Operator 文档](https://github.com/apache/doris-operator)
- [FoundationDB 文档](https://foundationdb.com/)