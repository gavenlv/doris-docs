# Doris Kubernetes 部署项目

本项目包含在 Kubernetes 环境中部署 Apache Doris 集群的配置，支持本地开发测试和生产环境。

## 目录结构

```
doris-gke-cluster-v4/
├── k8s-local/                    # 本地 Docker Desktop K8s 配置
│   ├── 00-namespace.yaml         # 命名空间定义
│   ├── operator.yaml             # Doris Operator 部署
│   ├── doriscluster.yaml         # DorisCluster 资源定义
│   ├── configmap.yaml            # FE/BE 配置（可选）
│   ├── secret.yaml               # 密钥配置
│   ├── deploy.sh                 # 部署脚本
│   ├── undeploy.sh               # 卸载脚本
│   └── README.md                 # 详细部署文档
│
├── k8s-gke/                      # Google GKE 生产配置
│   ├── 00-namespace.yaml         # 命名空间 + Regional PD Storage
│   ├── configmap.yaml            # FE 生产配置
│   ├── configmap-be.yaml         # BE 生产配置
│   ├── doriscluster.yaml         # 生产级 DorisCluster
│   ├── services.yaml             # Ingress + BackendConfig
│   ├── hpa.yaml                  # 自动扩缩容
│   ├── network-policy.yaml       # 网络策略
│   ├── monitoring.yaml          # Prometheus 监控
│   ├── backup.yaml               # 定时备份
│   ├── secret.yaml               # Secret 配置
│   ├── deploy.sh                 # 部署脚本
│   ├── undeploy.sh               # 卸载脚本
│   └── README.md
│
├── configs/                      # 配置文件
│   ├── build-config.yaml
│   └── nexus-config.yaml
│
├── DEBUG-LOCAL.md               # 本地部署调试记录
└── QUICK-START.md               # 快速开始
```

## 快速开始

### 本地开发 (Docker Desktop)

详见 [k8s-local/README.md](./k8s-local/README.md)

```bash
cd k8s-local

# 部署 Operator
kubectl apply -f operator.yaml

# 部署 DorisCluster
kubectl apply -f doriscluster.yaml

# 查看状态
kubectl get pods -n doris
```

### 生产部署 (GKE)

详见 [k8s-gke/README.md](./k8s-gke/README.md)

```bash
export PROJECT_ID="your-gcp-project"
export CLUSTER_NAME="doris-cluster"
export REGION="us-central1"

cd k8s-gke
./deploy.sh
```

## 版本信息

| 组件 | 版本 |
|------|------|
| Doris | 3.1.4 |
| Doris Operator | 25.8.0 |
| Kubernetes | 1.19+ |

## 本地部署要点

1. **无需 MinIO**: 开发环境使用 emptyDir 存储
2. **NodePort 访问**: Docker Desktop 使用 NodePort 而非 LoadBalancer
3. **1 副本**: 开发环境 FE/BE 各 1 副本节省资源
4. **默认配置**: 使用镜像内置配置，避免 ConfigMap 只读问题

## 故障排除

详见 [DEBUG-LOCAL.md](./DEBUG-LOCAL.md)

```bash
# 检查 pods
kubectl get pods -n doris

# 查看日志
kubectl logs -n doris <pod-name>

# 查看事件
kubectl get events -n doris --sort-by='.lastTimestamp'
```

## 参考

- [Doris Operator](https://github.com/apache/doris-operator)
- [Doris 官方文档](https://doris.apache.org)
- [GKE 文档](https://cloud.google.com/kubernetes-engine/docs)