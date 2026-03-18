# Doris 系统运维专家指南

## 目录

1. [架构理解](#架构理解)
2. [部署管理](#部署管理)
3. [监控告警](#监控告警)
4. [故障排查](#故障排查)
5. [性能调优](#性能调优)
6. [备份恢复](#备份恢复)
7. [安全管理](#安全管理)
8. [运维自动化](#运维自动化)

---

## 架构理解

### 整体架构

```
┌─────────────────────────────────────────────────────────────┐
│                        用户层                                │
│  (MySQL Client / JDBC / ODBC / Python / BI Tools)           │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      FE (Frontend)                          │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Query Planner  │  Query Optimizer  │  Query Cache  │   │
│  └─────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │        Metadata Management (bdbje)                  │   │
│  │   - 表结构   - 分区信息   - 节点状态                 │   │
│  └─────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │        Connection Manager                           │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                       BE (Backend)                          │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Storage Engine  │  Query Engine  │  Import Manager │   │
│  └─────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │        Storage Layer                                │   │
│  │   - Rowset    - Segment    - Page                   │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### 关键概念

| 组件 | 角色 | 职责 | 高可用 |
|------|------|------|--------|
| **FE** | 元数据管理、查询规划 | Leader + Follower | 3节点部署 |
| **BE** | 数据存储、查询执行 | 无状态 | 多节点部署 |
| **Broker** | 外部存储访问 | 辅助进程 | 按需部署 |

### 端口说明

| 端口 | 组件 | 用途 |
|------|------|------|
| 9030 | FE | 查询端口 (MySQL协议) |
| 8030 | FE | HTTP 端口 |
| 9010 | FE | RPC 端口 (内部通信) |
| 9020 | FE | Edit Log 端口 |
| 9060 | BE | RPC 端口 |
| 8040 | BE | HTTP 端口 |
| 9050 | BE | 心跳端口 |
| 8060 | BE | BRPC 端口 |

---

## 部署管理

### 1. 部署前检查清单

```bash
#!/bin/bash
# preflight-check.sh

echo "=== Doris 部署前检查 ==="

# 系统要求
echo "1. 检查系统版本..."
cat /etc/os-release | head -5

echo "2. 检查内存..."
free -h
if [ $(free -g | awk '/^Mem:/{print $2}') -lt 8 ]; then
    echo "❌ 内存不足 8GB"
    exit 1
fi

echo "3. 检查磁盘..."
df -h
if [ $(df -BG /opt | awk 'NR==2{print $4}' | sed 's/G//') -lt 50 ]; then
    echo "❌ 磁盘空间不足 50GB"
    exit 1
fi

echo "4. 检查 CPU..."
nproc
cat /proc/cpuinfo | grep "model name" | head -1

echo "5. 检查时间同步..."
timedatectl status | grep "NTP enabled"

echo "6. 检查文件描述符限制..."
ulimit -n
if [ $(ulimit -n) -lt 65535 ]; then
    echo "❌ 文件描述符限制过低"
    exit 1
fi

echo "7. 检查 SELinux..."
getenforce
if [ "$(getenforce)" = "Enforcing" ]; then
    echo "⚠️ 建议关闭 SELinux"
fi

echo "8. 检查防火墙..."
systemctl status firewalld || true

echo "=== 检查完成 ==="
```

### 2. 系统参数配置

```bash
#!/bin/bash
# setup-system.sh

echo "=== 配置系统参数 ==="

# 关闭交换分区
swapoff -a
sed -i '/swap/d' /etc/fstab

# 配置内核参数
cat >> /etc/sysctl.conf << EOF
# Doris 优化参数
vm.swappiness = 0
vm.max_map_count = 2000000
fs.file-max = 655360
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_tw_recycle = 0
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.ip_local_port_range = 10000 65535
EOF

sysctl -p

# 配置文件描述符
cat >> /etc/security/limits.conf << EOF
* soft nofile 655350
* hard nofile 655350
* soft nproc 655350
* hard nproc 655350
EOF

# 配置时钟同步
yum install -y chrony
systemctl enable chronyd
systemctl start chronyd

echo "=== 系统配置完成，请重启服务器 ==="
```

### 3. 集群扩容操作

```bash
#!/bin/bash
# scale-cluster.sh

# 扩容 BE 节点
add_be_node() {
    local be_host=$1
    local be_port=9050
    
    echo "添加 BE 节点: $be_host"
    mysql -h fe-leader -P 9030 -u root -e "
        ALTER SYSTEM ADD BACKEND '$be_host:$be_port';
    "
    
    # 在新节点上启动 BE
    ssh $be_host "
        cd /opt/doris/be &&
        ./bin/start_be.sh --daemon
    "
    
    # 等待 BE 上线
    sleep 10
    mysql -h fe-leader -P 9030 -u root -e "
        SHOW PROC '/backends';
    "
}

# 扩容 FE 节点 (Follower)
add_fe_follower() {
    local fe_host=$1
    local edit_log_port=9010
    local http_port=8030
    local query_port=9030
    
    echo "添加 FE Follower: $fe_host"
    mysql -h fe-leader -P 9030 -u root -e "
        ALTER SYSTEM ADD FOLLOWER '$fe_host:$edit_log_port';
    "
    
    # 在新节点上启动 FE (helper 指向 Leader)
    ssh $fe_host "
        cd /opt/doris/fe &&
        ./bin/start_fe.sh --helper fe-leader:$edit_log_port --daemon
    "
}

# 缩容 BE 节点
drop_be_node() {
    local be_host=$1
    
    echo "缩容 BE 节点: $be_host"
    
    # 获取 Backend ID
    backend_id=$(mysql -h fe-leader -P 9030 -u root -e "
        SHOW PROC '/backends';
    " | grep $be_host | awk '{print $1}')
    
    # 下线节点
    mysql -h fe-leader -P 9030 -u root -e "
        ALTER SYSTEM DECOMMISSION BACKEND '$backend_id';
    "
    
    # 等待数据迁移完成
    while true; do
        pending=$(mysql -h fe-leader -P 9030 -u root -e "
            SHOW PROC '/backends';
        " | grep $be_host | grep "DECOMMISSION")
        
        if [ -z "$pending" ]; then
            break
        fi
        echo "等待数据迁移完成..."
        sleep 30
    done
    
    # 删除节点
    mysql -h fe-leader -P 9030 -u root -e "
        ALTER SYSTEM DROPP BACKEND '$be_host:9050';
    "
}

# 使用示例
add_be_node "be-new-01"
add_be_node "be-new-02"
```

### 4. 滚动升级

```bash
#!/bin/bash
# rolling-upgrade.sh

VERSION="3.0.5"
PACKAGE="apache-doris-${VERSION}-bin-x64.tar.gz"

# 1. 升级 FE (先 Follower，最后 Leader)
upgrade_fe() {
    local fe_host=$1
    local is_leader=$2
    
    echo "升级 FE: $fe_host (Leader: $is_leader)"
    
    # 如果是 Leader，先切换
    if [ "$is_leader" = "true" ]; then
        mysql -h $fe_host -P 9030 -u root -e "
            ALTER SYSTEM LEADER TRANSFER;
        "
        sleep 10
    fi
    
    # 停止 FE
    ssh $fe_host "cd /opt/doris/fe && ./bin/stop_fe.sh"
    
    # 备份元数据
    ssh $fe_host "
        cp -r /opt/doris/fe/doris-meta \
               /opt/doris/fe/doris-meta.backup.$(date +%Y%m%d)
    "
    
    # 更新二进制
    scp $PACKAGE $fe_host:/opt/
    ssh $fe_host "
        tar -xzf /opt/$PACKAGE -C /tmp/ &&
        cp -r /tmp/apache-doris-${VERSION}-bin-x64/fe/* /opt/doris/fe/ &&
        rm -rf /tmp/apache-doris-${VERSION}-bin-x64
    "
    
    # 启动 FE
    ssh $fe_host "cd /opt/doris/fe && ./bin/start_fe.sh --daemon"
    
    # 等待恢复
    sleep 30
    
    # 检查状态
    mysql -h $fe_host -P 9030 -u root -e "SHOW FRONTENDS;"
}

# 2. 升级 BE
upgrade_be() {
    local be_host=$1
    
    echo "升级 BE: $be_host"
    
    # 停止 BE (会自动触发 Tablet 迁移)
    ssh $be_host "cd /opt/doris/be && ./bin/stop_be.sh"
    
    # 更新二进制
    scp $PACKAGE $be_host:/opt/
    ssh $be_host "
        tar -xzf /opt/$PACKAGE -C /tmp/ &&
        cp -r /tmp/apache-doris-${VERSION}-bin-x64/be/* /opt/doris/be/ &&
        rm -rf /tmp/apache-doris-${VERSION}-bin-x64
    "
    
    # 启动 BE
    ssh $be_host "cd /opt/doris/be && ./bin/start_be.sh --daemon"
    
    # 等待恢复
    sleep 30
    
    # 检查状态
    mysql -h fe-leader -P 9030 -u root -e "SHOW BACKENDS;"
}

# 执行升级
upgrade_fe "fe-02" "false"   # Follower
upgrade_fe "fe-03" "false"   # Follower
upgrade_fe "fe-01" "true"    # Leader (最后升级)

for be in be-01 be-02 be-03 be-04; do
    upgrade_be $be
done
```

---

## 监控告警

### 1. 内置监控

```sql
-- 查看 FE 状态
SHOW FRONTENDS;

-- 查看 BE 状态
SHOW BACKENDS;

-- 查看 Broker
SHOW PROC '/brokers';

-- 查看数据库统计
SHOW DATABASES;
SHOW DATA;

-- 查看表统计
SHOW TABLE STATUS FROM database_name;
SHOW DATA FROM table_name;

-- 查看 Tablet 分布
SHOW TABLET FROM table_name;
SHOW PROC '/statistic';

-- 查看副本状态
SHOW PROC '/backends';
SHOW PROC '/statistic';

-- 查看正在执行的查询
SHOW PROCESSLIST;

-- 查看慢查询
SHOW QUERY STATS ORDER BY QueryTime DESC LIMIT 20;
```

### 2. Prometheus 监控配置

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'doris-fe'
    static_configs:
      - targets: ['fe1:8030', 'fe2:8030', 'fe3:8030']
    metrics_path: '/metrics'
    
  - job_name: 'doris-be'
    static_configs:
      - targets: ['be1:8040', 'be2:8040', 'be3:8040', 'be4:8040']
    metrics_path: '/metrics'
```

### 3. 关键监控指标

```yaml
# 关键告警规则
groups:
  - name: doris_alerts
    rules:
      # FE 节点离线
      - alert: DorisFEOffline
        expr: up{job="doris-fe"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Doris FE node offline"
          
      # BE 节点离线
      - alert: DorisBEOffline
        expr: doris_be_is_alive == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Doris BE node offline"
          
      # 磁盘使用率
      - alert: DorisDiskUsageHigh
        expr: (doris_be_disks_total_capacity - doris_be_disks_available_capacity) / doris_be_disks_total_capacity > 0.85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Doris BE disk usage > 85%"
          
      # 内存使用率
      - alert: DorisMemoryUsageHigh
        expr: doris_be_memory_allocated / doris_be_memory_limit > 0.9
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Doris BE memory usage > 90%"
          
      # 查询延迟
      - alert: DorisQueryLatencyHigh
        expr: rate(doris_fe_query_latency_ms_sum[5m]) / rate(doris_fe_query_latency_ms_count[5m]) > 5000
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Doris query latency > 5s"
          
      # 失败 Tablet 数量
      - alert: DorisUnhealthyTablets
        expr: doris_fe_unhealthy_tablet_num > 10
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Doris has {{ $value }} unhealthy tablets"
```

### 4. 健康检查脚本

```bash
#!/bin/bash
# health-check.sh

FE_HOST="127.0.0.1"
FE_PORT="9030"
LOG_FILE="/var/log/doris-health-check.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a $LOG_FILE
}

check_fe() {
    log "Checking FE status..."
    
    result=$(mysql -h $FE_HOST -P $FE_PORT -u root -e "SHOW FRONTENDS;" 2>/dev/null)
    if [ $? -eq 0 ]; then
        fe_count=$(echo "$result" | wc -l)
        log "✓ FE check passed, $fe_count nodes"
        return 0
    else
        log "❌ FE check failed"
        return 1
    fi
}

check_be() {
    log "Checking BE status..."
    
    result=$(mysql -h $FE_HOST -P $FE_PORT -u root -e "SHOW BACKENDS;" 2>/dev/null)
    if [ $? -eq 0 ]; then
        # 检查是否有不健康的 BE
        unhealthy=$(echo "$result" | grep -v "true" | grep -v "Backends" | wc -l)
        if [ $unhealthy -eq 0 ]; then
            log "✓ BE check passed"
            return 0
        else
            log "⚠️ $unhealthy BE nodes are unhealthy"
            return 1
        fi
    else
        log "❌ BE check failed"
        return 1
    fi
}

check_disk() {
    log "Checking disk usage..."
    
    usage=$(df -h /opt/doris | awk 'NR==2{print $5}' | sed 's/%//')
    if [ $usage -gt 85 ]; then
        log "⚠️ Disk usage is ${usage}%"
        return 1
    else
        log "✓ Disk usage is ${usage}%"
        return 0
    fi
}

# 执行检查
failed=0
check_fe || failed=1
check_be || failed=1
check_disk || failed=1

if [ $failed -eq 0 ]; then
    log "=== All checks passed ==="
    exit 0
else
    log "=== Some checks failed ==="
    exit 1
fi
```

---

## 故障排查

### 1. 问题诊断流程

```
用户反馈问题
    │
    ▼
┌─────────────────┐
│ 1. 确认问题现象  │
│ 查看错误信息    │
└─────────────────┘
    │
    ▼
┌─────────────────┐
│ 2. 检查集群状态  │
│ SHOW FRONTENDS  │
│ SHOW BACKENDS   │
└─────────────────┘
    │
    ▼
┌─────────────────┐
│ 3. 查看日志     │
│ FE/BE logs      │
└─────────────────┘
    │
    ▼
┌─────────────────┐
│ 4. 定位根因     │
│ 资源/配置/数据   │
└─────────────────┘
    │
    ▼
┌─────────────────┐
│ 5. 修复问题     │
│ 重启/扩容/修复   │
└─────────────────┘
```

### 2. 常见问题排查

#### FE 无法启动

```bash
# 检查元数据
cd /opt/doris/fe/doris-meta
ls -la

# 检查日志
tail -n 100 /opt/doris/fe/log/fe.log
tail -n 100 /opt/doris/fe/log/fe.out

# 常见问题
# 1. 元数据损坏 - 从备份恢复
# 2. 端口冲突 - 检查端口占用
# 3. 内存不足 - 增加 JVM 内存

# 修复元数据
cd /opt/doris/fe
mv doris-meta doris-meta.corrupted
# 从备份恢复
cp -r doris-meta.backup.YYYYMMDD doris-meta
./bin/start_fe.sh
```

#### BE 无法启动

```bash
# 检查日志
tail -n 100 /opt/doris/be/log/be.INFO
tail -n 100 /opt/doris/be/log/be.WARNING

# 常见问题
# 1. 文件描述符不足
ulimit -n
# 修改 /etc/security/limits.conf

# 2. 端口冲突
netstat -tlnp | grep 9060

# 3. 磁盘权限
chown -R doris:doris /opt/doris/be

# 4. 存储路径问题
# 检查 storage_root_path 配置
```

#### 查询超时

```sql
-- 查看当前正在执行的查询
SHOW PROCESSLIST;

-- 杀掉慢查询
KILL QUERY <query_id>;

-- 查看慢查询原因
EXPLAIN <slow_query>;

-- 常见问题
-- 1. 缺少分区裁剪
-- 2. 数据倾斜
-- 3. 缺少统计信息
ANALYZE TABLE problematic_table;
```

#### 数据导入失败

```sql
-- 查看导入任务状态
SHOW LOAD ORDER BY CreateTime DESC LIMIT 10;

-- 查看失败详情
SHOW LOAD WHERE LABEL = 'failed_label';

-- 常见错误
-- 1. ETLError - 数据格式错误
-- 2. TaskError - 任务执行错误
-- 3. Timeout - 超时

-- 查看 BE 导入日志
grep -i "load" /opt/doris/be/log/be.INFO | tail -50
```

### 3. 日志分析

```bash
# FE 日志分析
# 审计日志 - 所有查询
awk '/Query/{print $0}' fe/log/fe.audit.log | tail -100

# 错误日志
grep -i "error\|exception" fe/log/fe.log | tail -50

# BE 日志分析
# 按模块过滤
grep "COMPACTION" be/log/be.INFO | tail -20
grep "SCHEMA_CHANGE" be/log/be.INFO | tail -20
grep "CLONE" be/log/be.INFO | tail -20

# 性能相关
grep "slow" be/log/be.INFO | tail -20
```

---

## 性能调优

### 1. FE 性能调优

```properties
# fe.conf

# JVM 内存 (根据机器内存调整)
JAVA_OPTS="-Xmx8g -Xms8g -XX:+UseG1GC"

# 查询相关
query_timeout = 300
max_running_query_num = 100
max_running_txn_num = 1000

# 元数据
meta_dir = /opt/doris/fe/doris-meta
edit_log_roll_num = 50000

# 连接
max_connections = 1024
thrift_backlog_num = 500
```

### 2. BE 性能调优

```properties
# be.conf

# 内存配置
mem_limit = 80%
total_memory_limit = 64G
disable_mem_pools = false

# 查询线程
fragment_pool_thread_num_max = 128
fragment_pool_queue_size = 2048

# 存储
storage_root_path = /data1/doris;/data2/doris
min_file_descriptor_number = 65536

# Compaction 配置 (影响查询性能)
cumulative_compaction_rounds_for_each_base_compaction_round = 5
max_cumulative_compaction_num_singleton_deltas = 1000
base_compaction_num_threads_per_disk = 2
cumulative_compaction_num_threads_per_disk = 2

# 导入配置
max_send_batch_parallelism_per_job = 5
min_bytes_per_broker_scanner = 67108864
```

### 3. 参数调优决策树

```
查询慢
  │
  ├─> 是否缺少分区裁剪？
  │     └─> 添加分区条件
  │
  ├─> 是否缺少统计信息？
  │     └─> ANALYZE TABLE
  │
  ├─> 是否数据倾斜？
  │     └─> 调整分桶列
  │
  ├─> CPU 是否打满？
  │     └─> 增加 BE 节点
  │
  └─> 内存是否不足？
        └─> 增加 BE 内存或降低并发

导入慢
  │
  ├─> Broker Load？
  │     └─> 增加并发参数
  │
  ├─> Stream Load？
  │     └─> 批量发送
  │
  └─> Routine Load？
        └─> 增加 Kafka 分区
```

---

## 备份恢复

### 1. FE 元数据备份

```bash
#!/bin/bash
# backup-fe-meta.sh

BACKUP_DIR="/backup/doris/fe"
DATE=$(date +%Y%m%d_%H%M%S)

# 创建备份目录
mkdir -p $BACKUP_DIR

# 备份元数据 (在 Leader 上执行)
cd /opt/doris/fe

# 方式 1: 直接复制 (需停止 FE)
# ./bin/stop_fe.sh
# tar -czf $BACKUP_DIR/doris-meta-$DATE.tar.gz doris-meta/
# ./bin/start_fe.sh

# 方式 2: 在线备份 (推荐)
# 使用镜像功能
mysql -h 127.0.0.1 -P 9030 -u root -e "
    CREATE REPOSITORY s3_repo
    WITH S3
    ON LOCATION 's3://bucket/doris-backup'
    PROPERTIES(
        'AWS_ENDPOINT' = 's3.amazonaws.com',
        'AWS_ACCESS_KEY' = 'xxx',
        'AWS_SECRET_KEY' = 'xxx'
    );
    
    BACKUP SNAPSHOT db1.snapshot1 TO s3_repo;
"

# 保留最近 7 天的备份
find $BACKUP_DIR -name "doris-meta-*.tar.gz" -mtime +7 -delete
```

### 2. 数据备份 (EXPORT)

```sql
-- 导出表数据到 S3
EXPORT TABLE db1.large_table TO "s3://bucket/backup/table/"
PROPERTIES (
    "column_separator" = ",",
    "line_delimiter" = "\n",
    "tablet_num_per_task" = "5"
);

-- 查看导出任务
SHOW EXPORT;

-- 取消导出
CANCEL EXPORT WHERE job_id = xxx;
```

### 3. 快照备份

```sql
-- 创建仓库
CREATE REPOSITORY hdfs_repo
WITH HDFS
ON LOCATION '/doris/backup'
PROPERTIES(
    'fs.defaultFS' = 'hdfs://namenode:9000',
    'hadoop.username' = 'hdfs'
);

-- 创建快照
BACKUP SNAPSHOT db1.snapshot_20240101
TO hdfs_repo;

-- 查看快照
SHOW SNAPSHOT ON hdfs_repo;

-- 恢复数据
RESTORE SNAPSHOT db1.snapshot_20240101
FROM hdfs_repo
ON (db1)
PROPERTIES (
    "backup_timestamp" = "2024-01-01-00-00-00-000"
);
```

---

## 安全管理

### 1. 用户权限管理

```sql
-- 创建用户
CREATE USER 'data_engineer'@'%' IDENTIFIED BY 'StrongPassword123!';
CREATE USER 'data_analyst'@'10.0.0.%' IDENTIFIED BY 'AnotherStrongPass!';

-- 创建角色
CREATE ROLE data_reader;
CREATE ROLE data_writer;
CREATE ROLE admin_role;

-- 授权角色
GRANT SELECT ON database1.* TO ROLE data_reader;
GRANT SELECT, INSERT, UPDATE ON database1.* TO ROLE data_writer;
GRANT ALL PRIVILEGES ON *.* TO ROLE admin_role;

-- 赋予角色给用户
GRANT data_reader TO 'data_analyst'@'10.0.0.%';
GRANT data_writer TO 'data_engineer'@'%';

-- 查看权限
SHOW GRANTS FOR 'data_engineer'@'%';
SHOW ROLES;
```

### 2. 网络隔离

```sql
-- 限制用户访问来源
CREATE USER 'etl_user'@'10.0.1.10' IDENTIFIED BY 'password';
CREATE USER 'bi_user'@'10.0.2.%' IDENTIFIED BY 'password';

-- 白名单配置 (fe.conf)
# enable_white_list = true
# white_list = 10.0.0.0/8,172.16.0.0/12
```

### 3. 数据加密

```properties
# SSL 配置 (fe.conf)
enable_ssl = true
ssl_keystore_path = /opt/doris/fe/conf/keystore.jks
ssl_keystore_password = changeit

# 传输加密 (be.conf)
enable_tls = true
tls_certificate_path = /opt/doris/be/conf/cert.pem
tls_private_key_path = /opt/doris/be/conf/key.pem
```

---

## 运维自动化

### 1. Ansible 部署剧本

```yaml
# deploy-doris.yml
---
- name: Deploy Doris Cluster
  hosts: all
  become: yes
  vars:
    doris_version: "3.0.5"
    fe_nodes: "{{ groups['fe'] }}"
    be_nodes: "{{ groups['be'] }}"
  
  tasks:
    - name: Install dependencies
      yum:
        name: 
          - java-11-openjdk
          - mysql
          - wget
        state: present
    
    - name: Create Doris user
      user:
        name: doris
        system: yes
        home: /opt/doris
    
    - name: Download Doris
      get_url:
        url: "https://apache-doris-releases.oss-accelerate.aliyuncs.com/apache-doris-{{ doris_version }}-bin-x64.tar.gz"
        dest: /tmp/doris.tar.gz
    
    - name: Extract Doris
      unarchive:
        src: /tmp/doris.tar.gz
        dest: /opt/
        remote_src: yes
        owner: doris
        group: doris
    
    - name: Configure FE
      template:
        src: fe.conf.j2
        dest: /opt/doris/fe/conf/fe.conf
      when: inventory_hostname in groups['fe']
    
    - name: Configure BE
      template:
        src: be.conf.j2
        dest: /opt/doris/be/conf/be.conf
      when: inventory_hostname in groups['be']
    
    - name: Start FE
      shell: su - doris -c "/opt/doris/fe/bin/start_fe.sh --daemon"
      when: inventory_hostname in groups['fe']
    
    - name: Start BE
      shell: su - doris -c "/opt/doris/be/bin/start_be.sh --daemon"
      when: inventory_hostname in groups['be']

# hosts.ini
[fe]
fe1 ansible_host=192.168.1.10
fe2 ansible_host=192.168.1.11
fe3 ansible_host=192.168.1.12

[be]
be1 ansible_host=192.168.1.20
be2 ansible_host=192.168.1.21
be3 ansible_host=192.168.1.22
be4 ansible_host=192.168.1.23
```

### 2. 定时任务脚本

```bash
#!/bin/bash
# crontab -e

# 每日健康检查
0 9 * * * /opt/doris/scripts/health-check.sh >> /var/log/doris-health.log 2>&1

# 每日元数据备份
0 2 * * * /opt/doris/scripts/backup-fe-meta.sh >> /var/log/doris-backup.log 2>&1

# 每周统计信息收集
0 3 * * 0 /opt/doris/scripts/analyze-all-tables.sh >> /var/log/doris-analyze.log 2>&1

# 每月清理旧日志
0 4 1 * * find /opt/doris/*/log -name "*.log.*" -mtime +30 -delete
```

### 3. 运维工具集

```bash
#!/bin/bash
# doris-admin.sh - Doris 运维工具集

FE_HOST="127.0.0.1"
FE_PORT="9030"

case "$1" in
    status)
        echo "=== FE Status ==="
        mysql -h $FE_HOST -P $FE_PORT -u root -e "SHOW FRONTENDS;"
        echo ""
        echo "=== BE Status ==="
        mysql -h $FE_HOST -P $FE_PORT -u root -e "SHOW BACKENDS;"
        ;;
    
    stats)
        echo "=== Database Stats ==="
        mysql -h $FE_HOST -P $FE_PORT -u root -e "SHOW DATA;"
        echo ""
        echo "=== Tablet Stats ==="
        mysql -h $FE_HOST -P $FE_PORT -u root -e "SHOW PROC '/statistic';"
        ;;
    
    top-queries)
        echo "=== Top 10 Slow Queries ==="
        mysql -h $FE_HOST -P $FE_PORT -u root -e "
            SHOW QUERY STATS 
            ORDER BY QueryTime DESC 
            LIMIT 10;
        "
        ;;
    
    kill-slow)
        # 杀掉执行超过 5 分钟的查询
        mysql -h $FE_HOST -P $FE_PORT -u root -e "
            SHOW PROCESSLIST;
        " | awk '$6 > 300 {print $1}' | while read id; do
            echo "Killing query $id"
            mysql -h $FE_HOST -P $FE_PORT -u root -e "KILL QUERY $id;"
        done
        ;;
    
    repair)
        echo "=== Repairing Unhealthy Tablets ==="
        mysql -h $FE_HOST -P $FE_PORT -u root -e "ADMIN REPAIR TABLE db1.*;"
        ;;
    
    compact)
        echo "=== Triggering Compaction ==="
        mysql -h $FE_HOST -P $FE_PORT -u root -e "ALTER TABLE db1.large_table SET ('enable_single_replica_compaction' = 'true');"
        ;;
    
    *)
        echo "Usage: $0 {status|stats|top-queries|kill-slow|repair|compact}"
        exit 1
        ;;
esac
```

---

## 运维检查清单

### 日常检查

- [ ] FE/BE 节点状态正常
- [ ] 磁盘使用率 < 80%
- [ ] 内存使用率 < 85%
- [ ] 无 Failed Tablet
- [ ] 无慢查询堆积

### 每周检查

- [ ] 统计信息已更新
- [ ] Compaction 进度正常
- [ ] 备份任务成功执行
- [ ] 日志清理完成

### 每月检查

- [ ] 集群容量规划评估
- [ ] 慢查询分析优化
- [ ] 安全补丁更新
- [ ] 运维文档更新

---

## 联系支持

遇到问题时的处理流程：

1. 查看 [Doris 官方文档](https://doris.apache.org/docs/)
2. 搜索 [GitHub Issues](https://github.com/apache/doris/issues)
3. 加入 [Doris 社区 Slack](https://join.slack.com/t/apachedoris/shared_invite/...)
4. 发送邮件到 dev@doris.apache.org
