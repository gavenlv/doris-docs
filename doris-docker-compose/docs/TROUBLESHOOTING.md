# 故障排查指南

## 常见问题

### 1. FE 启动失败

#### 症状
- FE 容器无法启动或启动后立即退出
- 日志显示 `OutOfMemoryError` 或端口冲突

#### 解决方案

**检查内存配置**
```bash
# 查看容器日志
docker-compose logs fe1

# 如果是内存不足，调整 .env
FE_MEMORY_LIMIT=3g
```

**检查端口冲突**
```bash
# 检查端口占用
netstat -tuln | grep -E '8030|9030|9010'

# 如果端口被占用，修改 .env
FE_HTTP_PORT=18030
FE_QUERY_PORT=19030
```

**清理并重启**
```bash
# 清理数据并重启
./scripts/reset-cluster.sh
```

---

### 2. BE 无法连接到 FE

#### 症状
- BE 节点状态显示为 `Dead` 或 `Unalive`
- 日志显示连接 FE 失败

#### 解决方案

**检查网络连接**
```bash
# 进入 BE 容器
docker exec -it doris-be1 bash

# 测试与 FE 的连接
ping fe1
telnet fe1 9020
```

**检查 FE 状态**
```bash
# 检查 FE 是否正常
curl http://localhost:8030/api/bootstrap

# 查看 FE 日志
docker-compose logs fe1
```

**重新添加 BE 节点**
```bash
# 删除旧的 BE 节点
mysql -h 127.0.0.1 -P 9030 -u root -e "ALTER SYSTEM DROP BACKEND 'be1:9050';"
mysql -h 127.0.0.1 -P 9030 -u root -e "ALTER SYSTEM DROP BACKEND 'be2:9050';"
mysql -h 127.0.0.1 -P 9030 -u root -e "ALTER SYSTEM DROP BACKEND 'be3:9050';"

# 重启 BE 节点
docker-compose restart be1 be2 be3

# 重新初始化
./scripts/init-cluster.sh
```

---

### 3. FoundationDB 连接失败

#### 症状
- FE 日志显示无法连接到 FDB
- 启动时报错 `Failed to connect to FDB cluster`

#### 解决方案

**检查 FDB 状态**
```bash
# 检查 FDB 容器是否运行
docker-compose ps fdb1 fdb2 fdb3

# 查看 FDB 日志
docker-compose logs fdb1
```

**验证 FDB 集群配置**
```bash
# 检查集群配置文件
cat configs/fdb/fdb.cluster

# 进入 FDB 容器测试
docker exec -it doris-fdb1 fdbcli --exec "status"
```

**重启 FDB 集群**
```bash
# 重启所有 FDB 节点
docker-compose restart fdb1 fdb2 fdb3

# 等待 10 秒后重启 FE
sleep 10
docker-compose restart fe1 fe2 fe3
```

---

### 4. 查询超时或性能慢

#### 症状
- 查询执行时间过长
- 出现 `Query timeout` 错误

#### 解决方案

**检查资源使用**
```bash
# 查看容器资源使用
docker stats

# 如果资源不足，增加内存限制
# 编辑 .env
BE_MEMORY_LIMIT=6g
FE_MEMORY_LIMIT=3g

# 重启集群
docker-compose down
./scripts/start.sh
```

**优化查询配置**
```bash
# 在 MySQL 客户端执行
SET GLOBAL query_timeout = 600;
SET GLOBAL insert_timeout = 600;
```

**检查 BE 配置**
```properties
# 编辑 configs/be/be.conf
scan_thread_pool_thread_num = 64
compaction_thread_num_per_disk = 4
```

---

### 5. 容器启动顺序问题

#### 症状
- FE 在 FDB 就绪前启动
- BE 在 FE 就绪前启动

#### 解决方案

**手动控制启动顺序**
```bash
# 1. 先启动 FDB
docker-compose up -d fdb1 fdb2 fdb3

# 2. 等待 FDB 就绪
sleep 15

# 3. 启动 FE
docker-compose up -d fe1 fe2 fe3

# 4. 等待 FE 就绪
sleep 30

# 5. 启动 BE
docker-compose up -d be1 be2 be3

# 6. 初始化集群
./scripts/init-cluster.sh
```

---

### 6. 数据丢失或损坏

#### 症状
- 重启后数据丢失
- 表数据不完整

#### 解决方案

**检查数据卷**
```bash
# 查看数据卷是否存在
docker volume ls | grep doris

# 如果数据卷不存在，说明数据已丢失
# 需要重新导入数据
```

**恢复数据**
```bash
# 如果有备份，恢复数据卷
docker run --rm -v doris-local_fe1-data:/data -v $(pwd):/backup alpine tar xzf /backup/fe1-backup.tar.gz -C /data

# 重启集群
docker-compose restart
```

---

### 7. 网络连接问题

#### 症状
- 容器间无法通信
- 客户端无法连接

#### 解决方案

**检查网络**
```bash
# 查看网络
docker network ls
docker network inspect doris-local

# 重建网络
docker-compose down
docker network rm doris-local
docker-compose up -d
```

**检查防火墙**
```bash
# 临时禁用防火墙测试（Linux）
sudo systemctl stop firewalld

# Windows: 检查防火墙规则
# 控制面板 > 系统和安全 > Windows Defender 防火墙
```

---

### 8. MySQL 连接失败

