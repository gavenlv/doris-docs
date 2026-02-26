# Nexus Docker 镜像仓库配置指南

## 概述

本文档说明如何配置公司内部 Nexus Docker 镜像仓库，用于 Doris GKE 集群的离线部署。

## 前置条件

- Nexus Repository Manager 3.x 已安装并运行
- Nexus 管理员账号权限
- Docker 客户端已安装
- 访问外网的权限（用于初始镜像同步）

## 步骤 1: 创建 Docker 仓库

### 1.1 登录 Nexus 管理界面

```bash
# 访问 Nexus Web UI
https://nexus.company.com
```

### 1.2 创建 Docker Hosted 仓库

1. 导航至 **Repository → Repositories**
2. 点击 **Create repository**
3. 选择 **docker (hosted)**
4. 配置仓库：
   - Name: `doris`
   - HTTP Port: `8082` (或公司规定的端口)
   - Enable Docker V1 API: `true` (如果需要兼容旧版本)
5. 点击 **Create repository**

### 1.3 创建 Docker Proxy 仓库（可选）

如果需要 Nexus 自动代理外网镜像：

1. 选择 **docker (proxy)**
2. 配置：
   - Name: `docker-proxy`
   - Proxy URL: `https://registry-1.docker.io`
   - HTTP Port: `8083`
3. 创建仓库

### 1.4 创建 Docker Group 仓库（可选）

整合 hosted 和 proxy 仓库：

1. 选择 **docker (group)**
2. 配置：
   - Name: `docker-group`
   - HTTP Port: `8084`
   - Member repositories: 添加 `doris` 和 `docker-proxy`
3. 创建仓库

## 步骤 2: 配置 Docker 客户端

### 2.1 配置 Docker 信任 Nexus

```bash
# 编辑 Docker daemon 配置
sudo vi /etc/docker/daemon.json
```

添加内容：

```json
{
  "insecure-registries": ["nexus.company.com:8082"],
  "registry-mirrors": ["http://nexus.company.com:8083"]
}
```

重启 Docker：

```bash
sudo systemctl restart docker
```

### 2.2 登录 Nexus Docker 仓库

```bash
docker login nexus.company.com:8082
# Username: admin
# Password: <your-password>
```

## 步骤 3: 同步镜像到 Nexus

### 3.1 配置同步脚本

编辑 `configs/nexus-config.yaml`，更新 Nexus URL 和凭据：

```yaml
nexus:
  url: nexus.company.com:8082
  username: admin
  password: your-password
```

### 3.2 运行镜像同步脚本

```bash
cd doris-gke-cluster
export NEXUS_USER=admin
export NEXUS_PASS=your-password
./scripts/sync-images.sh
```

### 3.3 验证镜像

```bash
# 列出 Nexus 中的所有镜像
curl -u admin:password https://nexus.company.com:8082/v2/_catalog

# 列出特定镜像的所有标签
curl -u admin:password https://nexus.company.com:8082/v2/doris/fe/tags/list
```

## 步骤 4: 创建 Kubernetes Secret

### 4.1 创建命名空间

```bash
kubectl create namespace doris
```

### 4.2 创建 Docker Registry Secret

```bash
kubectl create secret docker-registry nexus-secret \
  --docker-server=nexus.company.com:8082 \
  --docker-username=admin \
  --docker-password=your-password \
  --docker-email=admin@company.com \
  -n doris
```

### 4.3 验证 Secret

```bash
kubectl get secret nexus-secret -n doris -o yaml
```

## 步骤 5: 在 Kubernetes 中使用 Nexus 镜像

### 5.1 在 Pod 配置中引用

```yaml
spec:
  imagePullSecrets:
  - name: nexus-secret
  containers:
  - name: doris-fe
    image: nexus.company.com:8082/doris/fe:3.1.4
```

### 5.2 部署 Doris

```bash
kubectl apply -f kubernetes/doris-cluster/
```

## 故障排查

### 问题 1: 镜像拉取失败

**错误**: `ImagePullBackOff`

**解决方案**:
1. 检查 Secret 是否正确创建
2. 验证 Nexus 凭据是否正确
3. 检查网络连接
4. 确认镜像已推送到 Nexus

```bash
# 查看详细错误信息
kubectl describe pod <pod-name> -n doris
```

### 问题 2: Docker 登录失败

**错误**: `unauthorized`

**解决方案**:
1. 检查用户名和密码
2. 确认用户有权限访问 Docker 仓库
3. 检查 Nexus 实时日志

```bash
# 查看 Nexus 日志
tail -f /opt/nexus/logs/nexus.log
```

### 问题 3: 网络连接问题

**解决方案**:
1. 验证 DNS 解析
2. 检查防火墙规则
3. 确认端口是否开放

```bash
# 测试连接
telnet nexus.company.com 8082

# 测试 Docker API
curl -v https://nexus.company.com:8082/v2/
```

## 安全建议

1. **使用专用账号**: 为 Doris 部署创建专用的 Nexus 账号，仅授予读取权限
2. **启用 HTTPS**: 生产环境必须使用 HTTPS
3. **定期轮换密码**: 定期更新 Nexus 密码并更新 Kubernetes Secret
4. **限制访问 IP**: 配置 Nexus 只允许特定 IP 访问
5. **审计日志**: 启用 Nexus 审计日志，监控镜像访问

## 性能优化

1. **配置镜像缓存**: 使用 Docker Proxy 缓存外网镜像
2. **使用本地镜像仓库**: 在每个 GKE 节点配置本地缓存
3. **并行拉取**: 配置 Docker daemon 支持并行镜像拉取
4. **镜像分层优化**: 使用精简的基础镜像，减少层数

## 附录: 镜像列表

需要同步到 Nexus 的镜像：

- `apache/doris:fe-3.1.4`
- `apache/doris:be-3.1.4`
- `foundationdb/foundationdb:7.1.37`
- `apache/doris-operator:v1.1.0`
- `prom/prometheus:v2.45.0` (可选)
- `grafana/grafana:10.2.0` (可选)

## 联系支持

如有问题，请联系：
- Nexus 管理员: nexus-admin@company.com
- Doris 部署团队: doris-team@company.com
