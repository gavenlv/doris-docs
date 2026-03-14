# Doris GKE 集群 - 安全加固镜像构建部署方案

## 概述

本方案从 Ubuntu 基础镜像构建 Doris 组件镜像，集成安全扫描和漏洞修复流程，确保部署的镜像不含已知安全漏洞。

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

## 相关文档

- [安全加固指南](docs/SECURITY-HARDENING.md)
- [构建指南](docs/BUILD-GUIDE.md)
- [漏洞修复记录](docs/VULNERABILITY-FIXES.md)
- [部署指南](docs/DEPLOYMENT-GUIDE.md)
