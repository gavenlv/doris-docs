# 本地验证指南

## 概述

本文档说明如何在本地环境验证整个 Doris 安全镜像构建方案。

## 前置要求

- Docker Desktop 已安装并运行
- 至少 20GB 可用磁盘空间
- 至少 8GB 可用内存

## 快速开始

### 自动化验证

#### Windows 用户

```powershell
# 在项目根目录运行
.\verify.bat
```

该脚本会自动完成以下步骤：
1. 启动 Nexus 容器
2. 下载离线包
3. 构建镜像
4. 推送到 Nexus
5. 验证拉取

#### Linux/macOS 用户

```bash
# 在项目根目录运行
./scripts/local-verify.sh all
```

## 手动验证步骤

### 步骤 1: 启动 Nexus

```powershell
# 启动 Nexus 容器
docker run -d --name doris-nexus -p 8081:8081 -p 8082:8082 sonatype/nexus3:latest
```

**等待 2 分钟让 Nexus 完全启动**

#### 访问 Nexus

- Web UI: http://localhost:8081
- Docker Registry: localhost:8082
- 默认账号: admin / admin123 (首次登录需修改密码)

#### 配置 Nexus

1. 登录 Nexus Web UI
2. 创建 Docker Hosted Repository:
   - Name: `doris-docker`
   - HTTP Port: `8082`
3. 创建 Raw Hosted Repository (可选，用于存储离线包):
   - Name: `doris-packages`

### 步骤 2: 准备离线包

```powershell
# 创建目录
mkdir offline-packages\doris-fe
mkdir offline-packages\doris-be
mkdir offline-packages\foundationdb
```

#### 下载 Doris FE

```powershell
$DORIS_VERSION = "3.1.4"
Invoke-WebRequest -Uri "https://archive.apache.org/dist/doris/$DORIS_VERSION/apache-doris-fe-$DORIS_VERSION-bin.tar.gz" -OutFile "offline-packages\doris-fe\apache-doris-fe-$DORIS_VERSION-bin.tar.gz"
```

#### 下载 Doris BE

```powershell
Invoke-WebRequest -Uri "https://archive.apache.org/dist/doris/$DORIS_VERSION/apache-doris-be-$DORIS_VERSION-bin-x86_64.tar.gz" -OutFile "offline-packages\doris-be\apache-doris-be-$DORIS_VERSION-bin-x86_64.tar.gz"
```

#### 下载 FoundationDB

```powershell
$FDB_VERSION = "7.1.37"
Invoke-WebRequest -Uri "https://github.com/apple/foundationdb/releases/download/$FDB_VERSION/foundationdb-clients_$FDB_VERSION-1_amd64.deb" -OutFile "offline-packages\foundationdb\foundationdb-clients_$FDB_VERSION-1_amd64.deb"
Invoke-WebRequest -Uri "https://github.com/apple/foundationdb/releases/download/$FDB_VERSION/foundationdb-server_$FDB_VERSION-1_amd64.deb" -OutFile "offline-packages\foundationdb\foundationdb-server_$FDB_VERSION-1_amd64.deb"
```

### 步骤 3: 构建镜像

**重要**: 修改 Dockerfile 中的 OFFLINE_PATH 为您的实际路径

#### 构建 Doris FE

```powershell
cd docker\fe

# Windows 路径示例
docker build `
  --build-arg DORIS_VERSION=3.1.4 `
  --build-arg OFFLINE_PATH=C:\workspace\github\doris-docs\doris-gke-cluster-build-from-ubuntu-latest\offline-packages `
  -t doris-fe:3.1.4 `
  .
```

#### 构建 Doris BE

```powershell
cd ..\be

docker build `
  --build-arg DORIS_VERSION=3.1.4 `
  --build-arg OFFLINE_PATH=C:\workspace\github\doris-docs\doris-gke-cluster-build-from-ubuntu-latest\offline-packages `
  -t doris-be:3.1.4 `
  .
```

#### 验证构建

```powershell
docker images | findstr "doris-"
```

期望输出:
```
doris-fe    3.1.4    xxx MB    xxx ago
doris-be    3.1.4    xxx MB    xxx ago
```

### 步骤 4: 推送到 Nexus

#### 登录 Nexus

```powershell
docker login localhost:8082 -u admin -p admin123
```

#### Tag 镜像

```powershell
docker tag doris-fe:3.1.4 localhost:8082/doris/fe:3.1.4-secure
docker tag doris-be:3.1.4 localhost:8082/doris/be:3.1.4-secure
```

#### 推送镜像

```powershell
docker push localhost:8082/doris/fe:3.1.4-secure
docker push localhost:8082/doris/be:3.1.4-secure
```

### 步骤 5: 验证拉取

#### 清理本地镜像

```powershell
docker rmi localhost:8082/doris/fe:3.1.4-secure 2>$null
docker rmi localhost:8082/doris/be:3.1.4-secure 2>$null
```

#### 从 Nexus 拉取

```powershell
docker pull localhost:8082/doris/fe:3.1.4-secure
docker pull localhost:8082/doris/be:3.1.4-secure
```

#### 验证结果

```powershell
docker images | findstr "localhost:8082"
```

期望输出:
```
localhost:8082/doris/fe    3.1.4-secure    xxx MB    xxx ago
localhost:8082/doris/be    3.1.4-secure    xxx MB    xxx ago
```

## 可选步骤

### 安全扫描

如果已安装 Trivy:

```powershell
# 扫描 FE
trivy image --severity HIGH,CRITICAL doris-fe:3.1.4

# 扫描 BE
trivy image --severity HIGH,CRITICAL doris-be:3.1.4
```

