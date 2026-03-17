# Doris GKE 集群 - 安全加固镜像构建部署方案

## 概述

本方案从 Ubuntu 基础镜像构建 Doris 组件镜像，集成安全扫描和漏洞修复流程，确保部署的镜像不含已知安全漏洞。

## 重要说明：Doris 3.x 包格式变更

Doris 3.x 版本使用**统一二进制包格式**：
- **文件名**: `apache-doris-{VERSION}-bin-x64.tar.gz`
- **包含内容**: 同时包含 `fe/` 和 `be/` 目录
- **下载地址**: 阿里云 OSS (官方镜像)
- **本方案版本**: 3.0.5 (稳定版，有现成二进制包)

> ⚠️ **注意**: Doris 3.1.4 在 Apache 归档中只有源码包，没有二进制包。因此本方案使用 3.0.5 版本。

## 与标准方案的区别

| 特性 | 标准方案 | 安全加固方案 |
|------|---------|-------------|
| 基础镜像 | 官方 Doris 镜像 | Ubuntu 最新 LTS + 手动构建 |
| 安全扫描 | 无 | Trivy 全量扫描 |
| 漏洞处理 | 依赖官方修复 | 自主修复所有漏洞 |
| 镜像来源 | Docker Hub | 公司内部 Nexus |
| 合规性 | 一般 | 高（满足安全审计） |

## 适用场景

- 公司安全策略要求无已知漏洞
- 安全审计要求可追溯的镜像构建
- 需要自定义镜像内容
- 对镜像大小有优化需求

## 快速开始

### 在线构建

```bash
# 1. 构建并扫描镜像
./scripts/build-and-scan.sh all

# 2. 查看安全报告
cat reports/security-scan-report.txt

# 3. 修复漏洞（如有）
./scripts/fix-vulnerabilities.sh

# 4. 推送到 Nexus
./scripts/push-to-nexus.sh

# 5. 部署到 GKE
./scripts/deploy.sh
```

### 离线构建（推荐）

适用于构建环境无外网访问的场景：

```bash
# 1. 有网环境：下载离线包
./scripts/prepare-offline.sh download

# 2. 传输 offline-packages/ 到构建服务器

# 3. 离线环境构建
BUILD_MODE=local ./scripts/build-images.sh all

# 4. 安全扫描
./scripts/scan-images.sh all

# 5. 部署
./scripts/deploy.sh
```

详见: [离线构建指南](docs/OFFLINE-BUILD.md)

### 本地验证

在开发/测试环境中验证整个方案：

```bash
# Windows 用户
.\verify.bat

# Linux/macOS 用户
./scripts/local-verify.sh all
```

详见: [本地验证指南](docs/LOCAL-VERIFY.md)

## 目录结构

```
doris-gke-cluster-build-from-ubuntu-latest/
├── docker/                    # Dockerfile 和构建相关
│   ├── fe/                   # FE 镜像构建
│   ├── be/                   # BE 镜像构建
│   ├── fdb/                  # FoundationDB 镜像构建
│   └── operator/             # Doris Operator 镜像构建
├── scripts/                   # 构建和部署脚本
│   ├── build-images.sh       # 构建镜像
│   ├── scan-images.sh        # 安全扫描
│   ├── fix-vulnerabilities.sh # 漏洞修复
│   └── push-to-nexus.sh      # 推送到 Nexus
├── kubernetes/               # Kubernetes 配置
│   ├── doris-cluster/        # Doris 集群配置
│   ├── storage/              # 存储配置
│   └── namespace.yaml        # 命名空间
├── docs/                     # 文档
│   ├── SECURITY-HARDENING.md # 安全加固指南
│   ├── BUILD-GUIDE.md        # 构建指南
│   ├── OFFLINE-BUILD.md      # 离线构建指南
│   ├── LOCAL-VERIFY.md       # 本地验证指南
│   ├── VULNERABILITY-FIXES.md # 漏洞修复记录
│   └── DEPLOYMENT-GUIDE.md   # 部署指南
├── configs/                  # 配置文件
└── reports/                  # 安全扫描报告
```

## 安全流程

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│  构建镜像    │───▶│  安全扫描    │───▶│  漏洞修复    │
│  (Ubuntu)    │    │  (Trivy)     │    │  (迭代)      │
└──────────────┘    └──────────────┘    └──────────────┘
                                              │
                                              ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│  部署到 GKE  │◀───│  推送到 Nexus│◀───│  验证通过    │
│              │    │              │    │  (0 漏洞)    │
└──────────────┘    └──────────────┘    └──────────────┘
```

## 镜像信息

| 组件 | 基础镜像 | 版本 | 安全状态 |
|------|---------|------|---------|
| Doris FE | ubuntu:22.04 | 3.1.4 | 待扫描 |
| Doris BE | ubuntu:22.04 | 3.1.4 | 待扫描 |
| FoundationDB | ubuntu:22.04 | 7.1.37 | 待扫描 |
| Doris Operator | ubuntu:22.04 | v1.1.0 | 待扫描 |

## 前置要求

- Docker 24.0+
- Trivy 0.45+ (安全扫描)
- kubectl 1.28+
- GCP 项目访问权限
- Nexus Registry 访问权限

## 开始使用

### 方式 1: 一键验证 (推荐)

**Windows 用户:**
```powershell
# 在项目根目录双击运行
.\verify.bat
```

**Linux/macOS 用户:**
```bash
# 赋予执行权限并运行
chmod +x scripts/*.sh
./scripts/local-verify.sh all
```

### 如果 Nexus 登录失败

**方案 A: 修复 Nexus (PowerShell)**
```powershell
# 运行诊断修复脚本
powershell -ExecutionPolicy Bypass -File scripts\fix-nexus.ps1
```

**方案 B: 跳过 Nexus，仅验证镜像构建**
```powershell
# Windows 简化验证 (无需 Nexus)
.\verify-simple.bat

# Linux/macOS 简化验证
./scripts/build-images.sh all
./scripts/scan-images.sh all
```

### 方式 2: 手动验证

参考 [本地验证指南](docs/LOCAL-VERIFY.md) 按步骤执行。

### 方式 3: 生产部署

参考 [部署指南](docs/DEPLOYMENT-GUIDE.md)。

## 项目文档

| 文档 | 说明 |
|------|------|
| [PROJECT-SUMMARY.md](PROJECT-SUMMARY.md) | 项目完整总结 |
| [安全加固指南](docs/SECURITY-HARDENING.md) | 安全措施详解 |
| [构建指南](docs/BUILD-GUIDE.md) | 镜像构建说明 |
| [离线构建指南](docs/OFFLINE-BUILD.md) | 离线环境构建 |
| [本地验证指南](docs/LOCAL-VERIFY.md) | 本地测试步骤 |
| [漏洞修复记录](docs/VULNERABILITY-FIXES.md) | 漏洞处理记录 |
| [部署指南](docs/DEPLOYMENT-GUIDE.md) | GKE 部署说明 |
