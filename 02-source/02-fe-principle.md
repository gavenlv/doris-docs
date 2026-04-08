# FE 核心原理

## FE 概述

Frontend (FE) 是 Doris 的"大脑"，负责元数据管理、SQL 解析、查询优化、查询调度等核心功能。FE 采用 Java 实现，基于 BDBJE 实现高可用。

## FE 架构

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              FE 内部架构                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                         接入层 (Access Layer)                          │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                    │  │
│  │  │ MySQL Proto │  │  HTTP API   │  │   RPC API   │                    │  │
│  │  │  (9030)     │  │   (8030)    │  │   (9020)    │                    │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                    │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                    │                                         │
│                                    ▼                                         │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                         查询处理层 (Query Layer)                        │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │  │
│  │  │   Parser    │→ │  Analyzer   │→ │  Rewriter   │→ │  Optimizer  │  │  │
│  │  │  (解析)     │  │  (分析)     │  │  (重写)     │  │  (优化)     │  │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘  │  │
│  │                                    │                                   │  │
│  │                                    ▼                                   │  │
│  │                         ┌─────────────────┐                           │  │
│  │                         │    Planner      │                           │  │
│  │                         │   (生成计划)    │                           │  │
│  │                         └─────────────────┘                           │  │
│  │                                    │                                   │  │
│  │                                    ▼                                   │  │
│  │                         ┌─────────────────┐                           │  │
│  │                         │  Coordinator    │                           │  │
│  │                         │   (调度执行)    │                           │  │
│  │                         └─────────────────┘                           │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                    │                                         │
│                                    ▼                                         │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                         元数据层 (Catalog Layer)                        │  │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │  │
│  │  │                      CatalogMgr                                 │  │  │
│  │  │  ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌───────────┐   │  │  │
│  │  │  │ Internal  │  │  Mysql    │  │   Hive    │  │   Iceberg │   │  │  │
│  │  │  │ Catalog   │  │ Catalog   │  │ Catalog   │  │ Catalog   │   │  │  │
│  │  │  └───────────┘  └───────────┘  └───────────┘  └───────────┘   │  │  │
│  │  └─────────────────────────────────────────────────────────────────┘  │  │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │  │
│  │  │                     Internal Catalog                             │  │  │
│  │  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐           │  │  │
│  │  │  │Database │→ │ Table   │→ │Partition│→ │ Tablet  │           │  │  │
│  │  │  └─────────┘  └─────────┘  └─────────┘  └─────────┘           │  │  │
│  │  └─────────────────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                    │                                         │
│                                    ▼                                         │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                         存储层 (Storage Layer)                          │  │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │  │
│  │  │                      BDBJE (元数据存储)                          │  │  │
│  │  │  - EditLog: 操作日志                                            │  │  │
│  │  │  - Image: 元数据快照                                            │  │  │
│  │  │  - HA: Leader/Follower 选举                                     │  │  │
│  │  └─────────────────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 核心模块详解

### 1. 元数据管理 (Catalog)

#### 源码位置

```
fe/fe-core/src/main/java/org/apache/doris/catalog/
├── Catalog.java              # 元数据中心，单例模式
├── CatalogMgr.java           # 多目录管理器
├── Database.java             # 数据库
├── Table.java                # 表接口
├── OlapTable.java            # OLAP 表实现
├── Partition.java            # 分区
├── Tablet.java               # 分片
├── TabletMeta.java           # 分片元数据
├── Replica.java              # 副本
├── Column.java               # 列
├── Index.java                # 索引
└── MaterializedIndex.java    # 物化索引
```

#### 核心类关系

```java
// 元数据层次结构
public class Catalog {
    // 数据库映射: name -> Database
    private ConcurrentHashMap<String, Database> dbNameToDb;
    
    // ID 映射: id -> Database
    private ConcurrentHashMap<Long, Database> idToDb;
}

public class Database {
    private long id;
    private String name;
    
    // 表映射: name -> Table
    private ConcurrentHashMap<String, Table> tableNameToTable;
    
    // ID 映射: id -> Table
    private ConcurrentHashMap<Long, Table> idToTable;
}

public class OlapTable extends Table {
    private long id;
    private String name;
    private KeysType keysType;  // DUP_KEYS, AGG_KEYS, UNIQUE_KEYS
    
    // 分区映射: name -> Partition
    private ConcurrentHashMap<String, Partition> nameToPartition;
    
    // 默认分区
    private Partition defaultPartition;
}

public class Partition {
    private long id;
    private String name;
    
    // 索引映射: id -> MaterializedIndex
    private ConcurrentHashMap<Long, MaterializedIndex> indexIdToIndex;
}

public class MaterializedIndex {
    private long id;
    private IndexState state;
    
    // Tablet 映射: id -> Tablet
    private List<Tablet> tablets;
}

public class Tablet {
    private long id;
    private TabletMeta tabletMeta;
    
    // 副本列表
    private List<Replica> replicas;
}

public class Replica {
    private long id;
    private long backendId;
    private long version;
    private long dataSize;
    private ReplicaState state;  // NORMAL, DECOMMISSION, CLONE
}
```