### 测试镜像运行

```powershell
# 测试 FE
docker run -it --rm doris-fe:3.1.4 /bin/bash

# 测试 BE
docker run -it --rm doris-be:3.1.4 /bin/bash
```

## Nexus 登录问题

### 无法访问 http://localhost:8081

**症状**: 浏览器无法打开 Nexus 登录页面

**诊断步骤**:

```powershell
# Windows - 运行诊断脚本
powershell -ExecutionPolicy Bypass -File scripts\fix-nexus.ps1

# Linux/macOS - 运行诊断脚本
./scripts/fix-nexus.sh
```

**常见原因和解决方案**:

#### 原因 1: Nexus 仍在启动中

Nexus 首次启动需要 1-2 分钟。

```bash
# 查看启动状态
docker logs --tail 50 doris-nexus | grep -i "started"

# 等待完全启动
sleep 120
```

#### 原因 2: 忘记初始密码

```bash
# 获取初始密码
docker exec doris-nexus cat /nexus-data/admin.password
```

输出示例:
```
8a7b6c5d-4e3f-2g1h-0i9j-8k7l6m5n4o3p
```

使用 `admin / 上面获取的密码` 登录。

#### 原因 3: 使用正确的密码

您提供的凭据：**admin / adminadmin**

```bash
# 使用您的凭据登录
docker login localhost:8082 -u admin -p adminadmin

# 或在浏览器中访问 http://localhost:8081
# 用户名: admin
# 密码: adminadmin
```

如果密码不正确，重置 admin 密码:
```bash
# 进入 Nexus 容器重置密码
docker exec -it doris-nexus /bin/bash

# 在容器内执行
cd /opt/sonatype/nexus/bin
./nexus reset-admin-password
# 按提示设置新密码
```

#### 原因 4: 端口冲突

```bash
# 检查端口占用
netstat -ano | grep 8081

# 如果端口被占用，使用其他端口
docker rm -f doris-nexus
docker run -d --name doris-nexus -p 8091:8081 -p 8092:8082 sonatype/nexus3:latest

# 然后访问 http://localhost:8091
```

#### 原因 5: 容器未正常运行

```bash
# 完全重置 Nexus
docker rm -f doris-nexus
docker volume prune -f
docker run -d --name doris-nexus -p 8081:8081 -p 8082:8082 sonatype/nexus3:latest

# 等待 2 分钟
sleep 120
```

### 跳过 Nexus 验证

如果 Nexus 问题暂时无法解决，可以先验证镜像构建:

**Windows:**
```powershell
.\verify-simple.bat
```

**Linux/macOS:**
```bash
# 仅构建镜像
./scripts/build-images.sh all

# 扫描镜像
./scripts/scan-images.sh all
```

## 其他故障排查

### 问题 1: Docker 连接失败

```
error during connect: This error may indicate that the docker daemon is not running
```

**解决方案**:
```powershell
# 启动 Docker Desktop
Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"

# 等待启动
Start-Sleep -Seconds 30

# 验证
docker version
```

### 问题 2: Nexus 启动缓慢

**解决方案**:
- Nexus 首次启动需要 1-2 分钟
- 查看日志: `docker logs doris-nexus`
- 确认启动: `curl http://localhost:8081`

### 问题 3: 镜像构建失败 - 找不到离线包

```
ERROR: Package not found
```

**解决方案**:
```powershell
# 检查目录结构
Get-ChildItem -Recurse offline-packages

# 检查路径是否正确
# Dockerfile 中的 OFFLINE_PATH 应该指向宿主机路径
# Windows 格式: C:\workspace\github\doris-docs\doris-gke-cluster-build-from-ubuntu-latest\offline-packages
# Linux 格式: /workspace/github/doris-docs/doris-gke-cluster-build-from-ubuntu-latest/offline-packages
```

### 问题 4: Nexus 登录失败

```
Error: unauthorized: unauthorized to access repository
```

**解决方案**:
1. 访问 http://localhost:8081
2. 使用 admin 登录（查看容器获取初始密码）
3. 修改密码后使用新密码登录
4. 确认 Docker 仓库已创建

### 问题 5: 推送镜像失败

```
Error: unauthorized: incorrect username or password
```

**解决方案**:
```powershell
# 注销现有登录
docker logout localhost:8082

# 重新登录
docker login localhost:8082 -u admin
# 输入密码时注意隐藏
```

## 清理资源

### 停止 Nexus

```powershell
docker stop doris-nexus
```

### 删除 Nexus

```powershell
docker rm doris-nexus
```

### 清理镜像

```powershell
# 删除所有 doris 镜像
docker images | findstr "doris" | ForEach-Object { docker rmi ($_ -split '\s+')[2] }

# 清理所有悬空镜像
docker image prune -f
```

### 清理离线包

```powershell
# 删除整个 offline-packages 目录
Remove-Item -Recurse -Force offline-packages
```

## 验证清单

- [ ] Docker Desktop 已启动
- [ ] Nexus 容器运行中
- [ ] 可以访问 http://localhost:8081
- [ ] 离线包已下载
- [ ] FE 镜像构建成功
- [ ] BE 镜像构建成功
- [ ] 镜像已推送到 Nexus
- [ ] 可以从 Nexus 拉取镜像
- [ ] 镜像无高危漏洞（如安装 Trivy）

## 相关文档

- [离线构建指南](OFFLINE-BUILD.md)
- [构建指南](BUILD-GUIDE.md)
- [安全加固指南](SECURITY-HARDENING.md)

## 联系支持

遇到问题请查看:
- Doris 部署团队: doris-team@company.com
