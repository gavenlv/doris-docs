# 查询引擎原理

## 概述

Doris 查询引擎负责将 SQL 语句转换为高效的执行计划，并在分布式环境中执行。Doris 支持两种执行引擎：向量化引擎 (Vectorized Engine) 和 Pipeline 引擎。

## 查询处理流程

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         查询处理完整流程                                     │
└─────────────────────────────────────────────────────────────────────────────┘

SQL 语句
    │
    ▼
┌─────────────────┐
│   SQL Parser    │  词法分析 + 语法分析
│   (解析)        │  生成抽象语法树 (AST)
└─────────────────┘
    │
    ▼
┌─────────────────┐
│   Analyzer      │  语义分析
│   (分析)        │  绑定元数据、类型检查、权限检查
└─────────────────┘
    │
    ▼
┌─────────────────┐
│   Rewriter      │  查询重写
│   (重写)        │  视图展开、子查询优化、常量折叠
└─────────────────┘
    │
    ▼
┌─────────────────┐
│   Optimizer     │  查询优化
│   (优化)        │  基于代价优化 (CBO)、规则优化 (RBO)
└─────────────────┘
    │
    ▼
┌─────────────────┐
│   Planner       │  生成执行计划
│   (规划)        │  生成物理计划树
└─────────────────┘
    │
    ▼
┌─────────────────┐
│  Coordinator    │  计划分片与调度
│   (调度)        │  分发到 BE 节点执行
└─────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────────────────┐
│                    BE 分布式执行                             │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐                 │
│  │  BE 1   │    │  BE 2   │    │  BE 3   │                 │
│  │Fragment │    │Fragment │    │Fragment │                 │
│  │ Exec    │←──→│ Exec    │←──→│ Exec    │                 │
│  └─────────┘    └─────────┘    └─────────┘                 │
└─────────────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────┐
│ Result Collector│  结果收集与合并
│   (收集)        │  返回给客户端
└─────────────────┘
```

## SQL 解析

### 源码位置

```
fe/fe-core/src/main/java/org/apache/doris/analysis/
├── SqlParser.g4              # ANTLR4 语法定义
├── SqlParser.java            # 解析器生成
├── SqlLexer.g4               # 词法分析
├── StatementBase.java        # 语句基类
├── SelectStmt.java           # SELECT 语句
├── InsertStmt.java           # INSERT 语句
├── CreateTableStmt.java      # CREATE TABLE 语句
├── Expr.java                 # 表达式基类
├── SlotRef.java              # 列引用
├── LiteralExpr.java          # 字面量
├── FunctionCallExpr.java     # 函数调用
└── BinaryPredicate.java      # 二元谓词
```

### AST 结构

```java
// SELECT 语句 AST
public class SelectStmt extends StatementBase {
    private SelectList selectList;          // SELECT 列表
    private FromClause fromClause;          // FROM 子句
    private Expr whereClause;               // WHERE 条件
    private GroupByClause groupByClause;    // GROUP BY
    private Expr havingClause;              // HAVING
    private List<OrderByElement> orderByElements;  // ORDER BY
    private LimitElement limitElement;      // LIMIT
    
    // 分析方法
    @Override
    public void analyze(Analyzer analyzer) {
        // 1. 分析 FROM 子句
        fromClause.analyze(analyzer);
        
        // 2. 分析 WHERE 子句
        if (whereClause != null) {
            whereClause.analyze(analyzer);
        }
        
        // 3. 分析 SELECT 列表
        selectList.analyze(analyzer);
        
        // 4. 分析 GROUP BY
        if (groupByClause != null) {
            groupByClause.analyze(analyzer);
        }
        
        // 5. 分析 HAVING
        if (havingClause != null) {
            havingClause.analyze(analyzer);
        }
        
        // 6. 分析 ORDER BY
        if (orderByElements != null) {
            for (OrderByElement element : orderByElements) {
                element.analyze(analyzer);
            }
        }
        
        // 7. 分析 LIMIT
        if (limitElement != null) {
            limitElement.analyze(analyzer);
        }
    }
}

