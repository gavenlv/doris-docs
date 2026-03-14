# Doris Docker Compose 本地开发环境

## 概述

这是一个最小资源配置、高可用的 Doris 本地开发环境，使用 Docker Compose 部署。

**支持平台**：
- ✅ Windows 10/11 + Docker Desktop
- ✅ Linux (Ubuntu, CentOS, etc.)
- ✅ macOS + Docker Desktop

## 架构

### 组件配置

| 组件 | 节点数 | 内存限制 | 说明 |
|------|--------|----------|------|
| FoundationDB | 3 | 1GB | 元数据存储，高可用 |
| Doris FE | 3 | 2GB | 前端节点，高可用 |
| Doris BE | 3 | 4GB | 后端节点，高可用 |
| Prometheus | 1 | 256MB | 监控（可选）|
| Grafana | 1 | 256MB | 可视化（可选）|

**总资源需求**：约 21GB 内存（含监控约 22GB）

### 高可用设计

- **FE 集群**：3 节点，支持 Leader 故障自动切换
- **BE 集群**：3 节点，支持负载均衡和故障恢复
- **FDB 集群**：3 节点，保证元数据高可用

## 快速开始

### 前置要求

- **Docker Desktop** (Windows/macOS) 或 **Docker Engine** (Linux) 20.10+
- **Docker Compose** 2.0+
- **MySQL Client**（可选，用于连接测试）
- 至少 **24GB 可用内存**

### Windows 用户

