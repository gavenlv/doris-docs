# Build Tools

本地构建 Docker 镜像并推送到私有 Nexus 的完整工具链。

## 目录结构

```
build-tools/
├── README.md                  # 本文档
├── build-all.sh               # 完整构建流程：启动 Nexus → 构建 → 推送
├── pre-build.sh               # 前置准备：下载 Doris/FDB 离线包
├── nexus-docker-compose.yaml  # 本地 Nexus (docker-compose)
└── nexus-init.groovy          # Nexus 初始化脚本（自动创建 Docker 仓库）
```

## 快速开始

### 1. 下载离线包

```bash
cd build-tools
./pre-build.sh

# 仅下载不验证
./pre-build.sh --download-only
```

下载后，`offline-packages/` 目录结构：

```
offline-packages/
├── apache-doris-4.0.4-bin-x64.tar.gz    # Doris 统一包
└── foundationdb/                           # FDB DEB 包
    ├── foundationdb-clients_7.1.37_amd64.deb
    └── foundationdb-server_7.1.37_amd64.deb
```

### 2. 构建镜像并推送到 Nexus

```bash
# 完整流程：启动 Nexus → 构建 → 推送 → 验证
./build-all.sh

# 仅本地构建，不推 Nexus（用于调试）
./build-all.sh --local-only

# 跳过构建，仅推送已有镜像
./build-all.sh --skip-build

# 指定 Nexus 地址
./build-all.sh --nexus-host 192.168.1.100:5000
```

## 构建流程

```
┌──────────────────────────────────────────────────────────────┐
│                     build-all.sh 流程                          │
├──────────────────────────────────────────────────────────────┤
│  1. [check]    检查 Docker、buildx、curl 等工具               │
│  2. [nexus]    启动 Nexus (docker-compose)                     │
│  3. [login]    Docker login Nexus                             │
│  4. [build]    构建镜像                                        │
│                 ├─ FE:      apache/doris:4.0.4                 │
│                 ├─ BE:      apache/doris:4.0.4                 │
│                 └─ FDB:     foundationdb:7.1.37               │
│  5. [push]     推送镜像到 Nexus                                │
│                 └─ localhost:5000/doris/fe:4.0.4              │
│  6. [verify]   验证镜像完整性                                   │
└──────────────────────────────────────────────────────────────┘
```

## Nexus 访问

| 服务 | 地址 |
|------|------|
| Docker Registry API | `http://localhost:5000` |
| Nexus Web UI | `http://localhost:8081` |
| 默认账号 | `admin` / `admin123` |

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `DORIS_VERSION` | 4.0.4 | Doris 版本 |
| `OPERATOR_VERSION` | 1.4.0 | Doris Operator 版本 |
| `FDB_VERSION` | 7.1.37 | FoundationDB 版本 |
| `NEXUS_HOST` | localhost:5000 | Nexus 地址 |
| `NEXUS_PASSWORD` | admin123 | Nexus 密码 |
| `OFFLINE_PACKAGES_DIR` | ../offline-packages | 离线包目录 |

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
# 检查离线包
ls -la ../offline-packages/

# 重新下载
./pre-build.sh
```

### 推送失败：未登录

```bash
docker login localhost:5000 -u admin -p admin123
```

## 下一步

镜像构建完成后，部署到 Kubernetes：

- **本地 (Docker Desktop K8s)**:
  ```bash
  cd ../k8s-local && ./deploy.sh
  ```

- **GKE**:
  ```bash
  cd ../k8s-gke && ./deploy.sh
  ```