// 表达式 AST
public class BinaryPredicate extends Expr {
    private Operator op;     // EQ, NE, LT, LE, GT, GE
    private Expr left;       // 左表达式
    private Expr right;      // 右表达式
    
    public enum Operator {
        EQ,     // =
        NE,     // !=, <>
        LT,     // <
        LE,     // <=
        GT,     // >
        GE,     // >=
        EQ_FOR_NULL,  // <=>
    }
}
```

## 查询优化

### 优化器架构

```
┌─────────────────────────────────────────────────────────────┐
│                      优化器架构                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Nereids Optimizer (新优化器)            │   │
│  │  ┌─────────────────────────────────────────────┐    │   │
│  │  │            Cascades Framework                │    │   │
│  │  │  - Memo: 搜索空间                            │    │   │
│  │  │  - Group: 等价表达式组                       │    │   │
│  │  │  - Pattern: 匹配模式                         │    │   │
│  │  └─────────────────────────────────────────────┘    │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  优化规则:                                                   │
│  ├── RBO (Rule-Based Optimization)                         │
│  │   ├── 谓词下推 (Predicate Pushdown)                      │
│  │   ├── 投影下推 (Projection Pushdown)                     │
│  │   ├── 常量折叠 (Constant Folding)                        │
│  │   └── 子查询展开 (Subquery Unnesting)                    │
│  │                                                          │
│  └── CBO (Cost-Based Optimization)                         │
│      ├── Join 重排序 (Join Reorder)                         │
│      ├── 聚合下推 (Aggregation Pushdown)                    │
│      └── 索引选择 (Index Selection)                         │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 源码位置

```
fe/fe-core/src/main/java/org/apache/doris/nereids/
├── NereidsPlanner.java       # 优化器入口
├── analyzer/                 # 语义分析
│   ├── Analyzer.java
│   └── ...
├── rules/                    # 优化规则
│   ├── Rule.java
│   ├── RuleType.java
│   ├── implementation/       # 物理实现规则
│   │   ├── HashJoinImplementation.java
│   │   └── ...
│   └── rewrite/              # 逻辑重写规则
│       ├── PredicatePushdown.java
│       ├── ConstantFolding.java
│       └── ...
├── costs/                    # 代价模型
│   ├── CostModel.java
│   └── CostEstimator.java
├── memo/                     # 搜索空间
│   ├── Memo.java
│   ├── Group.java
│   └── GroupExpression.java
└── properties/               # 物理属性
    ├── PhysicalProperties.java
    └── ...
```

### 优化规则详解

