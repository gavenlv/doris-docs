# 离线构建指南

## 概述

本文档说明如何在没有外网访问的环境中构建 Doris 安全镜像。

## 构建模式

| 模式 | 说明 | 适用场景 |
|------|------|---------|
| `local` | 使用本地离线包 | 完全离线环境 |
| `nexus` | 从公司 Nexus 下载依赖 | 可访问 Nexus |
| `gcs` | 从 GCS 下载依赖 | 可访问 GCS |

## 流程概览

```
┌─────────────────────────────────────────────────────────────┐
│                    离线构建流程                              │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. 有网环境: 下载离线包                                    │
│     ./scripts/prepare-offline.sh download                  │
│                         │                                   │
│                         ▼                                   │
│  2. 传输到构建服务器                                        │
│     - USB 硬盘                                              │
│     - 内网传输                                              │
│                         │                                   │
│                         ▼                                   │
│  3. 构建镜像                                                │
│     BUILD_MODE=local ./scripts/build-images.sh all         │
│                         │                                   │
│                         ▼                                   │
│  4. 扫描并推送                                              │
│     ./scripts/scan-images.sh all                           │
│     ./scripts/push-to-nexus.sh                             │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## 详细步骤

### 方式一: 本地离线构建（推荐）

#### 步骤 1: 下载离线包（有网环境）

```bash
# 下载所有依赖到本地
./scripts/prepare-offline.sh download

# 查看下载的文件
ls -la offline-packages/
```

输出:
```
offline-packages/
├── doris-fe/
│   └── apache-doris-fe-3.1.4-bin.tar.gz
├── doris-be/
│   └── apache-doris-be-3.1.4-bin-x86_64.tar.gz
└── foundationdb/
    ├── foundationdb-clients_7.1.37-1_amd64.deb
    └── foundationdb-server_7.1.37-1_amd64.deb
```

#### 步骤 2: 传输到构建服务器

```bash
# 打包
tar -czvf offline-packages.tar.gz offline-packages/

# 传输方式:
# - USB 硬盘
# - 内网文件共享
# - 公司文件传输系统

# 在构建服务器上解压
tar -xzvf offline-packages.tar.gz
```

#### 步骤 3: 构建镜像（离线环境）

```bash
# 使用本地离线包构建
BUILD_MODE=local ./scripts/build-images.sh all

# 或指定组件
BUILD_MODE=local ./scripts/build-images.sh fe
BUILD_MODE=local ./scripts/build-images.sh be
BUILD_MODE=local ./scripts/build-images.sh fdb
```

### 方式二: Nexus 离线构建

如果构建服务器可以访问公司 Nexus：

#### 步骤 1: 上传离线包到 Nexus（有网环境）

```bash
# 先下载离线包
./scripts/prepare-offline.sh download

# 上传到 Nexus
export NEXUS_PASS=your-password
./scripts/upload-to-nexus.sh

# 验证上传
curl -u admin:your-password \
    http://nexus.company.com:8082/repository/doris-packages/doris-fe/3.1.4/
```

#### 步骤 2: 从 Nexus 构建（离线环境）

```bash
# 设置 Nexus 凭据（不保存到文件）
export NEXUS_USER=admin
export NEXUS_PASS=your-password

# 从 Nexus 下载依赖并构建
BUILD_MODE=nexus ./scripts/build-images.sh all
```

**注意**: `--secret` 凭据只在构建过程中使用，不会保存到镜像中。

### 方式三: GCS 离线构建

如果构建服务器可以访问 GCS：

#### 步骤 1: 上传到 GCS（有网环境）

```bash
# 下载离线包
./scripts/prepare-offline.sh download

# 上传到 GCS
./scripts/prepare-offline.sh upload-gcs
```

#### 步骤 2: 从 GCS 构建

```bash
# 设置 GCS 路径
export GCS_BUCKET=gs://doris-build-packages/doris-3.1.4

# 从 GCS 下载并构建
BUILD_MODE=gcs ./scripts/build-images.sh all
```

## 故障排查

### 问题 1: 找不到离线包

```
ERROR: Package not found
```

**解决方案**:
```bash
# 检查离线包目录
ls -la offline-packages/doris-fe/
ls -la offline-packages/doris-be/
ls -la offline-packages/foundationdb/
```

### 问题 2: Nexus 登录失败

```
unauthorized: unauthorized to access repository
```

**解决方案**:
```bash
# 验证凭据
export NEXUS_PASS=your-password
docker login nexus.company.com:8082 -u admin --password-stdin
```

### 问题 3: BuildKit 未启用

```
ERROR: invalid reference format
```

**解决方案**:
```bash
# 启用 BuildKit
export DOCKER_BUILDKIT=1

# 或在 Docker 配置中启用
# /etc/docker/daemon.json
{
  "features": {
    "buildkit": true
  }
}
```

## 环境变量参考

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `BUILD_MODE` | 构建模式 | `local` |
| `NEXUS_URL` | Nexus 地址 | `nexus.company.com:8082` |
| `NEXUS_USER` | Nexus 用户名 | `admin` |
| `NEXUS_PASS` | Nexus 密码 | - |
| `DORIS_VERSION` | Doris 版本 | `3.1.4` |
| `FDB_VERSION` | FDB 版本 | `7.1.37` |
| `GCS_BUCKET` | GCS 路径 | `gs://doris-build-packages` |

## 安全说明

1. **凭据安全**: 使用 `--secret` 传递的凭据只在构建时使用，不会保存到镜像中
2. **离线验证**: 构建完成后，使用 Trivy 扫描确保无漏洞
3. **镜像签名**: 建议使用 Cosign 签名镜像

## 相关文档

- [构建指南](BUILD-GUIDE.md)
- [安全加固指南](SECURITY-HARDENING.md)
- [部署指南](DEPLOYMENT-GUIDE.md)
