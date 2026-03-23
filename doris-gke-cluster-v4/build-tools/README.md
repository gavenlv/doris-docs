# Build Tools

本地构建、推送镜像到 Nexus 的完整工具链。

## 目录结构

```
build-tools/
├── README.md                  # 本文档
├── build-all.sh               # 完整构建流程脚本
├── pre-build.sh               # 前置准备（下载 Doris 二进制包）
├── nexus-docker-compose.yaml  # 本地 Nexus (docker-compose)
├── nexus-init.groovy          # Nexus 初始化脚本
└── image-pull-secret.sh       # 生成 Kubernetes imagePullSecrets
```

## 快速开始

### 1. 前置准备

下载 Doris 二进制包和 Operator 包：

```bash
cd doris-gke-cluster-v4/build-tools

# 交互式下载（自动检测已下载的包）
./pre-build.sh

# 仅下载不验证
./pre-build.sh --download-only
```

或者手动下载并放入 `../source-packages/` 目录：

- `apache-doris-4.0.4-fe.tar.gz`
- `apache-doris-4.0.4-be.tar.gz`

### 2. 构建镜像并推送到本地 Nexus

```bash
# 完整流程：启动 Nexus → 构建 → 推送 → 验证
./build-all.sh

# 仅本地构建，不推 Nexus（用于调试）
./build-all.sh --local-only

# 指定版本
./build-all.sh -- 4.0.4

# 跳过构建，仅推送已有镜像
./build-all.sh --skip-build

# 自定义 Nexus 地址
./build-all.sh --nexus-host 192.168.1.100:5000
```

### 3. 配置 Kubernetes 使用 Nexus

生成 imagePullSecrets 配置：

```bash
# 生成 Secret YAML（适用于 k8s-local 或 k8s-gke）
./image-pull-secret.sh > ../k8s-local/nexus-secret.yaml

# 或者指定 Nexus 地址
NEXUS_HOST=192.168.1.100:5000 NEXUS_PASSWORD=admin123 \
  ./image-pull-secret.sh > ../k8s-gke/secret.yaml
```

## 构建流程详解

```
┌──────────────────────────────────────────────────────────────┐
│                     build-all.sh 流程                          │
├──────────────────────────────────────────────────────────────┤
│                                                               │
│  1. [check]    检查 Docker、buildx、curl 等工具                │
│                                                               │
│  2. [nexus]    启动 Nexus (docker-compose)                     │
│               └─ nexus-docker-compose.yaml                     │
│               └─ 等待 Nexus HTTP 200                          │
│                                                               │
│  3. [login]    Docker login Nexus                             │
│                                                               │
│  4. [build]    构建镜像                                        │
│               ├─ FE:      apache-doris-fe:4.0.4                │
│               ├─ BE:      apache-doris-be:4.0.4                │
│               ├─ FDB:     foundationdb:7.1.37               │
│               └─ Operator: doris-operator:1.4.0               │
│                                                               │
│  5. [push]     推送镜像到 Nexus                                │
│               └─ localhost:5000/doris/fe:4.0.4                 │
│               └─ localhost:5000/doris/be:4.0.4                │
│               └─ localhost:5000/doris/fdb:7.1.37              │
│               └─ localhost:5000/doris/operator:1.4.0           │
│                                                               │
│  6. [verify]   验证镜像完整性                                   │
│                                                               │
│  7. [config]   生成 image-config.env 供部署使用                 │
│                                                               │
└──────────────────────────────────────────────────────────────┘
```

## Nexus 访问

| 服务 | 地址 |
|------|------|
| Docker Registry API | `http://localhost:5000` |
| Nexus Web UI | `http://localhost:8081` |
| 默认账号 | `admin` / `admin123` |

### Docker pull/push 示例

```bash
# 登录
docker login localhost:5000 -u admin -p admin123

# 拉取镜像
docker pull localhost:5000/doris/fe:4.0.4
docker pull localhost:5000/doris/be:4.0.4

# 打标签推送到远程 Nexus
docker tag localhost:5000/doris/fe:4.0.4 nexus.company.com:8082/doris/fe:4.0.4
docker push nexus.company.com:8082/doris/fe:4.0.4
```

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `DORIS_VERSION` | 4.0.4 | Doris 版本 |
| `OPERATOR_VERSION` | 1.4.0 | Doris Operator 版本 |
| `FDB_VERSION` | 7.1.37 | FoundationDB 版本 |
| `NEXUS_HOST` | localhost:5000 | Nexus Docker Registry 地址 |
| `NEXUS_PASSWORD` | admin123 | Nexus 密码 |
| `SOURCE_PACKAGE_DIR` | ../source-packages | 源码包目录 |
| `BUILD_OUTPUT_DIR` | ../build-output | 构建输出目录 |

## 故障排查

### Nexus 启动失败

```bash
# 查看 Nexus 日志
docker compose -f nexus-docker-compose.yaml logs -f nexus

# 重置 Nexus 数据
docker compose -f nexus-docker-compose.yaml down -v
docker volume rm doris-gke-cluster-v4_nexus-data
./build-all.sh
```

### 构建失败：包未找到

```bash
# 检查源码包
ls -la ../source-packages/

# 手动下载
./pre-build.sh
```

### 推送失败：未登录

```bash
docker login localhost:5000 -u admin -p admin123
```

## 自定义配置

### 使用远程 Nexus（生产环境）

```bash
# 设置远程 Nexus
export NEXUS_HOST=nexus.company.com:5000
export NEXUS_PASSWORD=your-password

# 构建并推送
./build-all.sh --skip-nexus-start
```

### 修改默认版本

```bash
export DORIS_VERSION=4.0.4
export OPERATOR_VERSION=1.4.0
./build-all.sh
```

## 清理

```bash
# 清理构建产物
rm -rf ../build-output

# 清理镜像（谨慎）
docker rmi localhost:5000/doris/fe:4.0.4 \
            localhost:5000/doris/be:4.0.4 \
            localhost:5000/doris/fdb:7.1.37 \
            localhost:5000/doris/operator:1.4.0

# 完全清理 Nexus
docker compose -f nexus-docker-compose.yaml down -v
```