```java
// 谓词下推规则
public class PredicatePushdown implements RewriteRule {
    @Override
    public Plan apply(Plan plan) {
        // 将 Filter 下推到 Scan
        if (plan instanceof LogicalFilter) {
            LogicalFilter filter = (LogicalFilter) plan;
            Plan child = filter.child();
            
            // 如果子节点是 Scan，直接下推
            if (child instanceof LogicalScan) {
                LogicalScan scan = (LogicalScan) child;
                scan.pushDownPredicates(filter.getPredicates());
                return scan;
            }
            
            // 如果子节点是 Join，尝试下推到两侧
            if (child instanceof LogicalJoin) {
                LogicalJoin join = (LogicalJoin) child;
                return pushDownThroughJoin(filter, join);
            }
        }
        return plan;
    }
    
    private Plan pushDownThroughJoin(LogicalFilter filter, LogicalJoin join) {
        // 分离可以下推的谓词
        List<Expr> leftPredicates = new ArrayList<>();
        List<Expr> rightPredicates = new ArrayList<>();
        List<Expr> remainingPredicates = new ArrayList<>();
        
        for (Expr pred : filter.getPredicates()) {
            if (canPushToLeft(pred, join)) {
                leftPredicates.add(pred);
            } else if (canPushToRight(pred, join)) {
                rightPredicates.add(pred);
            } else {
                remainingPredicates.add(pred);
            }
        }
        
        // 下推到左子树
        if (!leftPredicates.isEmpty()) {
            join.setLeft(new LogicalFilter(leftPredicates, join.left()));
        }
        
        // 下推到右子树
        if (!rightPredicates.isEmpty()) {
            join.setRight(new LogicalFilter(rightPredicates, join.right()));
        }
        
        // 返回剩余的 Filter
        if (remainingPredicates.isEmpty()) {
            return join;
        }
        return new LogicalFilter(remainingPredicates, join);
    }
}

// Join 重排序规则
public class JoinReorder implements RewriteRule {
    @Override
    public Plan apply(Plan plan) {
        if (plan instanceof LogicalJoin) {
            return reorderJoin((LogicalJoin) plan);
        }
        return plan;
    }
    
    private Plan reorderJoin(LogicalJoin join) {
        // 收集所有 Join 的表
        List<LogicalScan> tables = collectTables(join);
        
        // 使用动态规划或贪心算法
        // 选择最优的 Join 顺序
        return dpJoinOrder(tables);
    }
    
    private Plan dpJoinOrder(List<LogicalScan> tables) {
        int n = tables.size();
        
        // dp[i][j] 表示从第 i 个表到第 j 个表的最优计划
        Plan[][] dp = new Plan[n][n];
        double[][] cost = new double[n][n];
        
        // 初始化单个表
        for (int i = 0; i < n; i++) {
            dp[i][i] = tables.get(i);
            cost[i][i] = estimateCost(tables.get(i));
        }
        
        // 动态规划
        for (int len = 2; len <= n; len++) {
            for (int i = 0; i <= n - len; i++) {
                int j = i + len - 1;
                for (int k = i; k < j; k++) {
                    Plan leftPlan = dp[i][k];
                    Plan rightPlan = dp[k+1][j];
                    Plan joinPlan = new LogicalJoin(leftPlan, rightPlan);
                    double joinCost = estimateCost(joinPlan);
                    
                    if (cost[i][j] == 0 || joinCost < cost[i][j]) {
                        dp[i][j] = joinPlan;
                        cost[i][j] = joinCost;
                    }
                }
            }
        }
        
        return dp[0][n-1];
    }
}
```

### 代价模型

```java
// 代价估计
public class CostEstimator {
    
    // 估计 Scan 代价
    public double estimateScanCost(LogicalScan scan) {
        long numRows = scan.getTable().getRowCount();
        int numColumns = scan.getOutputColumns().size();
        
        // IO 代价
        double ioCost = numRows * numColumns * COLUMN_SIZE;
        
        // CPU 代价
        double cpuCost = numRows * numColumns;
        
        return ioCost + cpuCost;
    }
    
    // 估计 Join 代价
    public double estimateJoinCost(LogicalJoin join) {
        Plan left = join.left();
        Plan right = join.right();
        
        double leftRows = estimateCardinality(left);
        double rightRows = estimateCardinality(right);
        
        // Hash Join 代价
        // Build: rightRows * hash_cost
        // Probe: leftRows * probe_cost
        double buildCost = rightRows * HASH_COST;
        double probeCost = leftRows * PROBE_COST;
        
        // 输出行数
        double outputRows = estimateJoinCardinality(join);
        
        return buildCost + probeCost + outputRows * OUTPUT_COST;
    }
    
    // 估计聚合代价
    public double estimateAggCost(LogicalAggregate agg) {
        double inputRows = estimateCardinality(agg.child());
        int numGroupByColumns = agg.getGroupByColumns().size();
        int numAggFunctions = agg.getAggFunctions().size();
        
        // Hash 聚合代价
        double hashCost = inputRows * numGroupByColumns * HASH_COST;
        double aggCost = inputRows * numAggFunctions * AGG_COST;
        
        return hashCost + aggCost;
    }
    
    // 估计基数
    public double estimateCardinality(Plan plan) {
        if (plan instanceof LogicalScan) {
            return estimateScanCardinality((LogicalScan) plan);
        } else if (plan instanceof LogicalFilter) {
            return estimateFilterCardinality((LogicalFilter) plan);
        } else if (plan instanceof LogicalJoin) {
            return estimateJoinCardinality((LogicalJoin) plan);
        } else if (plan instanceof LogicalAggregate) {
            return estimateAggCardinality((LogicalAggregate) plan);
        }
        return 0;
    }
}
```

## 执行计划生成

### 物理计划节点

