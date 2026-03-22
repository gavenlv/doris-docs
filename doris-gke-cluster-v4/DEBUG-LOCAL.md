# Doris 本地 Kubernetes 调试记录

## 环境信息

| 项目 | 值 |
|------|-----|
| 操作系统 | Windows 11 (win32) |
| Shell | PowerShell |
| Kubernetes | Docker Desktop (v1.34.1) |
| Doris Operator | v25.8.0 |
| Doris 版本 | 3.1.4 |

## 成功部署记录

**部署时间**: 2026-03-22

### 部署结果

| 组件 | Pod | 状态 | 角色 |
|------|-----|------|------|
| FE | doriscluster-local-fe-0 | Running | Master |
| BE | doriscluster-local-be-0 | Running | Alive |

### 连接信息

| 服务 | 类型 | 端口映射 | 地址 |
|------|------|----------|------|
| FE HTTP | NodePort | 8030:30389 | 192.168.65.3:30389 |
| FE MySQL | NodePort | 9030:30632 | 192.168.65.3:30632 |
| BE | ClusterIP | - | doriscluster-local-be-service.doris |

## 问题与解决方案

### 问题 1：Operator 入口点错误

**现象**：
```
[ERROR] [Entrypoint]: Missing required parameters. Please check documentation.
```

**原因**：
Operator 镜像入口点配置错误，使用了 `/manager` 而非 `/dorisoperator`

**解决方案**：
在 `operator.yaml` 中修正 command:
```yaml
command: ["/opt/dorisoperator"]
args: ["--health-probe-bind-address=:8081"]
```

---

### 问题 2：CRD API 版本不匹配

**现象**：
```
no matches for kind "DorisCluster" in version "doris.apache.com/v1"
```

**原因**：
Doris Operator v2.x 使用 `doris.selectdb.com/v1` API 版本

**解决方案**：
更新 `doriscluster.yaml`:
```yaml
apiVersion: doris.selectdb.com/v1
kind: DorisCluster
```

---

### 问题 3：YAML 结构错误

**现象**：
```
error: error parsing ... invalidate...
```

**原因**：
`doriscluster.yaml` 中有重复的 `spec:` 字段

**解决方案**：
重写 YAML 结构，确保各资源定义正确分离

---

### 问题 4：Operator 权限不足

**现象**：
```
doriscluster.doris.selectdb.com is forbidden
```

**原因**：
ClusterRole 权限配置不完整

**解决方案**：
添加完整的 ClusterRole 权限 (参考 operator.yaml)

---

### 问题 5：存储类不存在

**现象**：
```
no storage class available
```

**原因**：
Docker Desktop 没有默认 StorageClass

**解决方案**：
使用 emptyDir 存储替代 PVC (开发环境):
```yaml
volumes:
  emptyDir: {}
```

---

### 问题 6：FE 配置文件只读

**现象**：
```
/opt/apache-doris/fe_entrypoint.sh: line 306: /opt/apache-doris/fe/conf/fe.conf: Read-only file system
```

**原因**：
ConfigMap 挂载为只读，但入口脚本需要修改 `fe.conf`

**解决方案**：
移除 `configMapInfo` 配置，让 FE 使用镜像内默认配置（可写）:
```yaml
feSpec:
  # 不使用 ConfigMap，使用镜像默认配置
  # configMapInfo:
  #   configMapName: fe-config
  #   resolveKey: fe.conf
```

---

## 调试步骤

### 1. 检查 Kubernetes 环境

```powershell
# 检查 kubectl 版本
kubectl version --client

# 检查集群状态
kubectl cluster-info

# 检查节点
kubectl get nodes -o wide
```

### 2. 部署 Operator

```powershell
# 部署 Operator (包含 CRD 和 RBAC)
kubectl apply -f k8s-local/operator.yaml

# 验证 Operator 运行
kubectl get pods -n doris-operator-system
```

### 3. 创建命名空间

```powershell
kubectl apply -f k8s-local/00-namespace.yaml
```

### 4. 部署 DorisCluster

```powershell
kubectl apply -f k8s-local/doriscluster.yaml

# 查看 pods 状态
kubectl get pods -n doris -w
```

### 5. 验证集群

```powershell
# 查看 FE 日志
kubectl logs doriscluster-local-fe-0 -n doris

# 查看 BE 日志
kubectl logs doriscluster-local-be-0 -n doris

# 查看 Service
kubectl get svc -n doris
```

### 6. 连接集群

Docker Desktop 环境使用 NodePort:

```powershell
# 获取节点 IP
$nodeIp = kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}'

# 使用 Docker 容器连接 MySQL
docker run --rm mysql:8 bash -c "mysql -h $nodeIp -P 30632 -u root -e 'SHOW FRONTENDS'"
```

## 常见问题

### Q1: Pod 一直 CrashLoopBackOff

**排查步骤**：
```powershell
# 查看当前日志
kubectl logs <pod-name> -n doris --previous

# 查看 Pod 详情
kubectl describe pod <pod-name> -n doris

# 查看事件
kubectl get events -n doris --sort-by='.lastTimestamp'
```

### Q2: 端口访问失败

**检查**：
```powershell
# 确认 NodePort
kubectl get svc -n doris

# 测试连通性
telnet <节点IP> 30632
```

### Q3: FE 无法连接 BE

**检查**：
```sql
-- 在 FE MySQL 中执行
SHOW FRONTENDS;
SHOW BACKENDS;
SHOW PROC '/backends';
```

## 验证命令

```sql
-- 连接后执行
SHOW FRONTENDS;
SHOW BACKENDS;
SHOW CLUSTER;
```

## 生产注意事项

1. **存储**：当前使用 EmptyDir，数据会丢失。生产环境需要 PVC
2. **资源**：根据负载调整 CPU 和内存配置
3. **副本数**：生产环境 FE/BE 建议 3+ 副本
4. **访问方式**：生产环境使用 LoadBalancer 或 Ingress

## 相关文件

| 文件 | 说明 |
|------|------|
| `k8s-local/00-namespace.yaml` | 命名空间定义 |
| `k8s-local/operator.yaml` | Operator 部署配置 |
| `k8s-local/doriscluster.yaml` | DorisCluster 资源定义 |
| `k8s-gke/` | GKE 生产配置目录 |