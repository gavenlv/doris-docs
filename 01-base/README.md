# Doris 基本使用教程

本目录包含 Doris 数据库的基本使用示例和教程。

## 目录结构

```
01-base/
├── README.md                    # 本文件
├── 01-connect.md                # 连接 Doris
├── 02-database-table.md         # 数据库和表管理
├── 03-crud.md                   # 增删改查操作
├── 04-data-import.md            # 数据导入
├── 05-data-export.md            # 数据导出
├── 06-partition.md              # 分区管理
├── 07-index.md                  # 索引管理
├── 08-join.md                   # JOIN 操作
├── 09-aggregation.md            # 聚合函数
├── 10-advanced.md               # 高级功能
├── 11-data-engineer-guide.md    # 数据工程师完整指南 ⭐
└── 12-operations-guide.md       # 系统运维专家指南 ⭐
```

## 前置要求

确保你已经有一个运行中的 Doris 集群。如果没有，请参考以下部署方案：

- [doris-docker-cluster/](../doris-docker-cluster/) - Docker 部署
- [doris-aliyun-cluster/](../doris-aliyun-cluster/) - 阿里云部署
- [doris-gcp-cluster/](../doris-gcp-cluster/) - GCP 部署

## 快速连接

```bash
# 使用 MySQL 客户端
mysql -h 127.0.0.1 -P 9030 -u root

# 使用 Docker
docker exec -it doris-fe mysql -h 127.0.0.1 -P 9030 -u root
```

## 学习路径

### 基础教程

1. [连接 Doris](./01-connect.md) - 学习如何连接 Doris 集群
2. [数据库和表管理](./02-database-table.md) - 创建和管理数据库、表
3. [增删改查操作](./03-crud.md) - 基本的 CRUD 操作
4. [数据导入](./04-data-import.md) - 导入数据到 Doris
5. [数据导出](./05-data-export.md) - 从 Doris 导出数据
6. [分区管理](./06-partition.md) - 分区表的使用
7. [索引管理](./07-index.md) - 索引的创建和使用
8. [JOIN 操作](./08-join.md) - 多表关联查询
9. [聚合函数](./09-aggregation.md) - 聚合和分组
10. [高级功能](./10-advanced.md) - 物化视图、动态分区等

### 完整指南

- [数据工程师完整指南](./11-data-engineer-guide.md) - 从入门到生产的数据工程实践
- [系统运维专家指南](./12-operations-guide.md) - 部署、监控、故障排除、性能调优

## 示例数据

所有示例都使用以下测试数据：

```sql
-- 用户表
CREATE TABLE users (
  user_id BIGINT,
  user_name VARCHAR(100),
  age INT,
  city VARCHAR(50),
  register_date DATE
)
DUPLICATE KEY(user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 10;

-- 订单表
CREATE TABLE orders (
  order_id BIGINT,
  user_id BIGINT,
  product_id BIGINT,
  amount DECIMAL(10,2),
  order_date DATE
)
DUPLICATE KEY(order_id)
DISTRIBUTED BY HASH(order_id) BUCKETS 10;
```

## 常用命令速查

```sql
-- 查看所有数据库
SHOW DATABASES;

-- 创建数据库
CREATE DATABASE my_db;

-- 使用数据库
USE my_db;

-- 查看所有表
SHOW TABLES;

-- 查看表结构
DESCRIBE table_name;

-- 查看建表语句
SHOW CREATE TABLE table_name;

-- 删除表
DROP TABLE table_name;

-- 删除数据库
DROP DATABASE my_db;
```

## 参考资料

- [Doris 官方文档](https://doris.apache.org/docs/)
- [Doris SQL 手册](https://doris.apache.org/docs/sql-manual/)
- [Doris 最佳实践](https://doris.apache.org/docs/get-started/best-practice/)
