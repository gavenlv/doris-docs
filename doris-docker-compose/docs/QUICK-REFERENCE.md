# Doris Local 快速参考卡

## 🚀 快速启动

```bash
# 1. 启动集群
./scripts/start.sh

# 2. 初始化集群（等待 1-2 分钟后执行）
./scripts/init-cluster.sh

# 3. 测试集群
./scripts/test-cluster.sh

# 4. 连接集群
mysql -h 127.0.0.1 -P 9030 -u root
```

## 📋 常用命令

### 集群管理

| 命令 | 说明 |
|------|------|
| `./scripts/start.sh` | 启动集群 |
| `./scripts/stop.sh` | 停止集群 |
| `./scripts/init-cluster.sh` | 初始化 BE 节点 |
| `./scripts/health-check.sh` | 健康检查 |
| `./scripts/test-cluster.sh` | 测试集群 |
| `./scripts/cleanup.sh` | 清理环境 |
| `./scripts/reset-cluster.sh` | 重置集群 |

### Docker 命令

| 命令 | 说明 |
|------|------|
| `docker-compose ps` | 查看容器状态 |
| `docker-compose logs -f` | 查看所有日志 |
| `docker-compose logs -f fe1` | 查看 FE 日志 |
| `docker-compose logs -f be1` | 查看 BE 日志 |
| `docker-compose restart` | 重启所有服务 |
| `docker-compose down` | 停止并删除容器 |
| `docker-compose down -v` | 停止并删除数据 |
| `docker stats` | 查看资源使用 |

### MySQL 命令

| 命令 | 说明 |
|------|------|
| `mysql -h 127.0.0.1 -P 9030 -u root` | 连接集群 |
| `SHOW FRONTENDS;` | 查看 FE 节点 |
| `SHOW BACKENDS;` | 查看 BE 节点 |
| `SHOW DATABASES;` | 查看数据库 |
| `SHOW TABLES;` | 查看表 |
| `SHOW PROCESSLIST;` | 查看连接 |

## 🔧 配置文件

| 文件 | 说明 |
|------|------|
| `.env` | 环境变量配置 |
| `configs/fe/fe.conf` | FE 配置文件 |
| `configs/be/be.conf` | BE 配置文件 |
| `configs/fdb/fdb.cluster` | FDB 集群配置 |
| `configs/prometheus/prometheus.yml` | Prometheus 配置 |

## 🌐 访问地址

| 服务 | 地址 | 说明 |
|------|------|------|
| FE Master | http://localhost:8030 | FE Web UI |
| MySQL | 127.0.0.1:9030 | MySQL 连接 |
| Prometheus | http://localhost:9090 | 监控（需启用）|
| Grafana | http://localhost:3000 | 可视化（需启用）|

## 📊 端口映射

| 服务 | 容器端口 | 主机端口 |
|------|----------|----------|
| FE1 | 8030,9030 | 8030,9030 |
| FE2 | 8030,9030 | 8031,9031 |
| FE3 | 8030,9030 | 8032,9032 |
| BE1 | 8040,9050 | 8040,9050 |
| BE2 | 8040,9050 | 8041,9051 |
| BE3 | 8040,9050 | 8042,9052 |

## 💾 资源配置

| 组件 | 节点数 | 内存 | 说明 |
|------|--------|------|------|
| FE | 3 | 2GB | 高可用 |
| BE | 3 | 4GB | 高可用 |
| FDB | 3 | 1GB | 元数据存储 |

**总资源需求**: 约 21GB 内存

## 🐛 故障排查

### FE 无法启动
```bash
# 查看日志
docker-compose logs fe1

# 检查端口占用
netstat -tuln | grep 8030

# 清理重启
./scripts/reset-cluster.sh
```

### BE 无法连接
```bash
# 检查 FE 状态
curl http://localhost:8030/api/bootstrap

# 重新添加 BE
mysql -h 127.0.0.1 -P 9030 -u root -e "ALTER SYSTEM ADD BACKEND 'be1:9050';"
```

### 性能慢
```bash
# 查看资源使用
docker stats

# 增加内存限制（编辑 .env）
FE_MEMORY_LIMIT=3g
BE_MEMORY_LIMIT=6g

# 重启集群
docker-compose down && ./scripts/start.sh
```

## 📝 常用 SQL

### 创建数据库和表
```sql
CREATE DATABASE test;
USE test;

CREATE TABLE users (
    id INT,
    name VARCHAR(100),
    age INT,
    created_at DATETIME
) ENGINE=OLAP
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 3
PROPERTIES ("replication_num" = "1");
```

### 数据导入
```sql
-- INSERT
INSERT INTO users VALUES (1, 'Alice', 25, '2024-01-01 10:00:00');

-- Stream Load（大数据量）
curl --location-trusted -u root: \
    -T data.csv \
    http://localhost:8030/api/test/users/_stream_load
```

### 查询示例
```sql
-- 简单查询
SELECT * FROM users LIMIT 10;

-- 聚合查询
SELECT age, COUNT(*) FROM users GROUP BY age;

-- 关联查询
SELECT a.*, b.name 
FROM orders a 
JOIN users b ON a.user_id = b.id;
```

## 🎯 监控启用

```bash
# 方法1: 修改 .env
ENABLE_MONITORING=true
./scripts/start.sh

# 方法2: 直接启动
docker-compose --profile monitoring up -d

# 访问监控
# Prometheus: http://localhost:9090
# Grafana: http://localhost:3000 (admin/admin)
```

## 🔄 备份与恢复

### 备份数据
```bash
# 备份 FE 数据
docker run --rm \
    -v doris-local_fe1-data:/data \
    -v $(pwd):/backup \
    alpine tar czf /backup/fe-backup.tar.gz -C /data .

# 备份 BE 数据
docker run --rm \
    -v doris-local_be1-data:/data \
    -v $(pwd):/backup \
    alpine tar czf /backup/be-backup.tar.gz -C /data .
```

### 恢复数据
```bash
# 恢复 FE 数据
docker run --rm \
    -v doris-local_fe1-data:/data \
    -v $(pwd):/backup \
    alpine tar xzf /backup/fe-backup.tar.gz -C /data

# 重启集群
docker-compose restart
```

## 📚 更多资源

- **详细文档**: `README.md`
- **故障排查**: `docs/TROUBLESHOOTING.md`
- **官方文档**: https://doris.apache.org
- **GitHub**: https://github.com/apache/doris

## ⚡ 快速诊断

```bash
# 一键健康检查
./scripts/health-check.sh

# 查看集群状态
mysql -h 127.0.0.1 -P 9030 -u root -e "SHOW FRONTENDS; SHOW BACKENDS;"

# 查看资源使用
docker stats --no-stream | grep doris
```
