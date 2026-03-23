# Doris 部署与清理指南

本文档覆盖两种部署环境的完整部署和清理步骤。

---

## 目录

- [环境总览](#环境总览)
- [一、本地部署 (Docker Desktop)](#一本地部署-docker-desktop)
  - [部署步骤](#部署步骤)
  - [验证部署](#验证部署)
  - [连接集群](#连接集群)
  - [清理步骤](#清理步骤)
- [二、生产部署 (GKE)](#二生产部署-gke)
  - [部署步骤](#部署步骤-1)
  - [验证部署](#验证部署-1)
  - [连接集群](#连接集群-1)
  - [清理步骤](#清理步骤-1)
- [三、日常运维命令](#三日常运维命令)
- [四、故障排除](#四故障排除)
- [五、部署流程图](#五部署流程图)

---

## 环境总览

| 环境 | 适用场景 | FE/BE 副本 | 存储 | 访问方式 | 数据持久化 |
|------|----------|------------|------|----------|-----------|
| **k8s-local** | 本地开发/调试 | 1/1 | emptyDir | NodePort | 否（重启丢失） |
| **k8s-gke** | 生产环境 | 3/3 | Regional PD + GCS | LoadBalancer + Ingress | 是 |

### 版本矩阵

| 组件 | 版本 |
|------|------|
| Apache Doris | 3.1.4 |
| Doris Operator | 25.8.0 |
| Kubernetes | 1.19+（本地）/ 1.28+（GKE） |

---

## 一、本地部署 (Docker Desktop)

### 前置条件

| 条件 | 最低要求 | 推荐值 |
|------|----------|--------|
| Docker Desktop | 已启用 Kubernetes | 最新版 |
| kubectl | 已安装并配置 | v1.28+ |
| CPU | 4 核 | 8 核 |
| 内存 | 8 GiB | 16 GiB |
| 磁盘 | 20 GiB 可用 | 50 GiB |

### 部署步骤

#### 方式 A：一键部署脚本

```bash
cd k8s-local
./deploy.sh
```

脚本会自动完成以下步骤：
1. 检查 kubectl 和集群连通性
2. 部署 Doris Operator（含 CRD + RBAC）
3. 创建 `doris` 命名空间
4. 部署 DorisCluster（1 FE + 1 BE）
5. 询问是否部署 HPA 自动扩缩容
6. 输出访问信息

#### 方式 B：手动分步部署

```bash
cd k8s-local

# ---- 第 1 步：部署 Operator ----
# 包含 CRD、ServiceAccount、ClusterRole、ClusterRoleBinding、Deployment
# Operator 是 Doris 集群管理的核心控制器，必须先部署
kubectl apply -f operator.yaml

# 等待 Operator Pod 就绪（约 30-60 秒）
kubectl wait --for=condition=Ready pods \
  -n doris-operator-system \
  -l app.kubernetes.io/name=doris-operator \
  --timeout=180s

# ---- 第 2 步：创建命名空间 ----
kubectl apply -f 00-namespace.yaml

# ---- 第 3 步：部署 DorisCluster ----
# Operator 会自动创建 FE/BE 的 StatefulSet、Service、Pod
kubectl apply -f doriscluster.yaml

# ---- 第 4 步（可选）：部署 HPA 自动扩缩容 ----
# 需要 metrics-server 支持，否则 HPA 无法获取 CPU/内存指标
kubectl apply -f hpa.yaml

# ---- 第 5 步：等待集群就绪 ----
# FE 首次启动需要 3-5 分钟（元数据初始化）
# BE 启动需要 2-3 分钟
kubectl get pods -n doris -w
```

**预期输出**：
```
NAME                      READY   STATUS    RESTARTS   AGE
doriscluster-local-be-0   1/1     Running   0          5m
doriscluster-local-fe-0   1/1     Running   0          7m
```

### 验证部署

```bash
# 查看 Pod 状态
kubectl get pods -n doris -o wide

# 查看 Service 和端口映射
kubectl get svc -n doris

# 检查 HPA（如已部署）
kubectl get hpa -n doris
```

### 连接集群

```bash
# 获取节点 IP（Docker Desktop 通常是 192.168.65.x）
kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}'

# 通过 Docker 运行 MySQL 客户端连接
docker run --rm mysql:8 bash -c \
  "mysql -h 192.168.65.3 -P 30632 -u root -e 'SHOW FRONTENDS'"
```

**端口映射**：

| 服务 | 容器端口 | NodePort | 用途 |
|------|----------|----------|------|
| FE MySQL | 9030 | 30632 | SQL 客户端连接 |
| FE HTTP | 8030 | 30389 | Web UI / REST API |
| FE RPC | 9020 | 30356 | FE 间通信 |
| FE Edit Log | 9010 | 32280 | BDBJE 复制 |

### 清理步骤

#### 方式 A：一键清理脚本

```bash
cd k8s-local
./undeploy.sh
```

脚本会按顺序清理：
1. HPA 自动扩缩容
2. DorisCluster（FE + BE Pod 自动删除）
3. ConfigMap
4. 命名空间和 RBAC
5. Doris Operator（询问确认）

#### 方式 B：手动分步清理

```bash
cd k8s-local

# ---- 第 1 步：删除 HPA（如果部署了） ----
kubectl delete -f hpa.yaml --ignore-not-found=true

# ---- 第 2 步：删除 DorisCluster ----
# 这会自动删除所有 FE/BE 的 Pod、Service、StatefulSet
kubectl delete -f doriscluster.yaml --ignore-not-found=true

# 等待 Pod 完全终止
kubectl get pods -n doris -w

# ---- 第 3 步：删除 ConfigMap ----
kubectl delete -f configmap.yaml --ignore-not-found=true

# ---- 第 4 步：删除命名空间 ----
kubectl delete -f 00-namespace.yaml --ignore-not-found=true

# ---- 第 5 步：删除 Operator（可选） ----
# 如果不再需要 Doris Operator，可以一并删除
kubectl delete -f operator.yaml --ignore-not-found=true
```

> **注意**：本地部署使用 emptyDir 存储，Pod 删除后数据自动清除，无需额外清理 PVC。

---

## 二、生产部署 (GKE)

### 前置条件

| 条件 | 要求 |
|------|------|
| GCP 项目 | 已创建并启用计费 |
| gcloud CLI | 已安装并认证 (`gcloud auth login`) |
| GKE 集群 | 1.28+，至少 3 个节点 |
| kubectl | 已配置指向目标 GKE 集群 |
| GCS | 用于 BE 数据存储和备份 |

### 环境变量

```bash
# 必须设置以下环境变量
export PROJECT_ID="your-gcp-project"
export CLUSTER_NAME="doris-cluster"
export REGION="us-central1"

# 获取 GKE 集群凭证
gcloud container clusters get-credentials $CLUSTER_NAME \
  --region $REGION --project $PROJECT_ID
```

### 部署步骤

#### 方式 A：一键部署脚本

```bash
cd k8s-gke
./deploy.sh
```

脚本会自动完成：
1. 检查环境和工具
2. 创建 GCS 存储桶
3. 配置 Workload Identity（GCS 访问权限）
4. 创建 StorageClass（Regional PD）
5. 部署 Doris Operator（离线包或在线）
6. 部署 DorisCluster（3 FE + 3 BE）
7. 等待集群就绪（10-20 分钟）
8. 输出连接信息

#### 方式 B：手动分步部署

```bash
cd k8s-gke

# ---- 第 1 步：创建 GCS 存储桶 ----
# BE 数据存储在 GCS，支持存储计算分离
gsutil mb -p $PROJECT_ID -l $REGION "gs://${PROJECT_ID}-doris-data"

# ---- 第 2 步：配置 Workload Identity ----
# 让 Pod 直接使用 GCP Service Account 访问 GCS，无需密钥文件
# 参考 deploy.sh 中的 configure_workload_identity() 函数

# ---- 第 3 步：创建命名空间和 StorageClass ----
# Regional PD 确保数据跨区域副本，单节点故障不丢数据
kubectl apply -f 00-namespace.yaml

# ---- 第 4 步：部署 Doris Operator ----
# 推荐使用离线包部署（避免外网依赖）
kubectl apply -f operator.yaml
kubectl wait --for=condition=Ready pods \
  -l app.kubernetes.io/name=doris-operator \
  -n doris-operator-system \
  --timeout=180s

# ---- 第 5 步：部署 ConfigMap 和 Secret ----
kubectl apply -f configmap.yaml
kubectl apply -f configmap-be.yaml
kubectl apply -f secret.yaml

# ---- 第 6 步：部署 DorisCluster ----
# 生产环境：3 FE（高可用）+ 3 BE（数据副本）
kubectl apply -f doriscluster.yaml

# ---- 第 7 步：部署可选组件 ----

# 自动扩缩容（BE 支持根据负载自动扩容到 20 副本）
kubectl apply -f hpa.yaml

# Ingress + 负载均衡（对外暴露 HTTP/MySQL 端口）
kubectl apply -f services.yaml

# 网络策略（限制 FE/BE 间通信白名单）
kubectl apply -f network-policy.yaml

# Prometheus 监控
kubectl apply -f monitoring.yaml

# 定时备份到 GCS
kubectl apply -f backup.yaml

# ---- 第 8 步：等待集群就绪 ----
# FE 3 副本需要选举 Master，首次启动约 10-15 分钟
# BE 需要从 GCS 拉取数据，约 5-10 分钟
kubectl get pods -n doris -w
```

**预期输出**：
```
NAME                      READY   STATUS    RESTARTS   AGE
doriscluster-fe-0         1/1     Running   0          12m
doriscluster-fe-1         1/1     Running   0          12m
doriscluster-fe-2         1/1     Running   0          12m
doriscluster-be-0         1/1     Running   0          10m
doriscluster-be-1         1/1     Running   0          10m
doriscluster-be-2         1/1     Running   0          10m
```

### 验证部署

```bash
# 查看 Pod 状态
kubectl get pods -n doris -o wide

# 查看 Service 和 LoadBalancer IP
kubectl get svc -n doris

# 查看 PVC 状态（确认存储已绑定）
kubectl get pvc -n doris

# 查看 HPA 状态
kubectl get hpa -n doris

# 查看备份 CronJob
kubectl get cronjob -n doris
```

### 连接集群

```bash
# 获取 FE LoadBalancer IP
FE_IP=$(kubectl get svc -n doris doriscluster-fe-service \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# MySQL 连接
mysql -h $FE_IP -P 9030 -u root -p'your_password'

# Web UI
open http://$FE_IP:8030
```

### 清理步骤

#### 方式 A：一键清理脚本

```bash
cd k8s-gke
./undeploy.sh
```

> **警告**：此操作不可逆！GCS 中的数据不会被自动删除，需手动清理。

#### 方式 B：手动分步清理

```bash
cd k8s-gke

# ---- 第 1 步：删除可选组件 ----
kubectl delete -f backup.yaml --ignore-not-found=true
kubectl delete -f monitoring.yaml --ignore-not-found=true
kubectl delete -f network-policy.yaml --ignore-not-found=true
kubectl delete -f services.yaml --ignore-not-found=true
kubectl delete -f hpa.yaml --ignore-not-found=true

# ---- 第 2 步：删除 DorisCluster ----
kubectl delete -f doriscluster.yaml --ignore-not-found=true

# 等待所有 Pod 终止
kubectl get pods -n doris -w

# ---- 第 3 步：删除 ConfigMap 和 Secret ----
kubectl delete -f configmap.yaml --ignore-not-found=true
kubectl delete -f configmap-be.yaml --ignore-not-found=true
kubectl delete -f secret.yaml --ignore-not-found=true

# ---- 第 4 步：删除命名空间 ----
kubectl delete -f 00-namespace.yaml --ignore-not-found=true

# ---- 第 5 步：检查并删除残留 PVC ----
# Regional PD 是付费资源，确认不再需要后必须手动删除
kubectl get pvc -n doris
# kubectl delete pvc <pvc-name> -n doris  # 逐个删除

# ---- 第 6 步：删除 Operator（可选） ----
kubectl delete -f operator.yaml --ignore-not-found=true

# ---- 第 7 步：清理 GCS 数据（可选，不可逆！） ----
# gsutil rm -r "gs://${PROJECT_ID}-doris-data"

# ---- 第 8 步：清理 GCP 资源（可选） ----
# 删除 Service Account
# gcloud iam service-accounts delete doris-gcs-sa@$PROJECT_ID.iam.gserviceaccount.com
```

> **重要**：GKE 的 Regional PD 是独立计费的 Persistent Disk 资源。即使删除了 PVC，对应的 PD 可能仍然存在。请在 [GCP Console > Compute Engine > Disks](https://console.cloud.google.com/compute/disks) 中确认并清理。

---

## 三、日常运维命令

### 查看状态

```bash
# Pod 状态
kubectl get pods -n doris -o wide

# Service 列表
kubectl get svc -n doris

# PVC 存储状态
kubectl get pvc -n doris

# HPA 扩缩容状态
kubectl get hpa -n doris
kubectl describe hpa doris-fe-hpa -n doris

# 资源使用率
kubectl top pods -n doris

# DorisCluster CRD 状态
kubectl get dcr -n doris
kubectl describe dcr -n doris
```

### 日志查看

```bash
# FE 日志（实时跟踪）
kubectl logs -f doriscluster-local-fe-0 -n doris

# BE 日志（最后 100 行）
kubectl logs doriscluster-local-be-0 -n doris --tail=100

# 上一次崩溃日志
kubectl logs doriscluster-local-fe-0 -n doris --previous

# Operator 日志（排查 CRD 调谐问题）
kubectl logs -n doris-operator-system -l app.kubernetes.io/name=doris-operator --tail=50
```

### 进入容器调试

```bash
# 进入 FE 容器
kubectl exec -it doriscluster-local-fe-0 -n doris -- bash

# 进入 BE 容器
kubectl exec -it doriscluster-local-be-0 -n doris -- bash

# 在容器内查看配置
kubectl exec doriscluster-local-fe-0 -n doris -- cat /opt/apache-doris/fe/conf/fe.conf
```

### 重启组件

```bash
# 重启 FE（滚动重启，不影响可用性，仅限多副本）
kubectl delete pod doriscluster-local-fe-0 -n doris

# 强制重启所有 Doris Pod
kubectl delete pods -n doris -l app.doris.cluster/doriscluster-local
```

### 扩缩容

```bash
# 手动扩容 BE 到 3 副本（编辑 doriscluster.yaml 后 apply）
# 或使用 HPA 自动扩缩容
kubectl get hpa -n doris -w
```

---

## 四、故障排除

### Pod CrashLoopBackOff

```bash
# 查看崩溃原因
kubectl logs <pod-name> -n doris --previous
kubectl describe pod <pod-name> -n doris
```

**常见原因和解决方案**：

| 原因 | 现象 | 解决方案 |
|------|------|----------|
| FE 配置只读 | `fe.conf: Read-only file system` | 移除 `configMapInfo`，使用默认配置 |
| 端口冲突 | `address already in use` | 修改 NodePort 或 Service 端口 |
| 内存不足 | `OOMKilled` | 增大 `limits.memory` |
| 镜像拉取失败 | `ImagePullBackOff` | 检查镜像名或配置镜像拉取密钥 |

### FE 无法连接 BE

```sql
-- 在 MySQL 客户端中执行
SHOW BACKENDS;
SHOW PROC '/backends';

-- 如果 BE 状态不是 Alive，检查 BE 日志
-- kubectl logs doriscluster-local-be-0 -n doris
```

### HPA 无法扩容

```bash
# 检查 metrics-server 是否运行
kubectl get pods -n kube-system -l k8s-app=metrics-server

# 如果未安装：
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# 检查 HPA 事件
kubectl describe hpa doris-fe-hpa -n doris
```

### Operator 无法调谐

```bash
# 查看 Operator 日志
kubectl logs -n doris-operator-system -l app.kubernetes.io/name=doris-operator --tail=100

# 检查 CRD 是否注册
kubectl get crd | grep doris

# 检查 DorisCluster 资源状态
kubectl get dcr -n doris -o yaml
```

---

## 五、部署流程图

### 本地部署流程

```
kubectl apply operator.yaml
        │
        ▼
  Operator Pod Running
  (CRD + RBAC 已注册)
        │
        ▼
kubectl apply 00-namespace.yaml
        │
        ▼
  namespace "doris" Created
        │
        ▼
kubectl apply doriscluster.yaml
        │
        ▼
  ┌─────────────────────────┐
  │   Operator 调谐开始      │
  │   读取 DorisCluster CR  │
  └──────────┬──────────────┘
             │
     ┌───────┴───────┐
     ▼               ▼
 FE StatefulSet   BE StatefulSet
     │               │
     ▼               ▼
 FE Pod (3-5min)  BE Pod (2-3min)
     │               │
     └───────┬───────┘
             ▼
     FE ↔ BE 通信建立
             │
             ▼
       集群就绪 ✅
```

### 清理流程

```
kubectl delete doriscluster.yaml
        │
        ▼
  Operator 调谐清理
        │
        ▼
  ┌─────────────────────────┐
  │ StatefulSet 缩容到 0     │
  │ Service 删除             │
  │ Pod 终止                 │
  └──────────┬──────────────┘
             │
             ▼
  ConfigMap / Secret 删除
             │
             ▼
  namespace "doris" 删除
             │
             ▼
  (可选) Operator + CRD 删除
             │
             ▼
       清理完成 ✅
```

---

## 参考文档

| 文档 | 说明 |
|------|------|
| [k8s-local/README.md](./k8s-local/README.md) | 本地部署详细说明 |
| [k8s-gke/README.md](./k8s-gke/README.md) | GKE 生产部署详细说明 |
| [DEBUG-LOCAL.md](./DEBUG-LOCAL.md) | 本地部署调试记录 |
| [QUICK-START.md](./QUICK-START.md) | Docker Compose 快速开始 |
| [Doris Operator](https://github.com/apache/doris-operator) | 官方 Operator 仓库 |
| [Doris 文档](https://doris.apache.org) | Apache Doris 官方文档 |