#### 元数据操作示例

```java
// 创建数据库
public void createDatabase(String dbName) {
    Database db = new Database(dbId, dbName);
    dbNameToDb.put(dbName, db);
    idToDb.put(dbId, db);
    
    // 写入 EditLog
    editLog.logCreateDb(db);
}

// 创建表
public void createTable(String dbName, Table table) {
    Database db = dbNameToDb.get(dbName);
    db.createTable(table);
    
    // 写入 EditLog
    editLog.logCreateTable(table);
}

// 添加分区
public void addPartition(String dbName, String tableName, Partition partition) {
    Database db = dbNameToDb.get(dbName);
    OlapTable table = (OlapTable) db.getTable(tableName);
    table.addPartition(partition);
    
    // 写入 EditLog
    editLog.logAddPartition(partition);
}
```

### 2. SQL 解析 (Parser)

#### 源码位置

```
fe/fe-core/src/main/java/org/apache/doris/analysis/
├── Parser.java               # SQL 解析器入口
├── SqlParser.g4              # ANTLR4 语法定义
├── StatementBase.java        # 语句基类
├── SelectStmt.java           # SELECT 语句
├── InsertStmt.java           # INSERT 语句
├── CreateTableStmt.java      # CREATE TABLE 语句
├── Expr.java                 # 表达式基类
├── SlotRef.java              # 列引用
├── LiteralExpr.java          # 字面量
└── FunctionCallExpr.java     # 函数调用
```

#### 解析流程

```java
// SQL 解析入口
public class Analyzer {
    public void analyze(StatementBase stmt) {
        // 1. 解析 SQL 文本
        SqlParser parser = new SqlParser();
        StatementBase parsedStmt = parser.parse(sql);
        
        // 2. 语义分析
        stmt.analyze(analyzer);
    }
}

// SELECT 语句分析
public class SelectStmt extends StatementBase {
    private SelectList selectList;
    private FromClause fromClause;
    private Expr whereClause;
    private GroupByClause groupByClause;
    private Expr havingClause;
    private OrderByElement orderByElements;
    private LimitElement limitElement;
    
    @Override
    public void analyze(Analyzer analyzer) {
        // 1. 分析 FROM 子句
        fromClause.analyze(analyzer);
        
        // 2. 分析 WHERE 子句
        whereClause.analyze(analyzer);
        
        // 3. 分析 SELECT 列表
        selectList.analyze(analyzer);
        
        // 4. 分析 GROUP BY 子句
        groupByClause.analyze(analyzer);
        
        // 5. 分析 HAVING 子句
        havingClause.analyze(analyzer);
        
        // 6. 分析 ORDER BY 子句
        orderByElements.analyze(analyzer);
        
        // 7. 分析 LIMIT 子句
        limitElement.analyze(analyzer);
    }
}
```

### 3. 查询优化 (Optimizer)

#### 源码位置

```
fe/fe-core/src/main/java/org/apache/doris/planner/
├── Planner.java              # 查询规划器
├── SingleNodePlanner.java    # 单节点规划器
├── DistributedPlanner.java   # 分布式规划器
├── ScanNode.java             # 扫描节点
├── OlapScanNode.java         # OLAP 扫描节点
├── JoinNode.java             # Join 节点
├── HashJoinNode.java         # Hash Join 节点
├── AggregationNode.java      # 聚合节点
├── SortNode.java             # 排序节点
└── ExchangeNode.java         # 数据交换节点

fe/fe-core/src/main/java/org/apache/doris/nereids/
├── NereidsPlanner.java       # 新优化器入口
├── rules/                    # 优化规则
│   ├── Rule.java
│   └── ...
└── costs/                    # 代价模型
    └── CostModel.java
```

#### 优化流程

