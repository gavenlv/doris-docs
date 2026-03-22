# Doris Local Kubernetes 配置 (Docker Desktop)

本目录包含在本地 Docker Desktop Kubernetes 环境中部署 Doris 集群的配置。

## 架构

```
┌─────────────────────────────────────────────────────────────┐
│                    Docker Desktop K8s                        │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                 doris-operator-system                 │   │
│  │                    (Operator)                         │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                     doris                             │   │
│  │                                                      │   │
│  │   ┌─────────────────┐    ┌─────────────────┐        │   │
│  │   │  doriscluster-  │    │  doriscluster-  │        │   │
│  │   │  local-fe-0     │    │  local-be-0     │        │   │
│  │   │    (FE)         │◄──►│    (BE)         │        │   │
│  │   │  NodePort:30632 │    │  ClusterIP       │        │   │
│  │   └─────────────────┘    └─────────────────┘        │   │
│  │                                                      │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## 组件配置

### Frontend (FE)

- **副本数**: 1 (开发环境)
- **镜像**: apache/doris:fe-3.1.4
- **CPU/内存**: 1-2 核 / 4-8 GiB
- **存储**: emptyDir (开发环境，数据重启后丢失)
- **端口**:
  - HTTP: 8030 (NodePort: 30389)
  - MySQL: 9030 (NodePort: 30632)
  - REPL: 9010 (NodePort: 32280)
  - RPC: 9020 (NodePort: 30356)

### Backend (BE)

- **副本数**: 1 (开发环境)
- **镜像**: apache/doris:be-3.1.4
- **CPU/内存**: 2-4 核 / 8-16 GiB
- **存储**: emptyDir (开发环境，数据重启后丢失)
- **端口**:
  - HTTP: 8040
  - Heartbeat: 9050
  - Arrow Flight: 8060

## 快速开始

### 前提条件

- Docker Desktop with Kubernetes 已启用
- kubectl 已安装并配置
- 资源: 建议 4+ 核 CPU, 16+ GiB 内存

### 部署

```bash
cd k8s-local

# 部署顺序:
# 1. 部署 Operator (包含 CRD)
kubectl apply -f operator.yaml

# 2. 等待 Operator 就绪
kubectl wait --for=condition=Ready pods -n doris-operator-system -l app.kubernetes.io/name=doris-operator --timeout=180s

# 3. 创建 namespace
kubectl apply -f 00-namespace.yaml

# 4. 部署 DorisCluster
kubectl apply -f doriscluster.yaml

# 查看状态
kubectl get pods -n doris
```

### 访问集群

```bash
# 获取 Docker Desktop 节点 IP
kubectl get nodes -o wide

# FE MySQL 连接 (使用 NodePort)
mysql -h <节点IP> -P 30632 -u root

# 示例 (Docker Desktop)
mysql -h 192.168.65.3 -P 30632 -u root
```

### 验证集群

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
# 删除 DorisCluster
kubectl delete -f doriscluster.yaml

# 删除 Operator (如需)
kubectl delete -f operator.yaml

# 删除 namespace
kubectl delete -f 00-namespace.yaml
```

## 配置文件说明

| 文件 | 说明 |
|------|------|
| `00-namespace.yaml` | 命名空间定义 |
| `operator.yaml` | Doris Operator 部署配置 |
| `doriscluster.yaml` | DorisCluster 资源定义 (FE + BE) |
| `configmap.yaml` | FE/BE 配置文件 (可选) |
| `secret.yaml` | 密钥配置 |
| `deploy.sh` | 一键部署脚本 |
| `undeploy.sh` | 卸载脚本 |

## 部署流程

1. **部署 Operator**
   - 自动创建 `doris-operator-system` 命名空间
   - 部署 CRD (CustomResourceDefinition)
   - 部署 Operator Pod

2. **创建 doris 命名空间**
   - 创建应用命名空间

3. **部署 DorisCluster**
   - 创建 FE StatefulSet (1副本)
   - 创建 BE StatefulSet (1副本)
   - 创建 FE/BE Service

4. **等待就绪**
   - FE 启动约需 3-5 分钟
   - BE 启动约需 2-3 分钟

## 常见问题

### FE 启动失败 (CrashLoopBackOff)

**问题**: fe.conf 只读文件系统错误

**原因**: ConfigMap 挂载为只读，但入口脚本需要修改配置

**解决**: 不使用 configMapInfo 配置，让 FE 使用镜像内默认配置

### 连接被拒绝

**检查**:
```bash
# 查看 FE 日志
kubectl logs -n doris doriscluster-local-fe-0

# 查看 Pod 状态
kubectl get pods -n doris

# 查看 Service
kubectl get svc -n doris
```

### 端口访问失败

Docker Desktop 环境使用 NodePort 访问:
```bash
# 获取外部可访问的 IP (通常是 docker-desktop 节点的 IP)
kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}'

# 使用 NodePort 端口连接
mysql -h <节点IP> -P 30632 -u root
```

## 生产环境注意事项

1. **资源**: 增加 FE/BE 副本数 (建议 3+)
2. **存储**: 使用 PVC 或远程存储替代 emptyDir
3. **高可用**: FE/BE 各 3 副本确保高可用
4. **监控**: 建议配置 Prometheus + Grafana 监控

## 扩展阅读

- [Doris Operator 官方文档](https://github.com/apache/doris-operator)
- [Doris 官方文档](https://doris.apache.org)
- [Debug 本地部署](./DEBUG-LOCAL.md)