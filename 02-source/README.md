# Doris 源代码专题

本专题深入分析 Apache Doris 的源代码，从整体架构和核心原理层面理解 Doris 的设计思想。

## 目录结构

```
02-source/
├── README.md                    # 本文件
├── 01-architecture.md           # 整体架构设计
├── 02-fe-principle.md           # FE 核心原理
├── 03-be-principle.md           # BE 核心原理
├── 04-query-engine.md           # 查询引擎原理
├── 05-storage-engine.md         # 存储引擎原理
├── 06-import-mechanism.md       # 数据导入机制
└── 07-transaction.md            # 事务与一致性
```

## 学习路径

### 第一阶段：整体理解

1. [整体架构设计](./01-architecture.md) - 了解 Doris 的整体架构和组件交互
2. [FE 核心原理](./02-fe-principle.md) - 理解 FE 的元数据管理和查询规划
3. [BE 核心原理](./03-be-principle.md) - 理解 BE 的数据存储和查询执行

### 第二阶段：深入核心

4. [查询引擎原理](./04-query-engine.md) - 深入查询解析、优化和执行
5. [存储引擎原理](./05-storage-engine.md) - 深入数据存储格式和索引
6. [数据导入机制](./06-import-mechanism.md) - 深入数据导入流程

### 第三阶段：高级主题

7. [事务与一致性](./07-transaction.md) - 理解事务模型和数据一致性保证

## 源代码获取

```bash
# 从 GitHub 克隆
git clone https://github.com/apache/doris.git
cd doris

# 切换到稳定版本
git checkout 4.0.2

# 查看目录结构
ls -la
```

## 源代码目录结构

```
doris/
├── fe/                          # Frontend 源代码 (Java)
│   ├── fe-core/                 # FE 核心代码
│   │   ├── src/main/java/org/apache/doris/
│   │   │   ├── analysis/        # SQL 解析
│   │   │   ├── catalog/         # 元数据管理
│   │   │   ├── planner/         # 查询规划
│   │   │   ├── rewrite/         # 查询重写
│   │   │   ├── system/          # 系统管理
│   │   │   └── transaction/     # 事务管理
│   │   └── ...
│   └── ...
│
├── be/                          # Backend 源代码 (C++)
│   ├── src/
│   │   ├── olap/                # 存储引擎
│   │   ├── runtime/             # 运行时
│   │   ├── vec/                 # 向量化引擎
│   │   ├── http/                # HTTP 服务
│   │   └── service/             # RPC 服务
│   └── ...
│
├── docs/                        # 文档
├── extension/                   # 扩展
├── samples/                     # 示例
└── thirdparty/                  # 第三方依赖
```

## 核心概念速查

| 概念 | 说明 | 源码位置 |
|------|------|---------|
| FE | Frontend，元数据管理和查询规划 | `fe/fe-core/` |
| BE | Backend，数据存储和查询执行 | `be/src/` |
| Tablet | 数据分片，数据分布的最小单位 | `be/src/olap/tablet.cpp` |
| Rowset | 行集合，一次导入的数据 | `be/src/olap/rowset/` |
| Segment | 段，Rowset 内的数据分片 | `be/src/olap/rowset/segment_v2/` |
| Column | 列，存储的基本单位 | `be/src/vec/columns/` |
| Schema | 表结构 | `fe/fe-core/src/main/java/org/apache/doris/catalog/` |
| Planner | 查询规划器 | `fe/fe-core/src/main/java/org/apache/doris/planner/` |
| Executor | 查询执行器 | `be/src/runtime/` |

## 设计原则

### 1. 存储计算分离

Doris 支持存算分离架构：
- **FE**：管理元数据，不存储用户数据
- **BE**：存储数据，执行计算
- **存算分离模式**：数据存储在对象存储（S3/GCS），BE 只做计算

### 2. MPP 架构

Massively Parallel Processing：
- 查询并行执行
- 数据本地化计算
- 无共享架构

### 3. 列式存储

- 高压缩比
- 高查询性能
- 向量化执行

### 4. 预聚合

- Aggregate Key 模型自动预聚合
- 物化视图预计算
- 减少查询时计算量

## 关键技术点

### FE 关键技术

```
┌─────────────────────────────────────────────────────────────┐
│                         FE 架构                              │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │ SQL Parser  │→ │   Planner   │→ │  Optimizer  │         │
│  │  (解析SQL)  │  │ (生成计划)  │  │ (优化计划)  │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│                           ↓                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Catalog (元数据管理)                     │   │
│  │  - Database, Table, Partition, Tablet               │   │
│  │  - BDBJE (分布式元数据存储)                          │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### BE 关键技术

```
┌─────────────────────────────────────────────────────────────┐
│                         BE 架构                              │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Storage Engine (存储引擎)                │   │
│  │  Tablet → Rowset → Segment → Column → Page          │   │
│  └─────────────────────────────────────────────────────┘   │
│                           ↓                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Query Engine (查询引擎)                  │   │
│  │  Scan → Filter → Join → Agg → Sort → Output         │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## 学习建议

### 1. 从整体到局部

先理解整体架构，再深入具体模块：
- 先读架构文档，建立全局观
- 再读核心模块源码，理解实现细节
- 最后读周边模块，完善知识体系

### 2. 从接口到实现

先理解模块对外接口，再深入实现：
- 看类的 public 方法
- 理解接口设计意图
- 再看具体实现

### 3. 从测试到代码

通过测试用例理解代码：
- 单元测试展示基本用法
- 集成测试展示模块交互
- 性能测试展示关键路径

### 4. 结合文档

源码阅读结合官方文档：
- 文档提供概念解释
- 源码提供实现细节
- 两者结合理解更深入

## 调试技巧

### FE 调试

```bash
# 启动 FE 调试模式
cd fe
mvn debug -pl fe-core

# 远程调试
export JAVA_OPTS="-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=5005"
./bin/start_fe.sh
```

### BE 调试

```bash
# 编译 Debug 版本
cd be
./build.sh --debug

# 使用 GDB 调试
gdb ./output/lib/doris_be
```

### 日志分析

```bash
# FE 日志
tail -f fe/log/fe.log
tail -f fe/log/fe.audit.log

# BE 日志
tail -f be/log/be.INFO
tail -f be/log/be.WARNING
```

## 参考资料

- [Doris 官方文档](https://doris.apache.org/docs/)
- [Doris GitHub](https://github.com/apache/doris)
- [Doris 设计文档](https://doris.apache.org/docs/design/)
- [Doris 社区](https://doris.apache.org/community/)
