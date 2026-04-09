# Doris 入门教程

## 概述

本目录包含 Doris 数据库的入门教程，从零基础开始，帮助你快速掌握 Doris 的基本使用。

---

## 学习路径

```
┌─────────────────────────────────────────────────────────────┐
│                    入门学习路径                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  第1天：了解 Doris                                           │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  01-introduction.md → Doris 简介、特性、应用场景     │   │
│  └─────────────────────────────────────────────────────┘   │
│                           ↓                                  │
│  第2天：安装部署                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  02-installation.md → Docker/物理机/K8s 部署         │   │
│  └─────────────────────────────────────────────────────┘   │
│                           ↓                                  │
│  第3天：快速上手                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  03-quick-start.md → 第一次操作、基础 SQL            │   │
│  └─────────────────────────────────────────────────────┘   │
│                           ↓                                  │
│  第4-5天：SQL 基础                                           │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  04-sql-basics.md → DDL/DML/DQL 完整语法             │   │
│  └─────────────────────────────────────────────────────┘   │
│                           ↓                                  │
│  第6天：数据模型                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  05-data-model.md → Duplicate/Aggregate/Unique       │   │
│  └─────────────────────────────────────────────────────┘   │
│                           ↓                                  │
│  第7天：数据导入导出                                         │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  06-data-import.md → Stream/Broker/Routine Load      │   │
│  │  07-data-export.md → SELECT INTO/EXPORT              │   │
│  └─────────────────────────────────────────────────────┘   │
│                           ↓                                  │
│  第8-10天：进阶内容                                          │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  08-best-practices.md → 最佳实践                     │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 目录结构

```
01-base/
├── README.md                    # 本文件
├── 01-introduction.md           # Doris 简介
├── 02-installation.md           # 安装部署
├── 03-quick-start.md            # 快速上手
├── 04-sql-basics.md             # SQL 基础
├── 05-data-model.md             # 数据模型
├── 06-data-import.md            # 数据导入
├── 07-data-export.md            # 数据导出
├── 08-best-practices.md         # 最佳实践
│
├── 01-connect.md                # 连接 Doris (旧)
├── 02-database-table.md         # 数据库和表管理 (旧)
├── 03-crud.md                   # 增删改查操作 (旧)
├── 04-data-import.md            # 数据导入 (旧)
├── 05-data-export.md            # 数据导出 (旧)
├── 06-partition.md              # 分区管理
├── 07-index.md                  # 索引管理
├── 08-join.md                   # JOIN 操作
├── 09-aggregation.md            # 聚合函数
├── 10-advanced.md               # 高级功能
├── 11-data-engineer-guide.md    # 数据工程师指南
└── 12-operations-guide.md       # 运维专家指南
```

---

## 学习目标

完成本教程后，你将能够：

- [ ] 理解 Doris 的定位和核心特性
- [ ] 独立部署 Doris 集群
- [ ] 使用 SQL 进行数据操作
- [ ] 选择合适的数据模型
- [ ] 完成数据的导入和导出
- [ ] 设计基础的表结构

---

## 前置要求

### 知识要求

- 基本的 SQL 知识（SELECT、INSERT、UPDATE、DELETE）
- 基本的 Linux 命令行操作
- 了解数据库的基本概念

### 环境要求

- Docker 20.0+（推荐）
- 或 Linux 服务器（CentOS 7+/Ubuntu 18.04+）
- 内存 >= 8GB
- 磁盘 >= 20GB

---

## 快速开始

### 1. 部署 Doris

```bash
# 使用 Docker 快速部署
docker network create doris-network

docker run -d --name doris-fe --network doris-network \
    -p 8030:8030 -p 9030:9030 \
    apache/doris:2.0.3-fe

docker run -d --name doris-be --network doris-network \
    -p 8040:8040 \
    apache/doris:2.0.3-be

# 添加 BE
docker exec -it doris-fe mysql -h 127.0.0.1 -P 9030 -u root -e "
ALTER SYSTEM ADD BACKEND 'doris-be:9050';
"
```

### 2. 连接 Doris

```bash
mysql -h 127.0.0.1 -P 9030 -u root
```

### 3. 创建第一个表

```sql
CREATE DATABASE demo;
USE demo;

