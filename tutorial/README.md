# Apache Doris 专家级完全教程

> 从零基础到生产级专家，覆盖架构原理、数据建模、查询优化、高级特性、运维排障全链路

## 教程定位

本教程的目标是让读者学完后成为 Doris 领域的**真正专家**，不只是"会用"，而是：

- **理解原理**：每个特性背后的设计思想、内部实现、适用边界
- **做出正确决策**：面对真实业务场景，知道选什么数据模型、什么分区策略、什么导入方式
- **排查问题**：能读懂执行计划、Profile、日志，定位性能瓶颈
- **生产就绪**：权限设计、监控告警、备份恢复、扩缩容升级全掌握

## 学习路径

### 第一部分：基础入门（打好地基）

| 章节 | 内容 | 文档 | SQL |
|------|------|------|-----|
| 01 | [环境搭建与部署](./docs/01-environment.md) | Docker/Binary/K8s/Cloud 全模式部署 | [SQL](./sql/00-setup.sql) |
| 02 | [架构深度解析](./docs/02-architecture.md) | FE/BE/MS/Broker 存储引擎 查询流程 | - |
| 03 | [数据模型深度解析](./docs/03-data-model.md) | Duplicate/Aggregate/Unique/Primary Key 模型选型 | [SQL](./sql/03-data-model.sql) |
| 04 | [数据类型全解](./docs/04-data-types.md) | 每种类型的存储、精度、性能影响 | [SQL](./sql/04-data-types.sql) |

### 第二部分：数据定义（建好框架）

| 章节 | 内容 | 文档 | SQL |
|------|------|------|-----|
| 05 | [数据库与表管理](./docs/05-ddl.md) | DDL深度、Schema Change、列操作、表属性 | [SQL](./sql/05-ddl.sql) |
| 06 | [分区与分桶策略](./docs/06-partition-bucket.md) | Range/List/Hash、分桶策略、冷热分离 | [SQL](./sql/06-partition-bucket.sql) |
| 07 | [索引系统详解](./docs/07-index.md) | 前缀索引、Bitmap、Bloom Filter、倒排索引、Ngram | [SQL](./sql/07-index.sql) |

### 第三部分：数据操作（灌好数据）

| 章节 | 内容 | 文档 | SQL |
|------|------|------|-----|
| 08 | [数据导入全解](./docs/08-data-import.md) | Stream/Broker/Routine/Insert/Flink/Spark/S3 全方式对比 | [SQL](./sql/08-data-import.sql) |
| 09 | [数据更新与删除](./docs/09-data-update-delete.md) | DELETE/UPDATE/REPLACE/Schema Change | [SQL](./sql/09-data-update-delete.sql) |
| 10 | [数据导出与ETL](./docs/10-data-export.md) | OUTFILE/Export/外部表/Hive/Iceberg/Hudi | [SQL](./sql/10-data-export.sql) |

### 第四部分：查询分析（写好查询）

| 章节 | 内容 | 文档 | SQL |
|------|------|------|-----|
| 11 | [JOIN深度解析](./docs/11-join.md) | 各JOIN类型、Colocate/Shuffle/Broadcast/Bucket Shuffle | [SQL](./sql/11-join.sql) |
| 12 | [聚合函数详解](./docs/12-aggregation.md) | 基础聚合、HLL/Bitmap/Percentile/Retention/自定义UDAF | [SQL](./sql/12-aggregation.sql) |
| 13 | [窗口函数与高级分析](./docs/13-window-analytic.md) | Window/CTE/子查询、漏斗/留存/路径分析 | [SQL](./sql/13-window-analytic.sql) |

### 第五部分：高级特性（用好特性）