```
┌─────────────────────────────────────────────────────────────┐
│                    物理计划节点类型                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Scan 节点                                                   │
│  ├── OlapScanNode        # OLAP 表扫描                      │
│  ├── MysqlScanNode       # MySQL 外表扫描                   │
│  ├── HiveScanNode        # Hive 外表扫描                    │
│  └── IcebergScanNode     # Iceberg 外表扫描                 │
│                                                              │
│  Join 节点                                                   │
│  ├── HashJoinNode        # Hash Join                        │
│  ├── NestLoopJoinNode    # Nest Loop Join                   │
│  └── MergeJoinNode       # Merge Join                       │
│                                                              │
│  聚合节点                                                    │
│  ├── AggregationNode     # 聚合                             │
│  └── AnalyticEvalNode    # 窗口函数                         │
│                                                              │
│  排序节点                                                    │
│  ├── SortNode            # 排序                             │
│  └── TopNNode            # Top-N 排序                       │
│                                                              │
│  数据交换节点                                                │
│  ├── ExchangeNode        # 数据交换                         │
│  ├── DataPartition       # 数据分区                         │
│  └── DataStreamSender    # 数据发送                         │
│                                                              │
│  其他节点                                                    │
│  ├── FilterNode          # 过滤                             │
│  ├── ProjectNode         # 投影                             │
│  ├── UnionNode           # 并集                             │
│  └── IntersectNode       # 交集                             │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 执行计划示例

```sql
SELECT 
    o.order_date,
    u.city,
    SUM(o.amount) as total_amount
FROM orders o
JOIN users u ON o.user_id = u.user_id
WHERE o.order_date >= '2024-01-01'
GROUP BY o.order_date, u.city
ORDER BY total_amount DESC
LIMIT 10;
```

执行计划：

```
PLAN FRAGMENT 0 (Coordinator)
└── TOP-N 
    ├── ORDER BY: total_amount DESC
    ├── LIMIT: 10
    └── EXCHANGE (receive from FRAGMENT 1)
        └── DataStreamReceiver

PLAN FRAGMENT 1
└── AGGREGATE (merge)
    ├── GROUP BY: order_date, city
    └── EXCHANGE (receive from FRAGMENT 2)
        └── DataStreamReceiver

PLAN FRAGMENT 2
└── AGGREGATE (update serialize)
    ├── GROUP BY: order_date, city
    └── HASH JOIN
        ├── JOIN PREDICATE: o.user_id = u.user_id
        ├── EXCHANGE (broadcast)
        │   └── PLAN FRAGMENT 3
        └── OlapScanNode (orders)
            ├── TABLE: orders
            ├── PREDICATE: order_date >= '2024-01-01'
            └── PARTITIONS: p202401, p202402, ...

PLAN FRAGMENT 3
└── OlapScanNode (users)
    └── TABLE: users
```

## 分布式执行

### Fragment 分布

```
┌─────────────────────────────────────────────────────────────┐
│                    Fragment 分布执行                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  FE (Coordinator)                                           │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Fragment 0 (Coordinator Fragment)                    │   │
│  │ └── Top-N + Result Collection                        │   │
│  └─────────────────────────────────────────────────────┘   │
│           ↑         ↑         ↑                             │
│           │         │         │                             │
│  ┌────────┴─────────┴─────────┴────────┐                  │
│  │           Exchange (Gather)          │                  │
│  └──────────────────────────────────────┘                  │
│           ↑         ↑         ↑                             │
│           │         │         │                             │
│  BE 1     │    BE 2 │    BE 3 │                             │
│  ┌────────┴───┐┌────┴────┐┌──┴────────┐                   │
│  │ Fragment 1 ││Fragment1││ Fragment 1│                   │
│  │ Agg + Join ││Agg+Join ││ Agg + Join│                   │
│  └────────────┘└─────────┘└───────────┘                   │
│       ↑            ↑            ↑                           │
│       │            │            │                           │
│  Local Data   Local Data   Local Data                       │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 数据交换

