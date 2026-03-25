# Doris 本地 Kubernetes 部署指南

## 概述

本目录包含在本地 Kubernetes 环境中部署 Apache Doris 集群的配置和脚本。

### 部署架构

```
┌─────────────────────────────────────────────────────────────┐
│                     Local Kubernetes                          │
│                                                             │
│  ┌─────────────────┐         ┌─────────────────┐          │
│  │   FoundationDB   │         │      Doris      │          │
│  │   (单节点测试)    │         │                 │          │
│  │                 │         │  ┌───────────┐  │          │
│  │  fdb-single     │         │  │    FE     │  │          │
│  │  Port: 4500     │         │  │  (1副本)  │  │          │
│  │                 │───────────│  Port: 9030 │  │          │
│  │                 │         │  └─────┬─────┘  │          │
│  │                 │         │        │        │          │
│  │                 │         │  ┌─────▼─────┐  │          │
│  │                 │         │  │    BE     │  │          │
│  │                 │         │  │  (1副本)  │  │          │
│  │                 │         │  │  Port:9060│  │          │
│  │                 │         │  └───────────┘  │          │
│  └─────────────────┘         └─────────────────┘          │
│                                                             │
│  Services:                                                  │
│    - doris-fe-service (NodePort: 32036->9030, 31993->8030)  │
│    - doris-be-service (ClusterIP: 9060)                     │
└─────────────────────────────────────────────────────────────┘
```

## 部署模式

本方案采用**简化部署**，不需要 Doris Operator 或 FDB Operator：

| 组件 | 部署方式 | 说明 |
|------|----------|------|
| FoundationDB | Pod (fdb-single) | 单节点测试用途 |
| Doris FE | Deployment | 传统 Deployment 方式 |
| Doris BE | Deployment | 传统 Deployment 方式 |

## 前置条件

- Docker Desktop 已启用 Kubernetes
- kubectl 已配置并连接到集群
- 资源需求: 4核CPU + 8GB内存
- 本地镜像已加载:
  - `apache/doris:fe-3.1.4`
  - `apache/doris:be-3.1.4`
  - `foundationdb/foundationdb:7.1.37`

## 快速开始

### 部署

```bash
cd k8s-local
./deploy.sh
```

### 验证

```bash
# 检查 Pod 状态
kubectl get pods -n doris
kubectl get pods -n foundationdb

# 检查 Services
kubectl get svc -n doris
```

### 连接

```bash
# 获取节点 IP
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

# 连接 FE
mysql -h $NODE_IP -P 32036 -u root

# 验证集群
SHOW FRONTENDS;
SHOW BACKENDS;
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
| `doris-traditional.yaml` | Doris FE + BE 部署配置 |
| `fdb-single.yaml` | FDB 单节点部署配置 |
| `fdb-crd.yaml` | FDB CRD 定义 |
| `00-namespace.yaml` | Namespace 定义 |

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `DORIS_FE_IMAGE` | `apache/doris:fe-3.1.4` | FE 镜像 |
| `DORIS_BE_IMAGE` | `apache/doris:be-3.1.4` | BE 镜像 |
| `FDB_IMAGE` | `foundationdb/foundationdb:7.1.37` | FDB 镜像 |

## 端口说明

| 服务 | 类型 | 内部端口 | NodePort |
|------|------|----------|----------|
| FE MySQL | NodePort | 9030 | 32036 |
| FE HTTP | NodePort | 8030 | 31993 |
| BE | ClusterIP | 9060 | - |
| FDB | ClusterIP | 4500 | - |

## 故障排查

### FE 无法启动

```bash
# 查看 FE 日志
kubectl logs -n doris deployment/doris-fe

# 检查环境变量是否正确
kubectl describe pod -n doris -l app=doris,component=fe
```

### BE 无法启动

```bash
# 查看 BE 日志
kubectl logs -n doris deployment/doris-be

# 检查 FE 是否就绪
kubectl get pod -n doris -l app=doris,component=fe
```

### FDB 无法启动

```bash
# 查看 FDB 日志
kubectl logs -n foundationdb fdb-single

# 检查 Pod 状态
kubectl get pod -n foundationdb fdb-single
```

## 下一步

- [Doris 官方文档](https://doris.apache.org/docs/)
- [Doris GitHub](https://github.com/apache/doris)