| 章节 | 内容 | 文档 | SQL |
|------|------|------|-----|
| 14 | [物化视图详解](./docs/14-materialized-view.md) | 异步MV、刷新策略、查询重写、与Rollup对比 | [SQL](./sql/14-materialized-view.sql) |
| 15 | [动态分区与生命周期](./docs/15-dynamic-partition.md) | 动态分区策略、自动过期、存储回收、冷热分离 | [SQL](./sql/15-dynamic-partition.sql) |
| 16 | [Nereids优化器](./docs/16-nereids.md) | CBO/RBO、统计信息、Join Reorder、MV重写 | [SQL](./sql/16-nereids.sql) |
| 17 | [执行计划与性能诊断](./docs/17-explain-profile.md) | EXPLAIN/Profile解读、算子性能、资源消耗分析 | [SQL](./sql/17-explain-profile.sql) |
| 18 | [资源管理与隔离](./docs/18-resource.md) | Workload Group、Resource Group、查询队列、大查询管理 | [SQL](./sql/18-resource.sql) |

### 第六部分：运维专家（管好集群）

| 章节 | 内容 | 文档 | SQL |
|------|------|------|-----|
| 19 | [备份与恢复](./docs/19-backup-restore.md) | Snapshot/Backup/Restore、灾备方案、跨集群迁移 | [SQL](./sql/19-backup-restore.sql) |
| 20 | [监控与告警](./docs/20-monitoring.md) | Prometheus/Grafana、审计日志、慢查询、容量规划 | - |
| 21 | [用户权限与安全](./docs/21-security.md) | RBAC、角色继承、行级列级权限、LDAP、数据脱敏 | [SQL](./sql/21-security.sql) |
| 22 | [集群管理与运维](./docs/22-cluster-ops.md) | 扩缩容、升级、Rebalance、存算分离、多集群 | [SQL](./sql/22-cluster-ops.sql) |
| 23 | [故障排查与诊断](./docs/23-troubleshooting.md) | OOM/超时/数据不一致/副本异常/Compaction调优 | [SQL](./sql/23-troubleshooting.sql) |

## 统一示例数据模型

教程使用电商分析场景，包含完整的维度表和事实表：

```sql
-- 维度表
dim_users          -- 用户维度 (100万)
dim_products       -- 商品维度 (10万)
dim_stores         -- 门店维度 (500)
dim_categories     -- 品类维度 (100)

-- 事实表
fact_orders        -- 订单事实 (5000万)
fact_order_items   -- 订单明细 (1亿)
fact_page_views    -- 页面浏览 (5亿)
fact_payments      -- 支付记录 (4000万)
```

> 完整建表与造数脚本见 `sql/00-setup.sql`

## SQL 执行环境

```bash
# 连接 Doris (MySQL协议)
mysql -h 127.0.0.1 -P 9030 -u root

# 执行单个 SQL 文件
source /path/to/sql/03-data-model.sql;

# 从命令行执行
mysql -h 127.0.0.1 -P 9030 -u root < sql/03-data-model.sql
```

## 权限要求汇总

| 操作类别 | 所需权限 | 适用角色 |
|----------|----------|----------|
| 创建数据库 | `CREATE PRIVILEGE` ON `*.*` | admin |
| 创建表 | `CREATE_PRIV` ON 库 | db_admin |
| 导入数据 | `INSERT_PRIV` ON 表 | data_writer |
| 查询数据 | `SELECT_PRIV` ON 表 | analyst |
| 修改/删除数据 | `UPDATE_PRIV` / `DELETE_PRIV` ON 表 | data_writer |
| 创建用户/授权 | `ADMIN` 或 `GRANT_PRIV` | admin |
| 创建物化视图 | `CREATE_PRIV` ON 库 | db_admin |
| 备份恢复 | `ADMIN` 或 `REPOSITORY` 相关权限 | ops_admin |
| 集群管理 | `ADMIN` 或 `NODE_PRIV` | admin |

> 教程中每个 SQL 文件头部标注了具体所需权限

## 参考资料

- [Apache Doris 官方文档](https://doris.apache.org/docs/)
- [Doris SQL Reference](https://doris.apache.org/docs/sql-manual/)
- [Doris Design](https://doris.apache.org/docs/design/)
- [Doris GitHub](https://github.com/apache/doris)