CREATE TABLE users (
    user_id INT,
    user_name VARCHAR(50),
    age INT
)
DUPLICATE KEY(user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 10;

INSERT INTO users VALUES (1, '张三', 25), (2, '李四', 30);
SELECT * FROM users;
```

---

## 章节详解

### 01. Doris 简介

了解 Doris 是什么、为什么选择 Doris、核心特性和应用场景。

**学习内容**：
- Doris 的定位和特点
- 与其他系统的对比
- 核心架构概览
- 典型应用场景

**学习时间**：2 小时

### 02. 安装部署

学习如何在各种环境下部署 Doris。

**学习内容**：
- Docker 快速部署
- 物理机生产部署
- Kubernetes 部署
- 高可用配置

**学习时间**：4 小时

### 03. 快速上手

10 分钟完成你的第一次 Doris 操作。

**学习内容**：
- 连接 Doris
- 创建数据库和表
- 导入数据
- 查询数据

**学习时间**：2 小时

### 04. SQL 基础

掌握 Doris SQL 的核心语法。

**学习内容**：
- DDL（数据定义语言）
- DML（数据操作语言）
- DQL（数据查询语言）
- 窗口函数

**学习时间**：8 小时

### 05. 数据模型

理解三种数据模型及其应用场景。

**学习内容**：
- Duplicate Key（明细模型）
- Aggregate Key（聚合模型）
- Unique Key（唯一主键模型）
- 模型选择指南

**学习时间**：4 小时

### 06. 数据导入

掌握多种数据导入方式。

**学习内容**：
- Stream Load
- Broker Load
- Routine Load
- Insert 导入
- Flink 导入

**学习时间**：8 小时

### 07. 数据导出

学习数据导出的多种方式。

**学习内容**：
- SELECT INTO OUTFILE
- EXPORT 命令
- MySQL Dump
- Catalog 导出

**学习时间**：4 小时

---

## 练习任务

### 任务1：部署集群

使用 Docker 部署一套 1 FE + 1 BE 的 Doris 集群。

**验证标准**：
- [ ] 能够连接 Doris
- [ ] SHOW BACKENDS 显示 Alive 为 true
- [ ] 能够创建数据库

### 任务2：创建表

创建一个用户行为表，包含以下字段：
- user_id (BIGINT)
- event_time (DATETIME)
- event_type (VARCHAR)
- page_id (VARCHAR)
- device_id (VARCHAR)

**验证标准**：
- [ ] 表创建成功
- [ ] DESC 显示正确的表结构
- [ ] 能够插入数据

### 任务3：导入数据

准备 1000 条测试数据，使用 Stream Load 导入。

**验证标准**：
- [ ] 导入成功
- [ ] 数据行数正确
- [ ] 数据内容正确

### 任务4：查询分析

完成以下查询：
1. 统计每个用户的总事件数
2. 统计每小时的事件分布
3. 找出最活跃的前 10 个用户

**验证标准**：
- [ ] 查询结果正确
- [ ] 理解聚合函数
- [ ] 理解 GROUP BY

---

## 常见问题

### Q1: FE 启动失败怎么办？

检查日志文件 `fe/log/fe.log`，常见原因：
- 端口被占用
- 内存不足
- 元数据损坏

### Q2: BE 无法加入集群？

检查：
- 网络连通性
- 端口配置
- BE 日志 `be/log/be.INFO`

### Q3: 导入数据失败？

检查：
- 数据格式是否正确
- 列分隔符是否匹配
- 数据类型是否匹配

---

## 下一步

完成入门教程后，建议继续学习：

- [进阶教程](../03-advanced/README.md) - 高级表设计、查询优化
- [专家教程](../04-expert/README.md) - 集群运维、故障排查
- [源码分析](../02-source/README.md) - 架构原理、源码解读
- [实战案例](../05-practice/README.md) - 实时数仓、日志分析

---

## 参考资料

- [Doris 官网](https://doris.apache.org/)
- [官方文档](https://doris.apache.org/docs/)
- [GitHub](https://github.com/apache/doris)
- [社区论坛](https://doris.apache.org/community/)