```java
// 数据分区类型
public enum DataPartitionType {
    UNPARTITIONED,      // 不分区，广播
    HASH_PARTITIONED,   // Hash 分区
    RANGE_PARTITIONED,  // 范围分区
    RANDOM,             // 随机分区
}

// 数据交换节点
public class ExchangeNode extends PlanNode {
    private DataPartition inputPartition;
    private List<PlanFragmentId> sourceFragmentIds;
    
    // 获取数据接收器
    public DataStreamReceiver createReceiver(RuntimeState state) {
        return new DataStreamReceiver(state, inputPartition);
    }
}

// 数据发送器
public class DataStreamSender {
    private List<Backend> destinations;
    private DataPartition outputPartition;
    
    // 发送数据块
    public void sendBlock(Block block) {
        // 根据分区策略分发数据
        if (outputPartition.getType() == DataPartitionType.HASH_PARTITIONED) {
            // Hash 分区
            int numDestinations = destinations.size();
            for (int i = 0; i < block.rows(); i++) {
                int hash = computeHash(block, i);
                int dest = hash % numDestinations;
                sendRowToDestination(block, i, destinations.get(dest));
            }
        } else if (outputPartition.getType() == DataPartitionType.UNPARTITIONED) {
            // 广播到所有目的地
            for (Backend dest : destinations) {
                sendBlockToDestination(block, dest);
            }
        }
    }
}
```

## 向量化执行引擎

### 向量化执行原理

```
┌─────────────────────────────────────────────────────────────┐
│                    向量化执行原理                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  传统执行 (Volcano Model):                                   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ for each row in table:                              │   │
│  │     if (filter(row)):                               │   │
│  │         result.add(row)                             │   │
│  └─────────────────────────────────────────────────────┘   │
│  问题: 函数调用开销大，CPU 缓存不友好                        │
│                                                              │
│  向量化执行 (Vectorized Model):                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ while (has_next_block()):                           │   │
│  │     block = get_next_block(1024 rows)              │   │
│  │     filter_mask = filter_vectorized(block)          │   │
│  │     result_block = apply_filter(block, filter_mask) │   │
│  │     return result_block                             │   │
│  └─────────────────────────────────────────────────────┘   │
│  优势:                                                       │
│  - 减少函数调用开销                                          │
│  - CPU 缓存友好                                              │
│  - 支持 SIMD 指令                                            │
│  - 批量处理                                                  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 向量化数据结构

```cpp
// Block: 一批行的集合
class Block {
public:
    Block(const std::vector<SlotDescriptor*>& slots);
    
    // 获取行数
    size_t rows() const { return _rows; }
    
    // 获取列
    ColumnPtr get_column(size_t index) const { return _columns[index]; }
    
    // 添加行
    void append_row(const Tuple& tuple);
    
    // 过滤行
    void filter(const std::vector<bool>& filter);
    
private:
    size_t _rows;
    std::vector<ColumnPtr> _columns;
    std::vector<std::string> _column_names;
};

// Column: 列数据
class IColumn {
public:
    virtual ~IColumn() = default;
    
    // 获取大小
    virtual size_t size() const = 0;
    
    // 获取元素
    virtual Field operator[](size_t index) const = 0;
    
    // 插入元素
    virtual void insert(const Field& field) = 0;
    
    // 批量插入
    virtual void insert_range_from(const IColumn& src, 
                                   size_t start, size_t length) = 0;
    
    // 过滤
    virtual ColumnPtr filter(const IColumn::Filter& filter) const = 0;
    
    // 复制
    virtual ColumnPtr clone() const = 0;
};

// 整数列
class ColumnVector<int32_t> : public IColumn {
public:
    size_t size() const override { return _data.size(); }
    
    Field operator[](size_t index) const override {
        return _data[index];
    }
    
    void insert(const Field& field) override {
        _data.push_back(field.get<int32_t>());
    }
    
    ColumnPtr filter(const IColumn::Filter& filter) const override {
        auto result = ColumnVector<int32_t>::create();
        for (size_t i = 0; i < _data.size(); i++) {
            if (filter[i]) {
                result->insert(_data[i]);
            }
        }
        return result;
    }
    
private:
    std::vector<int32_t> _data;
};

// 字符串列
class ColumnString : public IColumn {
public:
    size_t size() const override { return _offsets.size(); }
    