#### 1. 安装 Docker Desktop
- 下载并安装 [Docker Desktop for Windows](https://www.docker.com/products/docker-desktop)
- 确保 Docker Desktop 正在运行
- 确保 WSL 2 已启用（Docker Desktop 会自动提示）

#### 2. 启动集群
```powershell
# 双击运行或在 PowerShell 中执行
.\start.bat

# 或使用 Docker Compose 命令
docker-compose up -d
```

#### 3. 初始化集群（等待 1-2 分钟）
```powershell
.\init-cluster.bat
```

#### 4. 测试集群
```powershell
.\test-cluster.bat
```

#### 5. 查看状态
```powershell
.\health-check.bat
```

#### 其他 Windows 命令
```powershell
.\stop.bat           # 停止集群
.\cleanup.bat        # 清理环境
.\reset-cluster.bat  # 重置集群
.\view-logs.bat      # 查看日志
```

### Linux/macOS 用户

#### 1. 配置环境变量（可选）
```bash
# 复制环境变量模板
cp .env.example .env

# 编辑配置（可选）
vi .env
```

#### 2. 启动集群
```bash
# 给脚本添加执行权限
chmod +x scripts/*.sh

# 启动集群
./scripts/start.sh
```

#### 3. 初始化集群（等待 1-2 分钟）
```bash
./scripts/init-cluster.sh
```

#### 4. 验证集群
```bash
# 运行测试脚本
./scripts/test-cluster.sh
```

## 连接集群

### MySQL 连接

```bash
# 连接到 Doris
mysql -h 127.0.0.1 -P 9030 -u root

# 查看前端节点
SHOW FRONTENDS;

# 查看后端节点
SHOW BACKENDS;
```

### Web UI 访问

- **FE Master UI**: http://localhost:8030
- **FE Slave1 UI**: http://localhost:8031
- **FE Slave2 UI**: http://localhost:8032

### 监控访问（如果启用）

```bash
# 启动监控
ENABLE_MONITORING=true ./scripts/start.sh

# 访问地址
# Prometheus: http://localhost:9090
# Grafana: http://localhost:3000 (admin/admin)
```

## 常用操作

### 查看集群状态

```bash
# 查看容器状态
docker-compose ps

# 查看 FE 日志
docker-compose logs -f fe1

# 查看 BE 日志
docker-compose logs -f be1

# 查看所有日志
docker-compose logs -f
```

### 扩缩容（测试用）

```bash
# 扩展 BE 节点（需要手动配置 docker-compose.yml）
docker-compose up -d be4

# 添加新 BE 到集群
mysql -h 127.0.0.1 -P 9030 -u root -e "ALTER SYSTEM ADD BACKEND 'be4:9050';"
```

### 停止集群

```bash
# 停止集群（保留数据）
./scripts/stop.sh

# 停止并删除数据
docker-compose down -v
```

## 性能测试

### 简单性能测试

```bash
# 创建大表测试
mysql -h 127.0.0.1 -P 9030 -u root <<EOF
CREATE DATABASE IF NOT EXISTS perf_test;
USE perf_test;

CREATE TABLE lineorder (
    lo_orderkey INT,
    lo_linenumber INT,
    lo_custkey INT,
    lo_partkey INT,
    lo_suppkey INT,
    lo_orderdate DATE,
    lo_orderpriority VARCHAR(16),
    lo_shippriority INT,
    lo_quantity INT,
    lo_extendedprice DECIMAL(10,2),
    lo_ordtotalprice DECIMAL(10,2),
    lo_discount DECIMAL(10,2),
    lo_revenue DECIMAL(10,2),
    lo_supplycost DECIMAL(10,2),
    lo_tax INT,
    lo_commitdate DATE,
    lo_shipmode VARCHAR(11)
) ENGINE=OLAP
DUPLICATE KEY(lo_orderkey)
PARTITION BY RANGE(lo_orderdate) (
    PARTITION p1993 VALUES LESS THAN ('1994-01-01'),
    PARTITION p1994 VALUES LESS THAN ('1995-01-01'),
    PARTITION p1995 VALUES LESS THAN ('1996-01-01'),
    PARTITION p1996 VALUES LESS THAN ('1997-01-01'),
    PARTITION p1997 VALUES LESS THAN ('1998-01-01'),
    PARTITION p1998 VALUES LESS THAN ('1999-01-01')
)
DISTRIBUTED BY HASH(lo_orderkey) BUCKETS 12
PROPERTIES (
    "replication_num" = "1"
);
EOF
```

## 故障排查

### FE 无法启动

```bash
# 检查 FE 日志
docker-compose logs fe1

# 常见问题：
# 1. 内存不足 - 调整 .env 中的 FE_MEMORY_LIMIT
# 2. 端口冲突 - 修改 .env 中的端口配置
# 3. FDB 未就绪 - 等待 FDB 完全启动
```

### BE 无法连接到 FE

```bash
# 检查网络
docker network inspect doris-local

# 重启 BE 节点
docker-compose restart be1 be2 be3

# 重新添加 BE
mysql -h 127.0.0.1 -P 9030 -u root -e "ALTER SYSTEM ADD BACKEND 'be1:9050';"
```

### 性能问题

```bash
# 检查资源使用
docker stats

# 调整内存限制
# 编辑 .env 文件，增加内存限制
FE_MEMORY_LIMIT=3g
BE_MEMORY_LIMIT=6g

# 重启集群
docker-compose down
./scripts/start.sh
```

## 配置调优

### 调整内存配置

编辑 `.env` 文件：

```bash
# 最小配置（21GB）
FE_MEMORY_LIMIT=2g
BE_MEMORY_LIMIT=4g
FDB_MEMORY_LIMIT=1g

# 推荐配置（30GB）
FE_MEMORY_LIMIT=3g
BE_MEMORY_LIMIT=8g
FDB_MEMORY_LIMIT=1g
```

### 调整 FE 配置

编辑 `configs/fe/fe.conf`：

```properties
# 增加 Java 堆内存
JAVA_OPTS = "-Xmx2048m -Xms1024m -XX:+UseG1GC"

# 增加最大连接数
max_conn_per_user = 200

# 启用查询缓存
qcache_max_size_mb = 256
```

### 调整 BE 配置

编辑 `configs/be/be.conf`：

```properties
# 增加扫描线程
scan_thread_pool_thread_num = 64

# 增加内存限制
mem_limit = 8589934592

# 优化 Compaction
compaction_thread_num_per_disk = 4
```

## 网络配置

### 自定义网络

默认使用 Docker 桥接网络，可以通过 `.env` 修改：

```bash
NETWORK_NAME=doris-local
```

### 端口映射

| 服务 | 容器端口 | 主机端口 | 说明 |
|------|----------|----------|------|
| FE1 | 8030,9030 | 8030,9030 | HTTP, MySQL |
| FE2 | 8030,9030 | 8031,9031 | HTTP, MySQL |
| FE3 | 8030,9030 | 8032,9032 | HTTP, MySQL |
| BE1 | 8040,9050 | 8040,9050 | HTTP, Heartbeat |
| BE2 | 8040,9050 | 8041,9051 | HTTP, Heartbeat |
| BE3 | 8040,9050 | 8042,9052 | HTTP, Heartbeat |

## 数据持久化

所有数据存储在 Docker volumes 中：

```bash
# 查看数据卷
docker volume ls | grep doris

# 备份数据
docker run --rm -v doris-local_fe1-data:/data -v $(pwd):/backup alpine tar czf /backup/fe1-backup.tar.gz -C /data .

# 恢复数据
docker run --rm -v doris-local_fe1-data:/data -v $(pwd):/backup alpine tar xzf /backup/fe1-backup.tar.gz -C /data
```

## 与 GKE 生产环境对比

| 特性 | 本地环境 | GKE 生产环境 |
|------|----------|-------------|
| 节点数 | FE:3, BE:3 | FE:3, BE:2-25 (弹性) |
| 内存 | FE:2G, BE:4G | FE:16G, BE:64G |
| 存储 | Docker Volume | Local SSD + GCS |
| 网络 | Docker Bridge | Private VPC |
| 高可用 | ✓ | ✓ |
| 自动扩缩容 | ✗ | ✓ |
| 监控 | Prometheus | Prometheus + Grafana |
| 成本 | 免费 | ~$4,101/月 |

## 注意事项

1. **资源限制**：本地环境使用最小资源配置，性能不如生产环境
2. **数据持久化**：停止容器不会删除数据，需要使用 `docker-compose down -v` 清除
3. **网络隔离**：本地环境使用 Docker 网络，不支持跨主机访问
4. **监控可选**：监控组件默认不启动，需要手动启用
5. **适用场景**：仅用于开发测试，不建议用于生产环境

## 升级版本

```bash
# 1. 停止集群
./scripts/stop.sh

# 2. 修改 .env 中的版本号
DORIS_VERSION=3.1.5

# 3. 拉取新镜像
docker-compose pull

# 4. 启动集群
./scripts/start.sh
```

## 许可证

Apache License 2.0