#### 症状
- `mysql -h 127.0.0.1 -P 9030 -u root` 连接失败

#### 解决方案

**检查 FE 是否就绪**
```bash
# 检查 FE HTTP API
curl http://localhost:8030/api/bootstrap

# 如果 API 正常但 MySQL 连接失败，可能是 FE 还在初始化
# 等待 1-2 分钟后重试
```

**检查 MySQL 客户端**
```bash
# 确认 MySQL 客户端已安装
which mysql

# 如果没有安装
# Ubuntu/Debian: sudo apt-get install mysql-client
# CentOS/RHEL: sudo yum install mysql
# macOS: brew install mysql-client
```

---

### 9. 监控数据不显示

#### 症状
- Prometheus 无法采集指标
- Grafana 无法显示数据

#### 解决方案

**检查 Prometheus 配置**
```bash
# 查看 Prometheus 日志
docker-compose logs prometheus

# 检查配置文件
cat configs/prometheus/prometheus.yml

# 访问 Prometheus UI
# http://localhost:9090/targets
```

**检查 FE/BE 指标端口**
```bash
# 测试 FE 指标接口
curl http://localhost:8030/metrics

# 测试 BE 指标接口
curl http://localhost:8040/metrics
```

**重启监控服务**
```bash
docker-compose --profile monitoring restart prometheus grafana
```

---

### 10. 磁盘空间不足

#### 症状
- 容器启动失败
- 日志显示 `No space left on device`

#### 解决方案

**检查磁盘使用**
```bash
# 查看磁盘使用
df -h

# 查看 Docker 磁盘使用
docker system df
```

**清理 Docker 资源**
```bash
# 清理未使用的镜像、容器、网络
docker system prune -a

# 清理所有数据卷（注意：会删除数据）
docker volume prune
```

**调整日志级别**
```properties
# 编辑 configs/fe/fe.conf
sys_log_level = ERROR

# 编辑 configs/be/be.conf
sys_log_level = ERROR
sys_log_roll_size_mb = 128
```

---

## 性能调优

### 1. 优化内存配置

```bash
# 编辑 .env
# 推荐配置（总内存 ≥ 32GB）
FE_MEMORY_LIMIT=4g
BE_MEMORY_LIMIT=8g
FDB_MEMORY_LIMIT=2g

# 最小配置（总内存 16-24GB）
FE_MEMORY_LIMIT=2g
BE_MEMORY_LIMIT=4g
FDB_MEMORY_LIMIT=1g
```

### 2. 优化并发查询

```properties
# configs/fe/fe.conf
max_conn_per_user = 200
qcache_max_size_mb = 512

# configs/be/be.conf
scan_thread_pool_thread_num = 96
scanner_thread_pool_thread_num = 64
```

### 3. 优化 Compaction

```properties
# configs/be/be.conf
compaction_thread_num_per_disk = 4
base_compaction_num_cumulative_deltas = 5
cumulative_compaction_num_deltas_per_round = 500
```

---

## 日志分析

### FE 日志位置
```bash
# 进入 FE 容器
docker exec -it doris-fe1 bash

# 查看日志
tail -f /opt/doris/fe/log/fe.out
tail -f /opt/doris/fe/log/fe.log
```

### BE 日志位置
```bash
# 进入 BE 容器
docker exec -it doris-be1 bash

# 查看日志
tail -f /opt/doris/be/log/be.INFO
tail -f /opt/doris/be/log/be.WARNING
```

### 查看所有日志
```bash
# 实时查看所有服务日志
docker-compose logs -f --tail=100

# 查看特定服务日志
docker-compose logs -f fe1
docker-compose logs -f be1
```

---

## 诊断命令

### 快速诊断
```bash
# 运行健康检查脚本
./scripts/health-check.sh
```

### 检查集群状态
```bash
# MySQL 连接
mysql -h 127.0.0.1 -P 9030 -u root

# 查看 FE 状态
SHOW FRONTENDS\G

# 查看 BE 状态
SHOW BACKENDS;

# 查看表状态
SHOW TABLE STATUS;

# 查看副本状态
SHOW REPLICA STATUS;
```

### 检查系统资源
```bash
# 容器资源使用
docker stats --no-stream

# 磁盘使用
df -h

# 内存使用
free -h

# CPU 使用
top
```

---

## 获取帮助

如果以上方法无法解决问题：

1. **查看日志**
   ```bash
   docker-compose logs --tail=500 > doris-logs.txt
   ```

2. **检查配置**
   ```bash
   # 检查所有配置文件
   cat configs/fe/fe.conf
   cat configs/be/be.conf
   cat configs/fdb/fdb.cluster
   ```

3. **导出诊断信息**
   ```bash
   # 收集诊断信息
   echo "=== Docker Compose PS ===" > diagnostic.txt
   docker-compose ps >> diagnostic.txt
   
   echo "=== Docker Stats ===" >> diagnostic.txt
   docker stats --no-stream >> diagnostic.txt
   
   echo "=== FE Logs ===" >> diagnostic.txt
   docker-compose logs fe1 --tail=100 >> diagnostic.txt
   
   echo "=== BE Logs ===" >> diagnostic.txt
   docker-compose logs be1 --tail=100 >> diagnostic.txt
   ```

4. **社区支持**
   - Apache Doris 官方文档: https://doris.apache.org
   - Doris GitHub Issues: https://github.com/apache/doris/issues
   - Doris 邮件列表: dev@doris.apache.org