```
┌─────────────────────────────────────────────────────────────┐
│                      查询优化流程                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. 语法树 (AST)                                             │
│     └── SelectStmt                                          │
│                                                              │
│  2. 逻辑计划 (Logical Plan)                                  │
│     └── LogicalPlan                                         │
│         ├── LogicalScan                                     │
│         ├── LogicalFilter                                   │
│         ├── LogicalJoin                                     │
│         ├── LogicalAggregate                                │
│         └── LogicalSort                                     │
│                                                              │
│  3. 优化规则应用                                             │
│     ├── 谓词下推 (Predicate Pushdown)                        │
│     ├── 投影下推 (Projection Pushdown)                       │
│     ├── Join 重排序 (Join Reorder)                           │
│     ├── 常量折叠 (Constant Folding)                          │
│     └── 子查询展开 (Subquery Unnesting)                      │
│                                                              │
│  4. 物理计划 (Physical Plan)                                 │
│     └── PhysicalPlan                                        │
│         ├── PhysicalOlapScan                                │
│         ├── PhysicalHashJoin                                │
│         ├── PhysicalHashAggregate                           │
│         └── PhysicalSort                                    │
│                                                              │
│  5. 分布式计划 (Distributed Plan)                            │
│     └── PlanFragment                                        │
│         ├── Fragment 0 (Coordinator)                        │
│         ├── Fragment 1 (Scan)                               │
│         └── Fragment 2 (Join)                               │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

#### 优化规则示例

```java
// 谓词下推规则
public class PredicatePushdown implements Rule {
    @Override
    public Plan apply(Plan plan) {
        // 将 Filter 下推到 Scan
        if (plan instanceof LogicalFilter) {
            LogicalFilter filter = (LogicalFilter) plan;
            Plan child = filter.child();
            
            if (child instanceof LogicalScan) {
                LogicalScan scan = (LogicalScan) child;
                // 将谓词合并到 Scan 的条件中
                scan.addConjuncts(filter.getConjuncts());
                return scan;
            }
        }
        return plan;
    }
}

// Join 重排序规则
public class JoinReorder implements Rule {
    @Override
    public Plan apply(Plan plan) {
        // 基于代价的 Join 重排序
        if (plan instanceof LogicalJoin) {
            // 使用动态规划或贪心算法
            // 选择最优的 Join 顺序
            return reorderJoin((LogicalJoin) plan);
        }
        return plan;
    }
}
```

### 4. 查询调度 (Coordinator)

#### 源码位置

```
fe/fe-core/src/main/java/org/apache/doris/qe/
├── Coordinator.java          # 查询协调器
├── CoordinatorMonitor.java   # 监控器
├── QueryState.java           # 查询状态
├── QueryStatistics.java      # 查询统计
└── ResultReceiver.java       # 结果接收器
```

#### 调度流程

```java
public class Coordinator {
    public void exec() throws Exception {
        // 1. 初始化
        initialize();
        
        // 2. 分配 Fragment 到 BE
        assignFragmentExecInstances();
        
        // 3. 发送执行请求
        sendFragmentExecRequests();
        
        // 4. 收集结果
        collectResults();
    }
    
    private void assignFragmentExecInstances() {
        // 为每个 Fragment 分配执行实例
        for (PlanFragment fragment : fragments) {
            // 确定 Scan 节点的数据位置
            // 选择最优的 BE 节点
            // 分配执行实例
        }
    }
    
    private void sendFragmentExecRequests() {
        // 并行发送执行请求到所有 BE
        for (Backend backend : backends) {
            // 发送 RPC 请求
            backendService.execPlanFragment(request);
        }
    }
    
    private void collectResults() {
        // 从 BE 接收查询结果
        // 合并排序结果
        // 返回给客户端
    }
}
```

### 5. 元数据存储 (BDBJE)

#### 存储机制

```
┌─────────────────────────────────────────────────────────────┐
│                     元数据存储机制                           │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                    EditLog                          │   │
│  │  - 记录所有元数据变更操作                            │   │
│  │  - 写入 BDBJE                                       │   │
│  │  - 复制到 Follower                                  │   │
│  └─────────────────────────────────────────────────────┘   │
│                           │                                  │
│                           ▼                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                    BDBJE                            │   │
│  │  - 分布式键值存储                                    │   │
│  │  - 支持 ACID 事务                                   │   │
│  │  - Leader/Follower 复制                             │   │
│  └─────────────────────────────────────────────────────┘   │
│                           │                                  │
│                           ▼                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                    Image                            │   │
│  │  - 元数据快照                                       │   │
│  │  - 定期生成                                         │   │
│  │  - 加速启动                                         │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

#### EditLog 操作

