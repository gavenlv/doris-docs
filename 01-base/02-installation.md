# 安装部署

## 部署方式选择

```
┌─────────────────────────────────────────────────────────────┐
│                    部署方式对比                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Docker 部署 (推荐新手)                              │   │
│  │  - 优点：快速、简单、隔离环境                        │   │
│  │  - 缺点：性能略低                                    │   │
│  │  - 适用：学习、开发、测试                            │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  物理机/虚拟机部署                                   │   │
│  │  - 优点：性能最优、完全控制                          │   │
│  │  - 缺点：配置复杂                                    │   │
│  │  - 适用：生产环境                                    │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Kubernetes 部署                                     │   │
│  │  - 优点：自动化、弹性伸缩                            │   │
│  │  - 缺点：需要 K8s 基础                               │   │
│  │  - 适用：云原生环境                                  │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  云平台部署 (AWS/GCP/阿里云)                         │   │
│  │  - 优点：开箱即用、高可用                            │   │
│  │  - 缺点：成本较高                                    │   │
│  │  - 适用：企业生产                                    │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 方式一：Docker 快速部署

### 前置要求

- Docker 20.0+
- 内存 >= 8GB
- 磁盘 >= 20GB

### 单节点快速启动

```bash
# 1. 创建网络
docker network create doris-network

# 2. 启动 FE
docker run -d \
    --name doris-fe \
    --network doris-network \
    -p 8030:8030 \
    -p 9030:9030 \
    -e FE_SERVERS="doris-fe" \
    -e FE_ID=1 \
    apache/doris:2.0.3-fe

# 3. 等待 FE 启动 (约 30 秒)
sleep 30

# 4. 启动 BE
docker run -d \
    --name doris-be \
    --network doris-network \
    -p 8040:8040 \
    -e FE_SERVERS="doris-fe:9010" \
    -e BE_ADDR="doris-be:9050" \
    apache/doris:2.0.3-be

# 5. 在 FE 中添加 BE
docker exec -it doris-fe mysql -h 127.0.0.1 -P 9030 -u root -e "
ALTER SYSTEM ADD BACKEND 'doris-be:9050';
"

# 6. 验证集群状态
docker exec -it doris-fe mysql -h 127.0.0.1 -P 9030 -u root -e "
SHOW BACKENDS;
SHOW FRONTENDS;
"
```

### 使用 Docker Compose (推荐)

```yaml
# docker-compose.yml
version: '3'

services:
  fe:
    image: apache/doris:2.0.3-fe
    container_name: doris-fe
    hostname: doris-fe
    ports:
      - "8030:8030"
      - "9030:9030"
    environment:
      - FE_SERVERS=doris-fe
      - FE_ID=1
    volumes:
      - ./fe/doris-meta:/opt/apache-doris/fe/doris-meta
    networks:
      - doris-network

  be:
    image: apache/doris:2.0.3-be
    container_name: doris-be
    hostname: doris-be
    ports:
      - "8040:8040"
    environment:
      - FE_SERVERS=doris-fe:9010
      - BE_ADDR=doris-be:9050
    volumes:
      - ./be/storage:/opt/apache-doris/be/storage
    depends_on:
      - fe
    networks:
      - doris-network

networks:
  doris-network:
    driver: bridge
```

```bash
# 启动集群
docker-compose up -d

# 等待启动
sleep 60

# 添加 BE
docker exec -it doris-fe mysql -h 127.0.0.1 -P 9030 -u root -e "
ALTER SYSTEM ADD BACKEND 'doris-be:9050';
"

# 查看状态
docker exec -it doris-fe mysql -h 127.0.0.1 -P 9030 -u root -e "
SHOW BACKENDS;
"
```

---

## 方式二：物理机部署

### 硬件要求

| 组件 | CPU | 内存 | 磁盘 | 网络 |
|------|-----|------|------|------|
| FE | 8+ 核 | 16GB+ | SSD 100GB+ | 1Gbps |
| BE | 16+ 核 | 64GB+ | SSD 1TB+ | 10Gbps |

### 系统要求

```bash
# 关闭防火墙
systemctl stop firewalld
systemctl disable firewalld

# 关闭 SELinux
setenforce 0
sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config

# 设置系统参数
cat >> /etc/sysctl.conf << EOF
vm.max_map_count = 2000000
vm.swappiness = 0
net.core.somaxconn = 65535
EOF
sysctl -p

# 设置文件描述符
cat >> /etc/security/limits.conf << EOF
* soft nofile 655350
* hard nofile 655350
* soft nproc 655350
* hard nproc 655350
EOF

# 关闭透明大页
echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo never > /sys/kernel/mm/transparent_hugepage/defrag
```

### 安装步骤

```bash
# 1. 下载安装包
wget https://dlcdn.apache.org/doris/2.0.3/apache-doris-2.0.3-bin-x64.tar.gz

# 2. 解压
tar -xzf apache-doris-2.0.3-bin-x64.tar.gz
cd apache-doris-2.0.3-bin-x64

# 3. 配置 FE
cd fe
vim conf/fe.conf

# 修改以下配置
meta_dir = /data/doris/fe/doris-meta
priority_networks = 192.168.1.0/24

# 4. 启动 FE
./bin/start_fe.sh --daemon

# 5. 配置 BE
cd ../be
vim conf/be.conf

# 修改以下配置
storage_root_path = /data/doris/be/storage
priority_networks = 192.168.1.0/24

