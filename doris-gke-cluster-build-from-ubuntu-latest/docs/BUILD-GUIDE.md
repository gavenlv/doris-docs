# 构建指南

## 环境准备

### 系统要求

- 操作系统: Linux / macOS / Windows (WSL2)
- Docker: 24.0+
- 内存: 至少 8GB
- 磁盘: 至少 50GB 可用空间

### 安装依赖

```bash
# 安装 Docker
# Ubuntu/Debian
curl -fsSL https://get.docker.com | bash

# macOS
brew install --cask docker

# 安装 Trivy (安全扫描)
brew install trivy  # macOS
# 或
sudo apt-get install trivy  # Ubuntu

# 安装 jq (JSON 处理)
brew install jq  # macOS
# 或
sudo apt-get install jq  # Ubuntu
```

### 配置环境变量

```bash
# 创建 .env 文件或导出环境变量
export NEXUS_URL="nexus.company.com:8082"
export NEXUS_USER="admin"
export NEXUS_PASS="your-password"
export NEXUS_REPO="doris"

# Doris 版本
export DORIS_VERSION="3.1.4"
export FDB_VERSION="7.1.37"
export OPERATOR_VERSION="v1.1.0"
```

## 构建流程

### 完整构建流程

```bash
# 1. 进入项目目录
cd doris-gke-cluster-build-from-ubuntu-latest

# 2. 构建所有镜像
./scripts/build-images.sh all

# 3. 扫描镜像
./scripts/scan-images.sh all

# 4. 查看报告
cat reports/security-scan-report.txt

# 5. 如果有漏洞，修复后重新构建
./scripts/fix-vulnerabilities.sh
# 修改 Dockerfile 后重新构建

# 6. 推送到 Nexus
./scripts/push-to-nexus.sh all
```

### 单独构建组件

```bash
# 仅构建 FE
./scripts/build-images.sh fe

# 仅构建 BE
./scripts/build-images.sh be

# 仅构建 FoundationDB
./scripts/build-images.sh fdb

# 仅构建 Operator
./scripts/build-images.sh operator
```

## Dockerfile 说明

### FE Dockerfile 结构

```dockerfile
# 阶段 1: 下载 Doris
FROM ubuntu:22.04 AS downloader
# ... 下载和解压

# 阶段 2: 运行时镜像
FROM ubuntu:22.04
# ... 安全加固和配置
```

### 关键构建参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| DORIS_VERSION | Doris 版本 | 3.1.4 |
| DORIS_DOWNLOAD_URL | 下载地址 | https://archive.apache.org/dist/doris |
| FDB_VERSION | FoundationDB 版本 | 7.1.37 |
| OPERATOR_VERSION | Operator 版本 | v1.1.0 |

### 自定义构建

```bash
# 指定版本构建
docker build \
    --build-arg DORIS_VERSION=3.1.5 \
    -t nexus.company.com:8082/doris/fe:3.1.5-secure \
    docker/fe/
```

## 镜像优化

### 减小镜像大小

1. **多阶段构建**: 分离构建和运行时环境
2. **清理缓存**: `rm -rf /var/lib/apt/lists/*`
3. **移除文档**: 删除 README、LICENSE 等文件
4. **使用 alpine**: 考虑使用 alpine 基础镜像（需测试兼容性）

### 镜像大小参考

| 组件 | 优化前 | 优化后 |
|------|--------|--------|
| FE | ~2.5GB | ~1.8GB |
| BE | ~1.5GB | ~1.2GB |
| FDB | ~800MB | ~500MB |
| Operator | ~200MB | ~50MB |

## 构建缓存

### 利用缓存加速构建

```bash
# 不使用 --no-cache 会利用 Docker 缓存
docker build -t image:tag .
```

### 清理构建缓存

```bash
# 清理未使用的镜像
docker image prune

# 清理所有未使用资源
docker system prune
```

## 故障排查

### 常见问题

#### 1. 下载失败

```
Error: failed to download Doris
```

**解决方案**:
- 检查网络连接
- 使用代理或镜像站点
- 手动下载后放到本地

#### 2. 磁盘空间不足

```
Error: no space left on device
```

**解决方案**:
```bash
# 清理 Docker 资源
docker system prune -a
```

#### 3. 构建超时

**解决方案**:
- 增加构建超时时间
- 使用国内镜像源
- 检查网络连接

### 构建日志

查看详细构建日志：

```bash
# 启用调试模式
DEBUG=1 ./scripts/build-images.sh all
```

## CI/CD 集成

### GitHub Actions 示例

```yaml
name: Build and Scan
on:
  push:
    branches: [main]
  schedule:
    - cron: '0 2 * * 0'  # 每周构建

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    
    - name: Build images
      run: ./scripts/build-images.sh all
    
    - name: Scan images
      run: ./scripts/scan-images.sh all
    
    - name: Push to Nexus
      if: success()
      run: ./scripts/push-to-nexus.sh all
      env:
        NEXUS_PASS: ${{ secrets.NEXUS_PASSWORD }}
```

## 相关文档

- [安全加固指南](SECURITY-HARDENING.md)
- [漏洞修复记录](VULNERABILITY-FIXES.md)
- [部署指南](DEPLOYMENT-GUIDE.md)