```java
// 写入 EditLog
public class EditLog {
    // 创建数据库
    public void logCreateDb(Database db) {
        EditLogEntry entry = EditLogEntry.createDb(db);
        appendEntry(entry);
    }
    
    // 创建表
    public void logCreateTable(Table table) {
        EditLogEntry entry = EditLogEntry.createTable(table);
        appendEntry(entry);
    }
    
    // 添加分区
    public void logAddPartition(Partition partition) {
        EditLogEntry entry = EditLogEntry.addPartition(partition);
        appendEntry(entry);
    }
    
    // 追加日志条目
    private void appendEntry(EditLogEntry entry) {
        // 写入 BDBJE
        // 等待多数节点确认
        journal.write(entry);
    }
}

// 回放 EditLog
public class EditLogLoader {
    public void load() {
        // 1. 加载最新的 Image
        Image image = loadLatestImage();
        
        // 2. 回放 Image 之后的 EditLog
        List<EditLogEntry> entries = readEditLogs(image.getEndOffset());
        for (EditLogEntry entry : entries) {
            replayEntry(entry);
        }
    }
    
    private void replayEntry(EditLogEntry entry) {
        switch (entry.getType()) {
            case CREATE_DB:
                Catalog.getCurrentCatalog().replayCreateDb(entry.getDb());
                break;
            case CREATE_TABLE:
                Catalog.getCurrentCatalog().replayCreateTable(entry.getTable());
                break;
            case ADD_PARTITION:
                Catalog.getCurrentCatalog().replayAddPartition(entry.getPartition());
                break;
        }
    }
}
```

### 6. 高可用机制

#### Leader 选举

```java
// FE 高可用管理
public class HaProtocol {
    // 选举 Leader
    public void electLeader() {
        // BDBJE 内置选举机制
        // 多数派投票
        // 获得多数票的 Follower 成为 Leader
    }
    
    // Leader 转移
    public void transferLeader(long newLeaderId) {
        // 将 Leader 权限转移给指定节点
        // 用于维护或升级
    }
    
    // 节点加入
    public void addFollower(String host, int port) {
        // 添加新的 Follower 节点
        // 同步元数据
    }
}
```

#### 故障恢复

```
┌─────────────────────────────────────────────────────────────┐
│                     FE 故障恢复流程                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Leader 故障检测                                          │
│     └── 心跳超时 (默认 5 秒)                                 │
│                                                              │
│  2. 选举新 Leader                                            │
│     ├── Follower 发起选举                                    │
│     ├── 多数派投票                                           │
│     └── 新 Leader 产生                                       │
│                                                              │
│  3. 元数据同步                                               │
│     ├── 新 Leader 加载最新 Image                             │
│     ├── 回放 EditLog                                         │
│     └── 恢复元数据                                           │
│                                                              │
│  4. 服务恢复                                                 │
│     ├── 接受新连接                                           │
│     ├── 处理新查询                                           │
│     └── 恢复正常服务                                         │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## 关键配置参数

### FE 配置文件 (fe.conf)

```properties
# 元数据目录
meta_dir = /opt/doris/fe/doris-meta

# 网络配置
edit_log_port = 9010
query_port = 9030
http_port = 8030
rpc_port = 9020

# JVM 配置
JAVA_OPTS = "-Xmx8192m -Xms8192m -Xmn4096m"

# 元数据配置
edit_log_roll_num = 50000
max_journal_writer_num = 5

# 查询配置
query_timeout = 300
max_running_query_num = 100
max_connection_per_user = 100

# 高可用配置
enable_bdbje_debug_mode = false
meta_delay_toleration_second = 10

# 统计信息
enable_statistics_collection = true
statistics_collection_interval = 3600
```

## 常用运维命令

### 元数据操作

```sql
-- 查看所有数据库
SHOW DATABASES;

-- 查看表结构
DESCRIBE table_name;
SHOW CREATE TABLE table_name;

-- 查看分区信息
SHOW PARTITIONS FROM table_name;

-- 查看分片信息
SHOW TABLET FROM table_name;

-- 查看副本状态
SHOW REPLICA STATUS FROM table_name;

-- 查看元数据版本
SHOW FRONTENDS;
```

### 元数据修复

```sql
-- 修复副本
ADMIN REPAIR TABLE table_name;

-- 设置副本状态
ADMIN SET REPLICA STATUS PROPERTIES("tablet_id" = "xxx", "status" = "ok");

-- 查看元数据不一致
SHOW PROC '/statistic';
```

## 参考资料

- [FE 源码](https://github.com/apache/doris/tree/master/fe)
- [Catalog 源码](https://github.com/apache/doris/tree/master/fe/fe-core/src/main/java/org/apache/doris/catalog)
- [Planner 源码](https://github.com/apache/doris/tree/master/fe/fe-core/src/main/java/org/apache/doris/planner)
- [Nereids 优化器](https://github.com/apache/doris/tree/master/fe/fe-core/src/main/java/org/apache/doris/nereids)