# 6. 启动 BE
./bin/start_be.sh --daemon

# 7. 连接 FE 并添加 BE
mysql -h 192.168.1.10 -P 9030 -u root

# 添加 BE 节点
ALTER SYSTEM ADD BACKEND "192.168.1.11:9050";
ALTER SYSTEM ADD BACKEND "192.168.1.12:9050";
ALTER SYSTEM ADD BACKEND "192.168.1.13:9050";

# 查看集群状态
SHOW BACKENDS;
SHOW FRONTENDS;
```

### FE 高可用部署

```bash
# 在第一台 FE (Leader) 上启动
./bin/start_fe.sh --daemon

# 在其他 FE (Follower) 上启动
# 先获取 Leader 信息
mysql -h fe1 -P 9030 -u root -e "SHOW FRONTENDS;"

# 在 Follower 节点启动
./bin/start_fe.sh --helper fe1:9010 --daemon

# 添加 Follower
ALTER SYSTEM ADD FOLLOWER "fe2:9010";
ALTER SYSTEM ADD FOLLOWER "fe3:9010";

# 添加 Observer (可选)
ALTER SYSTEM ADD OBSERVER "fe4:9010";
```

---

## 方式三：Kubernetes 部署

### 使用 Doris Operator

```yaml
# doris-cluster.yaml
apiVersion: doris.apache.org/v1
kind: DorisCluster
metadata:
  name: doris-cluster
spec:
  feSpec:
    replicas: 3
    image: apache/doris:2.0.3-fe
    config:
      meta_dir: /opt/apache-doris/fe/doris-meta
    resources:
      requests:
        cpu: 4
        memory: 8Gi
      limits:
        cpu: 8
        memory: 16Gi
    persistentVolumes:
    - mountPath: /opt/apache-doris/fe/doris-meta
      name: fe-meta
      resource:
        requests:
          storage: 100Gi
        storageClassName: standard

  beSpec:
    replicas: 3
    image: apache/doris:2.0.3-be
    config:
      storage_root_path: /opt/apache-doris/be/storage
    resources:
      requests:
        cpu: 8
        memory: 16Gi
      limits:
        cpu: 16
        memory: 32Gi
    persistentVolumes:
    - mountPath: /opt/apache-doris/be/storage
      name: be-storage
      resource:
        requests:
          storage: 500Gi
        storageClassName: standard
```

```bash
# 安装 Operator
kubectl apply -f https://raw.githubusercontent.com/apache/doris-operator/master/config/crd/bases/doris.apache.org_dorisclusters.yaml

# 部署集群
kubectl apply -f doris-cluster.yaml

# 查看状态
kubectl get doriscluster
kubectl get pods -l app=doris
```

---

## 连接 Doris

### MySQL 客户端

```bash
# 基本连接
mysql -h 127.0.0.1 -P 9030 -u root

# 指定数据库
mysql -h 127.0.0.1 -P 9030 -u root -D mydb

# 使用密码
mysql -h 127.0.0.1 -P 9030 -u root -p
```

### JDBC 连接

```java
// Java JDBC
String url = "jdbc:mysql://127.0.0.1:9030/mydb";
String user = "root";
String password = "";

Connection conn = DriverManager.getConnection(url, user, password);
Statement stmt = conn.createStatement();
ResultSet rs = stmt.executeQuery("SELECT * FROM users");
```

### Python 连接

```python
# Python
import mysql.connector

conn = mysql.connector.connect(
    host='127.0.0.1',
    port=9030,
    user='root',
    password='',
    database='mydb'
)

cursor = conn.cursor()
cursor.execute("SELECT * FROM users")
for row in cursor:
    print(row)
```

### Web UI

```
FE Web UI: http://127.0.0.1:8030
BE Web UI: http://127.0.0.1:8040
```

---

## 验证安装

```sql
-- 查看集群状态
SHOW FRONTENDS;
SHOW BACKENDS;

-- 查看版本
SHOW FRONTENDS\G

-- 创建测试数据库
CREATE DATABASE test;
USE test;

-- 创建测试表
CREATE TABLE test_table (
    id INT,
    name VARCHAR(50)
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 10;

-- 插入测试数据
INSERT INTO test_table VALUES (1, 'test');

-- 查询数据
SELECT * FROM test_table;

-- 清理
DROP DATABASE test;
```

---

## 常见问题

### 1. FE 启动失败

```bash
# 检查日志
tail -f fe/log/fe.log

# 常见原因
# - 端口被占用
# - 内存不足
# - 元数据损坏
```

### 2. BE 无法加入集群

```bash
# 检查网络连通性
telnet fe_host 9010

# 检查 BE 日志
tail -f be/log/be.INFO

# 常见原因
# - 网络不通
# - 端口错误
# - 配置错误
```

### 3. 内存不足

```bash
# 调整 JVM 参数
# fe.conf
JAVA_OPTS = "-Xmx8192m -Xms8192m"

# be.conf
mem_limit = 80%
```

---

## 下一步

- [快速上手](./03-quick-start.md) - 完成你的第一次操作
- [SQL 基础](./04-sql-basics.md) - 学习 Doris SQL
- [数据模型](./05-data-model.md) - 理解三种数据模型

---

## 参考资料

- [官方安装文档](https://doris.apache.org/docs/install/)
- [Docker 部署](../doris-docker-cluster/)
- [Kubernetes 部署](../doris-gke-cluster-v4/)