    Field operator[](size_t index) const override {
        size_t start = index == 0 ? 0 : _offsets[index - 1];
        size_t end = _offsets[index];
        return std::string(&_data[start], end - start);
    }
    
    void insert(const Field& field) override {
        std::string str = field.get<std::string>();
        _data.insert(_data.end(), str.begin(), str.end());
        _offsets.push_back(_data.size());
    }
    
private:
    std::vector<char> _data;      // 字符数据
    std::vector<size_t> _offsets; // 偏移量
};
```

### 向量化算子

```cpp
// 向量化扫描节点
class VScanNode : public ExecNode {
public:
    Status get_next(RuntimeState* state, Block* block, bool* eos) override {
        // 从存储引擎读取一个 Block
        RETURN_IF_ERROR(_reader->get_next(block, eos));
        
        if (*eos) {
            return Status::OK();
        }
        
        // 应用谓词过滤
        if (!_conjunct_ctxs.empty()) {
            RETURN_IF_ERROR(_filter_block(block));
        }
        
        return Status::OK();
    }
    
private:
    Status _filter_block(Block* block) {
        // 计算过滤掩码
        ColumnPtr filter_column = ColumnVector<uint8_t>::create(block->rows());
        
        for (auto& ctx : _conjunct_ctxs) {
            ctx->execute(block, filter_column);
        }
        
        // 应用过滤
        block->filter(*filter_column);
        
        return Status::OK();
    }
};

// 向量化 Hash Join
class VHashJoinNode : public ExecNode {
public:
    Status open(RuntimeState* state) override {
        // 构建哈希表
        RETURN_IF_ERROR(_build_hash_table(state));
        return Status::OK();
    }
    
    Status get_next(RuntimeState* state, Block* block, bool* eos) override {
        // 从探测端获取 Block
        Block probe_block;
        RETURN_IF_ERROR(_probe_child->get_next(state, &probe_block, eos));
        
        if (*eos) {
            return Status::OK();
        }
        
        // 探测哈希表
        RETURN_IF_ERROR(_probe_hash_table(probe_block, block));
        
        return Status::OK();
    }
    
private:
    Status _build_hash_table(RuntimeState* state) {
        Block build_block;
        bool eos = false;
        
        while (!eos) {
            RETURN_IF_ERROR(_build_child->get_next(state, &build_block, &eos));
            
            if (!eos) {
                // 将 Block 插入哈希表
                _hash_table->insert(build_block);
            }
        }
        
        return Status::OK();
    }
    
    Status _probe_hash_table(const Block& probe_block, Block* output_block) {
        // 获取 Join Key 列
        ColumnPtr key_column = probe_block.get_column(_probe_key_index);
        
        // 探测哈希表
        std::vector<RowRefList> results;
        _hash_table->find(*key_column, &results);
        
        // 构建输出 Block
        for (size_t i = 0; i < probe_block.rows(); i++) {
            if (!results[i].empty()) {
                for (auto& ref : results[i]) {
                    // 添加探测侧行
                    for (size_t col = 0; col < probe_block.columns(); col++) {
                        output_block->get_column(col)->insert_from(
                            *probe_block.get_column(col), i);
                    }
                    // 添加构建侧行
                    for (size_t col = 0; col < _build_block.columns(); col++) {
                        output_block->get_column(col + probe_block.columns())
                            ->insert_from(*ref.block->get_column(col), ref.row);
                    }
                }
            }
        }
        
        return Status::OK();
    }
    
    std::unique_ptr<HashTable> _hash_table;
    ExecNode* _build_child;
    ExecNode* _probe_child;
};

