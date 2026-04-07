# 1. 环境准备与连接

## 1.1 Doris 简介

### 什么是 Doris

Apache Doris 是一个现代化的 MPP (Massively Parallel Processing) 分析型数据库，专注于 OLAP 场景：

- **特点**：
  - 高并发点查询
  - 复杂分析查询
  - 实时数据写入
  - 物化视图加速

### 核心架构

```
┌─────────────────────────────────────────────────────────┐
│                      FE (Frontend)                       │
│  ┌─────────────────────────────────────────────────┐   │
│  │  MySQL Protocol    │  Query Planner  │  Metadata │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────┐
│                      BE (Backend)                        │
│  ┌─────────────────────────────────────────────────┐   │
│  │  Storage Engine    │  Query Executor │  Tablet  │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

**为什么这样设计？**

| 组件 | 作用 | 为什么需要 |
|------|------|-----------|
| FE | 接收请求、解析SQL、优化查询、调度任务 | 前端入口，负责SQL处理和协调 |
| BE | 实际存储数据、执行查询任务 | 后端执行，数据实际存储和计算 |

## 1.2 环境准备

### 方式一：Docker Compose 本地环境

```bash
# 克隆或下载 doris-docker-compose
cd doris-docker-compose

# 启动集群
./scripts/start.sh   # Linux/macOS
.\start.bat          # Windows

# 等待 1-2 分钟初始化
./scripts/init-cluster.sh  # Linux/macOS
.\init-cluster.bat   # Windows
```

### 方式二：云服务部署

参考以下部署方案：
- [GCP 部署](../doris-gcp-cluster/README.md)
- [GKE 部署](../doris-gke-cluster/README.md)
- [阿里云部署](../doris-aliyun-cluster/README.md)

## 1.3 连接 Doris

### 使用 MySQL 客户端

```bash
# 基本连接
mysql -h <FE_HOST> -P 9030 -u <USER> -p

# 示例
mysql -h 127.0.0.1 -P 9030 -u root
```

### 连接参数说明

| 参数 | 说明 | 默认值 | 示例 |
|------|------|--------|------|
| -h | FE 主机地址 | 127.0.0.1 | 192.168.1.100 |
| -P | 查询端口 | 9030 | 9030 |
| -u | 用户名 | root | admin |
| -p | 密码 | 空 | password123 |
| -D | 数据库名 | default | my_db |

### 验证连接

```sql
-- 查看当前用户
SELECT USER();

-- 查看当前数据库
SELECT DATABASE();

-- 查看所有数据库
SHOW DATABASES;

-- 查看集群状态
SHOW FRONTENDS;
SHOW BACKENDS;
```

## 1.4 权限系统

### Doris 权限模型

```
用户 -> 角色 -> 权限
```

### 权限类型

| 权限 | 说明 | 适用范围 |
|------|------|----------|
| ADMIN | 管理员权限 | 全局 |
| GRANT | 授予权限 | 全局/数据库/表 |
| SELECT | 查询 | 数据库/表 |
| INSERT | 插入 | 数据库/表 |
| UPDATE | 更新 | 数据库/表 |
| DELETE | 删除 | 数据库/表 |
| CREATE | 创建 | 数据库/表 |
| DROP | 删除 | 数据库/表 |

### 创建用户并授权

```sql
-- 【所需权限】ADMIN
-- 创建用户
CREATE USER 'tutorial_user'@'%' IDENTIFIED BY 'Tutorial@123';

-- 【所需权限】ADMIN
-- 授予权限
GRANT SELECT, INSERT, UPDATE, DELETE ON tutorial.* TO 'tutorial_user'@'%';

-- 【所需权限】ADMIN
-- 刷新权限
FLUSH PRIVILEGES;
```

## 1.5 常见问题

### 连接被拒绝

```bash
# 检查 FE 是否运行
docker ps | grep doris-fe  # Docker 部署

# 检查端口
telnet 127.0.0.1 9030
```

### 权限不足

```sql
-- 查看当前用户权限
SHOW GRANTS FOR CURRENT_USER();

-- 如果是 root 或 ADMIN 用户
GRANT ALL PRIVILEGES ON *.* TO 'your_user'@'%';
FLUSH PRIVILEGES;
```

## 下一步

- [架构原理](./02-architecture.md) - 深入理解 Doris 架构
- [数据库表管理](./03-database-table.md) - 学习创建和管理数据库表
