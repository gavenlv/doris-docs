# Doris 本地 Kubernetes 调试记录

## 环境信息

- **操作系统**: Windows 11 (win32)
- **Shell**: PowerShell
- **Kubernetes**: Docker Desktop (v1.34.1)
- **Doris Operator**: v25.8.0
- **Doris 版本**: 3.1.4

## 调试过程

### 1. 问题发现

**问题**: 现有的 `zlsmshoqvwt6q1.xuanyuan.run/apache/doris:fe-4.0.2` 镜像是为 Kubernetes + Doris Operator 设计的，不能直接使用 `docker run` 或普通 K8s Deployment 启动。

**错误信息**:
```
[ERROR] [Entrypoint]: Missing required parameters. Please check documentation.
```

### 2. 解决方案

使用 **Doris Operator** 来管理 Doris 集群。

#### 2.1 安装 Doris Operator

```bash
# 1. 安装 CRD
kubectl create -f https://raw.githubusercontent.com/apache/doris-operator/25.8.0/config/crd/bases/doris.apache.com_dorisclusters.yaml

# 2. 安装 Operator
kubectl apply -f https://raw.githubusercontent.com/apache/doris-operator/25.8.0/config/operator/operator.yaml

# 3. 验证 Operator 状态
kubectl get pods -n doris
```

#### 2.2 创建 DorisCluster

```bash
kubectl apply -f kubernetes/doris-cluster-local/doriscluster-local.yaml
```

### 3. 访问集群

```bash
# 端口转发
kubectl port-forward -n doris svc/doriscluster-local-fe-service 8030:8030 9030:9030

# 连接
mysql -h127.0.0.1 -P9030 -uroot
```

### 4. 验证集群状态

```sql
SHOW FRONTENDS;
SHOW BACKENDS;
SHOW CLUSTER;
```

## 常见问题

### Q1: 镜像拉取失败

**问题**: `zlsmshoqvwt6q1.xuanyuan.run/apache/doris:*` 镜像需要私有仓库认证

**解决**: 使用公共镜像 `apache/doris:*`

### Q2: Pod 一直 CrashLoopBackOff

**原因**: 直接使用 Deployment 而非 DorisCluster，缺少必需的环境变量和配置

**解决**: 使用 Doris Operator 管理的 DorisCluster 资源

### Q3: 端口转发断开

**解决**: 使用后台进程或 Kubernetes Service NodePort 模式

## 生产注意事项

1. **存储**: 当前配置使用 EmptyDir，数据会丢失。生产环境需要配置 PVC
2. **资源**: 根据实际负载调整 CPU 和内存配置
3. **副本数**: 生产环境 FE 建议 3 副本，BE 建议 3+ 副本
4. **高可用**: 配置 Service 使用 NodePort 或 LoadBalancer 模式