// 向量化聚合
class VAggregationNode : public ExecNode {
public:
    Status get_next(RuntimeState* state, Block* block, bool* eos) override {
        if (_is_merge) {
            // 合并阶段
            return _merge_aggregate(state, block, eos);
        } else {
            // 聚合阶段
            return _update_aggregate(state, block, eos);
        }
    }
    
private:
    Status _update_aggregate(RuntimeState* state, Block* block, bool* eos) {
        Block input_block;
        RETURN_IF_ERROR(_child->get_next(state, &input_block, eos));
        
        if (*eos) {
            // 输出聚合结果
            _get_aggregate_result(block);
            return Status::OK();
        }
        
        // 获取分组键
        std::vector<ColumnPtr> key_columns;
        for (size_t i = 0; i < _group_by_columns.size(); i++) {
            key_columns.push_back(input_block.get_column(_group_by_columns[i]));
        }
        
        // 计算 Hash 值
        std::vector<size_t> hashes = _compute_hashes(key_columns);
        
        // 更新聚合状态
        for (size_t i = 0; i < input_block.rows(); i++) {
            size_t hash = hashes[i];
            auto it = _agg_states.find(hash);
            
            if (it == _agg_states.end()) {
                // 创建新的聚合状态
                AggState state;
                for (auto& agg_func : _agg_functions) {
                    state.values.push_back(agg_func->create());
                }
                _agg_states[hash] = state;
            }
            
            // 更新聚合状态
            AggState& state = _agg_states[hash];
            for (size_t j = 0; j < _agg_functions.size(); j++) {
                _agg_functions[j]->update(
                    input_block.get_column(_agg_columns[j]), i, 
                    state.values[j]);
            }
        }
        
        return Status::OK();
    }
    
    std::unordered_map<size_t, AggState> _agg_states;
    std::vector<AggregateFunctionPtr> _agg_functions;
};
```

## Pipeline 执行引擎

### Pipeline 架构

```
┌─────────────────────────────────────────────────────────────┐
│                    Pipeline 执行引擎                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  传统执行模型:                                               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Operator 1 → Operator 2 → Operator 3 → ...          │   │
│  │                                                      │   │
│  │ 问题:                                                │   │
│  │ - 阻塞算子 (Sort, Agg) 导致后续算子等待              │   │
│  │ - 无法充分利用多核                                    │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  Pipeline 执行模型:                                          │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Pipeline 1: Source → Operator → Operator → Sink     │   │
│  │                    ↓                                 │   │
│  │ Pipeline 2: Source → Operator → Operator → Sink     │   │
│  │                    ↓                                 │   │
│  │ Pipeline 3: Source → Operator → Operator → Sink     │   │
│  │                                                      │   │
│  │ 优势:                                                │   │
│  │ - 流水线并行                                          │   │
│  │ - 充分利用多核                                        │   │
│  │ - 减少阻塞                                            │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Pipeline 实现

```cpp
// Pipeline 定义
class Pipeline {
public:
    Pipeline(int id) : _id(id) {}
    
    // 添加算子
    void add_operator(std::unique_ptr<Operator> op) {
        _operators.push_back(std::move(op));
    }
    
    // 准备执行
    Status prepare(RuntimeState* state) {
        for (auto& op : _operators) {
            RETURN_IF_ERROR(op->prepare(state));
        }
        return Status::OK();
    }
    
    // 执行
    Status execute(RuntimeState* state) {
        Block block;
        bool eos = false;
        
        while (!eos) {
            // 从 Source 读取数据
            RETURN_IF_ERROR(_source->get_next(state, &block, &eos));
            
            if (eos) {
                break;
            }
            
            // 通过算子链处理
            for (auto& op : _operators) {
                RETURN_IF_ERROR(op->push(state, &block));
            }
            
            // 写入 Sink
            RETURN_IF_ERROR(_sink->push(state, block));
        }
        
        return Status::OK();
    }
    
private:
    int _id;
    std::vector<std::unique_ptr<Operator>> _operators;
    SourceOperator* _source;
    SinkOperator* _sink;
};

// Source Operator
class SourceOperator : public Operator {
public:
    virtual Status get_next(RuntimeState* state, Block* block, bool* eos) = 0;
};

// Sink Operator
class SinkOperator : public Operator {
public:
    virtual Status push(RuntimeState* state, const Block& block) = 0;
    virtual Status finalize(RuntimeState* state) = 0;
};

// Pipeline Task
class PipelineTask {
public:
    PipelineTask(Pipeline* pipeline, RuntimeState* state);
    
    // 执行一个批次
    Status execute() {
        Block block;
        bool eos = false;
        
        // 从 Source 读取
        RETURN_IF_ERROR(_source->get_next(_state, &block, &eos));
        
        if (eos) {
            _finished = true;
            return Status::OK();
        }
        
        // 处理
        for (auto& op : _operators) {
            RETURN_IF_ERROR(op->push(_state, &block));
        }
        
        // 写入 Sink
        RETURN_IF_ERROR(_sink->push(_state, block));
        
        return Status::OK();
    }
    
    bool is_finished() const { return _finished; }
    
private:
    Pipeline* _pipeline;
    RuntimeState* _state;
    bool _finished = false;
};

// Pipeline Task Scheduler
class PipelineTaskScheduler {
public:
    // 提交任务
    void submit(std::unique_ptr<PipelineTask> task) {
        _tasks.push_back(std::move(task));
    }
    
    // 执行所有任务
    void run() {
        while (!_tasks.empty()) {
            for (auto it = _tasks.begin(); it != _tasks.end(); ) {
                auto& task = *it;
                
                // 执行任务
                task->execute();
                
                // 如果完成，移除任务
                if (task->is_finished()) {
                    it = _tasks.erase(it);
                } else {
                    ++it;
                }
            }
        }
    }
    
private:
    std::vector<std::unique_ptr<PipelineTask>> _tasks;
    ThreadPool _thread_pool;
};
```

