# 部署指南

## 概述

本文档说明如何将安全加固的 Doris 部署到 GKE 集群。

## 前置条件

### 工具要求

- kubectl 1.28+
- gcloud CLI
- Docker 24.0+
- MySQL Client 8.0+ (用于连接测试)

### 权限要求

- GCP 项目访问权限
- GKE 集群管理权限
- Nexus Registry 访问权限

### 资源要求

| 组件 | 副本数 | CPU | 内存 | 存储 |
|------|--------|-----|------|------|
| FE | 3 | 4-8 核 | 8-16GB | 100GB x 3 |
| BE | 5-25 | 8-16 核 | 32-64GB | 1.5TB x 5+ |
| FDB | 3 | 2-4 核 | 4-8GB | 100GB x 3 |

## 部署流程

### 阶段 1: 准备镜像

```bash
# 1. 构建镜像
./scripts/build-images.sh all

# 2. 扫描安全漏洞
./scripts/scan-images.sh all

# 3. 确认无高危漏洞
cat reports/security-scan-report.txt

# 4. 推送到 Nexus
export NEXUS_PASS="your-password"
./scripts/push-to-nexus.sh all
```

### 阶段 2: 准备 GKE 集群

```bash
# 配置 gcloud
gcloud config set project your-project-id

# 获取集群凭证
gcloud container clusters get-credentials doris-prod \
    --region us-central1 \
    --project your-project-id

# 验证连接
kubectl cluster-info
kubectl get nodes
```

### 阶段 3: 创建命名空间和 Secret

```bash
# 创建命名空间
kubectl apply -f kubernetes/namespace.yaml

# 创建 Nexus Secret
kubectl create secret docker-registry nexus-secret \
    --docker-server=nexus.company.com:8082 \
    --docker-username=admin \
    --docker-password=your-password \
    -n doris
```

### 阶段 4: 部署存储

```bash
# 创建存储类
kubectl apply -f kubernetes/storage/storage-class.yaml

# 验证
kubectl get storageclass
```

### 阶段 5: 部署 FoundationDB

```bash
kubectl apply -f kubernetes/doris-cluster/fdb.yaml

# 等待就绪
kubectl wait --for=condition=ready pod -l app=fdb -n doris --timeout=300s
```

### 阶段 6: 部署 Doris FE

```bash
kubectl apply -f kubernetes/doris-cluster/fe.yaml

# 等待就绪 (FE 启动较慢)
sleep 60
kubectl wait --for=condition=ready pod -l app=fe -n doris --timeout=600s
```

### 阶段 7: 部署 Doris BE

```bash
kubectl apply -f kubernetes/doris-cluster/be.yaml

# 等待就绪
sleep 60
kubectl wait --for=condition=ready pod -l app=be -n doris --timeout=600s || true
```

### 阶段 8: 验证部署

```bash
# 检查 Pod 状态
kubectl get pods -n doris -o wide

# 检查服务
kubectl get services -n doris

# 连接测试
FE_IP=$(kubectl get svc fe-lb -n doris -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
mysql -h $FE_IP -P 9030 -u root
```

## 一键部署

```bash
# 使用部署脚本
./scripts/deploy.sh
```

## 配置说明

### FE 配置

编辑 `kubernetes/doris-cluster/fe.yaml` 中的 ConfigMap：

```yaml
data:
  fe.conf: |
    # 内存配置
    JAVA_OPTS = "-Xmx8g -Xms8g -Xmn4g"
    
    # 网络配置
    priority_networks = 10.0.0.0/16
    
    # 其他配置...
```

### BE 配置

编辑 `kubernetes/doris-cluster/be.yaml` 中的 ConfigMap：

```yaml
data:
  be.conf: |
    # 存储配置
    storage_root_path = /mnt/local-ssd,/mnt/gcs-cold-storage
    
    # 性能配置
    streaming_load_max_mb = 10240
    
    # 其他配置...
```

### 资源调整

修改 StatefulSet 中的 resources：

```yaml
resources:
  limits:
    cpu: 16
    memory: 64Gi
  requests:
    cpu: 8
    memory: 32Gi
```

## 扩缩容

### 手动扩容 BE

```bash
kubectl scale statefulset be -n doris --replicas=10
```

### 配置 HPA (可选)

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: be-hpa
  namespace: doris
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: StatefulSet
    name: be
  minReplicas: 5
  maxReplicas: 25
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

## 监控和日志

### 查看日志

```bash
# FE 日志
kubectl logs -f statefulset/fe -n doris

# BE 日志
kubectl logs -f statefulset/be -n doris

# 特定 Pod 日志
kubectl logs -f fe-0 -n doris
```

### 查看事件

```bash
kubectl get events -n doris --sort-by='.lastTimestamp'
```

## 故障排查

### Pod 无法启动

```bash
# 查看 Pod 状态
kubectl describe pod <pod-name> -n doris

# 查看日志
kubectl logs <pod-name> -n doris

# 检查事件
kubectl get events -n doris --field-selector involvedObject.name=<pod-name>
```

### 镜像拉取失败

```bash
# 检查 Secret
kubectl get secret nexus-secret -n doris -o yaml

# 测试 Nexus 连接
curl -u admin:password http://nexus.company.com:8082/v2/_catalog
```

### 服务无法访问

```bash
# 检查 Service
kubectl get svc -n doris
kubectl describe svc fe-lb -n doris

# 检查端点
kubectl get endpoints -n doris
```

## 升级

### 滚动升级

```bash
# 更新镜像版本
kubectl set image statefulset/fe fe=nexus.company.com:8082/doris/fe:3.1.5-secure -n doris

# 查看升级状态
kubectl rollout status statefulset/fe -n doris
```

### 回滚

```bash
# 查看历史
kubectl rollout history statefulset/fe -n doris

# 回滚
kubectl rollout undo statefulset/fe -n doris
```

## 备份和恢复

### 备份

```bash
# 备份 GCS 数据
gsutil -m cp -r gs://doris-prod-cold-storage gs://doris-backup/

# 备份 FDB
kubectl exec -n doris fdb-0 -- fdbbackup start -d file:///backup
```

### 恢复

```bash
# 从备份恢复
# 参考 Doris 官方文档
```

## 安全建议

1. **网络隔离**: 使用 VPC 和防火墙规则
2. **访问控制**: 配置 RBAC 和 NetworkPolicy
3. **审计日志**: 启用 Kubernetes 审计日志
4. **定期更新**: 及时应用安全补丁

## 相关文档

- [安全加固指南](SECURITY-HARDENING.md)
- [构建指南](BUILD-GUIDE.md)
- [漏洞修复记录](VULNERABILITY-FIXES.md)
