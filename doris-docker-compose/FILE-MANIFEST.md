# Doris Local 环境文件清单

## 📁 目录结构

```
doris-gke-cluster/local/
├── .env.example                           # 环境变量模板
├── docker-compose.yml                      # Docker Compose 主配置文件
├── README.md                               # 主文档
│
├── configs/                                # 配置文件目录
│   ├── fe/
│   │   └── fe.conf                        # FE 配置文件
│   ├── be/
│   │   └── be.conf                        # BE 配置文件
│   ├── fdb/
│   │   └── fdb.cluster                    # FoundationDB 集群配置
│   ├── prometheus/
│   │   └── prometheus.yml                 # Prometheus 监控配置
│   └── grafana/
│       └── provisioning/
│           ├── datasources/
│           │   └── datasources.yml        # Grafana 数据源配置
│           └── dashboards/
│               └── dashboards.yml         # Grafana Dashboard 配置
│
├── scripts/                                # 脚本目录
│   ├── start.sh                           # 启动集群
│   ├── stop.sh                            # 停止集群
│   ├── init-cluster.sh                    # 初始化集群
│   ├── test-cluster.sh                    # 测试集群
│   ├── health-check.sh                    # 健康检查
│   ├── cleanup.sh                         # 清理环境
│   ├── reset-cluster.sh                   # 重置集群
│   └── example-load.sh                    # 数据加载示例
│
├── examples/                               # 示例文件目录
│   └── quick-start.sql                    # SQL 快速入门示例
│
└── docs/                                   # 文档目录
    ├── QUICK-REFERENCE.md                 # 快速参考卡
    ├── TROUBLESHOOTING.md                 # 故障排查指南
    └── ARCHITECTURE-LOCAL.md              # 本地架构说明
```

## 📄 文件说明

### 核心配置文件

| 文件 | 说明 | 是否必需 |
|------|------|----------|
| `.env.example` | 环境变量模板 | 可选（首次运行自动复制）|
| `docker-compose.yml` | Docker Compose 主配置 | ✅ 必需 |
| `configs/fe/fe.conf` | FE 性能配置 | ✅ 必需 |
| `configs/be/be.conf` | BE 性能配置 | ✅ 必需 |
| `configs/fdb/fdb.cluster` | FDB 集群配置 | ✅ 必需 |

### 运维脚本

| 脚本 | 功能 | 使用场景 |
|------|------|----------|
| `start.sh` | 启动集群 | 首次启动或日常启动 |
| `stop.sh` | 停止集群 | 停止服务 |
| `init-cluster.sh` | 初始化集群 | 首次部署时初始化 BE 节点 |
| `test-cluster.sh` | 测试集群 | 验证集群功能 |
| `health-check.sh` | 健康检查 | 诊断集群状态 |
| `cleanup.sh` | 清理环境 | 完全删除集群和数据 |
| `reset-cluster.sh` | 重置集群 | 清空数据并重新部署 |

### 监控配置（可选）

| 文件 | 说明 |
|------|------|
| `configs/prometheus/prometheus.yml` | Prometheus 配置 |
| `configs/grafana/provisioning/datasources/datasources.yml` | Grafana 数据源 |
| `configs/grafana/provisioning/dashboards/dashboards.yml` | Grafana Dashboard |

### 文档

| 文档 | 说明 |
|------|------|
| `README.md` | 主文档（快速开始、使用指南）|
| `docs/QUICK-REFERENCE.md` | 快速参考卡（命令速查）|
| `docs/TROUBLESHOOTING.md` | 故障排查指南 |
| `docs/ARCHITECTURE-LOCAL.md` | 本地架构说明 |

### 示例文件

| 文件 | 说明 |
|------|------|
| `examples/quick-start.sql` | SQL 快速入门示例 |

## 🚀 快速开始

### 1. 进入目录
```bash
cd doris-gke-cluster/local
```

### 2. 启动集群
```bash
# Linux/macOS
./scripts/start.sh

# Windows PowerShell
bash scripts/start.sh
# 或者直接使用 Docker Compose
docker-compose up -d
```

### 3. 初始化集群（等待 1-2 分钟）
```bash
./scripts/init-cluster.sh
```

### 4. 验证集群
```bash
# 运行测试
./scripts/test-cluster.sh

# 或手动连接
mysql -h 127.0.0.1 -P 9030 -u root
```

### 5. 查看状态
```bash
# 健康检查
./scripts/health-check.sh

# 查看容器
docker-compose ps

# 查看日志
docker-compose logs -f
```

## 📊 资源需求

| 组件 | 节点数 | 内存/节点 | 总内存 |
|------|--------|-----------|--------|
| FoundationDB | 3 | 1GB | 3GB |
| Doris FE | 3 | 2GB | 6GB |
| Doris BE | 3 | 4GB | 12GB |
| **总计** | **9** | - | **21GB** |

**推荐配置**: 24GB+ 内存，50GB+ 磁盘空间

## 🌐 服务端口

| 服务 | 端口 | 说明 |
|------|------|------|
| FE Master HTTP | 8030 | Web UI |
| FE Master MySQL | 9030 | MySQL 连接 |
| BE1 HTTP | 8040 | BE 管理 |
| BE1 Heartbeat | 9050 | 心跳检测 |
| Prometheus | 9090 | 监控（可选）|
| Grafana | 3000 | 可视化（可选）|

## 🔧 环境变量

编辑 `.env` 文件自定义配置：

```bash
# 复制模板
cp .env.example .env

# 编辑配置
vi .env
```

主要配置项：
- `DORIS_VERSION`: Doris 版本（默认 3.1.4）
- `FDB_VERSION`: FoundationDB 版本（默认 7.1.37）
- `FE_MEMORY_LIMIT`: FE 内存限制（默认 2g）
- `BE_MEMORY_LIMIT`: BE 内存限制（默认 4g）
- `ENABLE_MONITORING`: 是否启用监控（默认 false）

## 📚 相关文档

- **主文档**: `README.md` - 完整使用指南
- **快速参考**: `docs/QUICK-REFERENCE.md` - 命令速查表
- **故障排查**: `docs/TROUBLESHOOTING.md` - 常见问题解决
- **架构说明**: `docs/ARCHITECTURE-LOCAL.md` - 技术架构详解

## ⚠️ 注意事项

1. **首次启动**: 需要下载 Docker 镜像（约 2-3GB）
2. **初始化时间**: 集群启动后需要 1-2 分钟才能完全就绪
3. **数据持久化**: 数据存储在 Docker volumes 中，`docker-compose down -v` 会删除数据
4. **资源占用**: 确保有足够的内存和磁盘空间
5. **适用场景**: 仅用于本地开发测试，不建议用于生产环境

## 🐛 问题反馈

如遇到问题，请按以下步骤排查：

1. 查看日志: `docker-compose logs -f`
2. 运行健康检查: `./scripts/health-check.sh`
3. 查看故障排查文档: `docs/TROUBLESHOOTING.md`
4. 重置集群: `./scripts/reset-cluster.sh`

## 📝 版本信息

- Doris: 3.1.4
- FoundationDB: 7.1.37
- Prometheus: v2.45.0
- Grafana: 10.2.0