## 查询性能优化

### 查询优化建议

```sql
-- 1. 使用分区裁剪
SELECT * FROM orders 
WHERE dt = '2024-01-01';  -- 只扫描指定分区

-- 2. 使用分桶裁剪
SELECT * FROM orders 
WHERE user_id = 12345;  -- 只扫描指定分桶

-- 3. 使用索引
-- Zone Map 自动使用
SELECT * FROM orders WHERE amount > 1000;

-- Bloom Filter 自动使用
SELECT * FROM orders WHERE user_id = 12345;

-- Bitmap Index
SELECT * FROM orders WHERE status = 'PAID';

-- Inverted Index
SELECT * FROM orders WHERE description LIKE '%keyword%';

-- 4. 使用 Colocate Join
CREATE TABLE orders (
    user_id BIGINT,
    ...
) DISTRIBUTED BY HASH(user_id) BUCKETS 32
PROPERTIES ("colocate_with" = "group1");

CREATE TABLE users (
    user_id BIGINT,
    ...
) DISTRIBUTED BY HASH(user_id) BUCKETS 32
PROPERTIES ("colocate_with" = "group1");

-- Colocate Join 不需要数据交换
SELECT * FROM orders o JOIN users u ON o.user_id = u.user_id;

-- 5. 使用物化视图
CREATE MATERIALIZED VIEW mv_daily_sales
AS SELECT dt, SUM(amount) as total_amount
FROM orders
GROUP BY dt;

-- 查询自动使用物化视图
SELECT dt, SUM(amount) FROM orders GROUP BY dt;

-- 6. 使用 Runtime Filter
-- 自动启用，无需配置
SELECT * FROM orders o 
JOIN users u ON o.user_id = u.user_id
WHERE u.city = 'Beijing';

-- Runtime Filter 会将 u.user_id 的值推送到 orders 扫描
```

### 查询分析

```sql
-- 查看执行计划
EXPLAIN SELECT * FROM orders WHERE dt = '2024-01-01';

-- 查看详细执行计划
EXPLAIN VERBOSE SELECT * FROM orders WHERE dt = '2024-01-01';

-- 查看执行 Profile
SET enable_profile = true;
SELECT * FROM orders WHERE dt = '2024-01-01';
SHOW QUERY PROFILE 'xxx';

-- Profile 输出示例
Query:
  - TotalTime: 1.234s
  Fragment 0:
    - Instance 0:
      - ScanTime: 0.5s
      - RowsReturned: 1000000
      - BytesRead: 100MB
```

## 参考资料

- [Nereids 优化器](https://github.com/apache/doris/tree/master/fe/fe-core/src/main/java/org/apache/doris/nereids)
- [向量化引擎](https://github.com/apache/doris/tree/master/be/src/vec)
- [Pipeline 引擎](https://github.com/apache/doris/tree/master/be/src/pipeline)
- [查询优化文档](https://doris.apache.org/docs/query/optimization/)
