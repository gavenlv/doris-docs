# 事务与一致性

## 概述

Doris 通过事务机制保证数据的 ACID 特性，确保并发导入和查询的数据一致性。本文深入分析 Doris 的事务模型、一致性保证和故障恢复机制。

## 事务模型

### 事务特性

```
┌─────────────────────────────────────────────────────────────┐
│                      ACID 特性                               │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  A - Atomicity (原子性)                                      │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  一个事务要么全部成功，要么全部失败                    │   │
│  │  - 导入任务的所有 Tablet 要么全部写入成功             │   │
│  │  - 任何一个 Tablet 写入失败，整个事务回滚             │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  C - Consistency (一致性)                                    │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  事务前后数据满足约束条件                             │   │
│  │  - 数据类型约束                                      │   │
│  │  - 主键唯一性约束                                    │   │
│  │  - 聚合函数约束                                      │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  I - Isolation (隔离性)                                      │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  并发事务互不干扰                                     │   │
│  │  - MVCC (多版本并发控制)                              │   │
│  │  - 快照读 (Snapshot Read)                            │   │
│  │  - 写写互斥 (Label 去重)                             │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  D - Durability (持久性)                                     │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  提交后数据持久化                                     │   │
│  │  - EditLog 持久化                                    │   │
│  │  - BDBJE 复制                                       │   │
│  │  - 数据落盘                                          │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 事务类型

```
┌─────────────────────────────────────────────────────────────┐
│                      事务类型                                │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. 导入事务 (Load Transaction)                              │
│     └── Stream Load, Broker Load, Routine Load              │
│         └── 保证数据导入的原子性                             │
│                                                              │
│  2. DDL 事务 (DDL Transaction)                               │
│     └── CREATE, ALTER, DROP 等操作                           │
│         └── 保证元数据变更的原子性                           │
│                                                              │
│  3. 副本修复事务 (Clone Transaction)                         │
│     └── 副本补齐、迁移                                      │
│         └── 保证副本一致性                                   │
│                                                              │
│  4. Compaction 事务 (Compaction Transaction)                 │
│     └── Base Compaction, Cumulative Compaction              │
│         └── 保证合并的原子性                                 │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## 多版本并发控制 (MVCC)

### 版本管理

```
┌─────────────────────────────────────────────────────────────┐
│                    MVCC 版本管理                             │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Tablet 版本链:                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                                                      │   │
│  │  Rowset 0: [v1]           (Base Rowset)             │   │
│  │  Rowset 1: [v2-v3]        (Cumulative)              │   │
│  │  Rowset 2: [v4-v6]        (Cumulative)              │   │
│  │  Rowset 3: [v7-v10]       (Cumulative)              │   │
│  │  Rowset 4: [v11]          (最新导入)                 │   │
│  │                                                      │   │
│  │  查询 v5: 读取 Rowset 0 + Rowset 1 + Rowset 2      │   │
│  │  查询 v10: 读取 Rowset 0 + Rowset 1 + Rowset 2     │   │
│  │            + Rowset 3                                │   │
│  │  查询 v11: 读取所有 Rowset                          │   │
│  │                                                      │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  版本可见性:                                                 │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  查询开始时获取当前最大版本号作为快照版本             │   │
│  │  只读取版本号 <= 快照版本的 Rowset                   │   │
│  │  导入提交后新版本对后续查询可见                      │   │
│  │  正在写入的 Rowset 对其他查询不可见                  │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 版本实现

```cpp
// 版本定义
struct Version {
    int64_t start;
    int64_t end;
    
    bool contains(int64_t v) const {
        return v >= start && v <= end;
    }
    
    bool operator<(const Version& other) const {
        return end < other.start;
    }
};

// Tablet 版本管理
class Tablet {
public:
    // 获取指定版本的 Rowsets
    Status capture_consistent_rowsets(
            const Version& version,
            std::vector<RowsetSharedPtr>* rowsets) {
        std::shared_lock<std::shared_mutex> lock(_meta_lock);
        
        for (const auto& rowset : _rowsets) {
            if (rowset->start_version() <= version.end &&
                rowset->end_version() >= version.start) {
                rowsets->push_back(rowset);
            }
        }
        
        return Status::OK();
    }
    
    // 获取最大版本号
    Version max_version() const {
        std::shared_lock<std::shared_mutex> lock(_meta_lock);
        
        if (_rowsets.empty()) {
            return Version {-1, -1};
        }
        
        return _rowsets.back()->version();
    }
    
    // 添加新 Rowset (事务提交)
    Status add_rowset(const RowsetSharedPtr& rowset) {
        std::unique_lock<std::shared_mutex> lock(_meta_lock);
        
        // 检查版本连续性
        if (!_rowsets.empty()) {
            int64_t last_end = _rowsets.back()->end_version();
            if (rowset->start_version() != last_end + 1) {
                return Status::Corruption("version not continuous");
            }
        }
        
        _rowsets.push_back(rowset);
        return Status::OK();
    }
    
private:
    std::vector<RowsetSharedPtr> _rowsets;
    mutable std::shared_mutex _meta_lock;
};
```

### 快照读

```cpp
// 查询快照
class QueryContext {
public:
    QueryContext() {
        // 获取当前快照版本
        _snapshot_version = get_current_max_version();
    }
    
    int64_t snapshot_version() const { return _snapshot_version; }
    
private:
    int64_t _snapshot_version;
};

// Tablet Reader 使用快照
class TabletReader {
public:
    Status open() {
        // 使用查询快照版本
        Version version(0, _query_ctx->snapshot_version());
        
        // 获取快照版本对应的 Rowsets
        RETURN_IF_ERROR(_tablet->capture_consistent_rowsets(
            version, &_rowset_readers));
        
        // 创建 Merger
        _merger = std::make_unique<Merger>(_schema, _rowset_readers);
        
        return Status::OK();
    }
    
    Status get_next(Block* block, bool* eos) {
        return _merger->get_next(block, eos);
    }
    
private:
    TabletSharedPtr _tablet;
    QueryContext* _query_ctx;
    std::vector<RowsetReaderSharedPtr> _rowset_readers;
    std::unique_ptr<Merger> _merger;
};
```

## 导入事务

### 事务状态机

```
┌─────────────────────────────────────────────────────────────┐
│                    导入事务状态机                             │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│                    ┌──────────┐                              │
│                    │ PENDING  │                              │
│                    │ (待处理) │                              │
│                    └────┬─────┘                              │
│                         │                                    │
│                         │ 开始执行                           │
│                         ▼                                    │
│                    ┌──────────┐                              │
│                    │ RUNNING  │                              │
│                    │ (执行中) │                              │
│                    └────┬─────┘                              │
│                         │                                    │
│              ┌──────────┼──────────┐                         │
│              │          │          │                         │
│              │ 成功     │ 失败     │ 超时                    │
│              ▼          ▼          ▼                         │
│        ┌──────────┐ ┌──────────┐ ┌──────────┐              │
│        │COMMITTED │ │ ABORTED  │ │ ABORTED  │              │
│        │ (已提交) │ │ (已中止) │ │ (已中止) │              │
│        └────┬─────┘ └──────────┘ └──────────┘              │
│             │                                                │
│             │ FE 确认                                        │
│             ▼                                                │
│        ┌──────────┐                                         │
│        │ VISIBLE  │                                         │
│        │ (可见)   │                                         │
│        └──────────┘                                         │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 事务实现

```java
// FE 端事务管理
public class TransactionManager {
    
    // 开始事务
    public long beginTransaction(String dbName, String label, 
                                  List<Tablet> tablets) {
        // 1. 检查 Label 去重
        if (_labelToTxn.containsKey(label)) {
            throw new LabelAlreadyExistsException(label);
        }
        
        // 2. 创建事务
        long txnId = _nextTxnId.getAndIncrement();
        TransactionState txnState = new TransactionState(txnId, label, dbName);
        txnState.setTablets(tablets);
        
        // 3. 注册事务
        _txnMap.put(txnId, txnState);
        _labelToTxn.put(label, txnId);
        
        // 4. 设置超时
        scheduleTimeout(txnId, _timeoutMs);
        
        return txnId;
    }
    
    // 提交事务
    public void commitTransaction(long txnId) {
        TransactionState txnState = _txnMap.get(txnId);
        
        // 1. 检查事务状态
        if (txnState.getState() != TransactionState.State.RUNNING) {
            throw new TransactionStateException(txnId);
        }
        
        // 2. 通知所有 BE 提交
        for (Backend backend : txnState.getBackends()) {
            try {
                backendService.commitTransaction(txnId);
            } catch (Exception e) {
                // 标记事务需要回滚
                txnState.setState(TransactionState.State.ABORTED);
                throw new TransactionCommitException(txnId, e);
            }
        }
        
        // 3. 写入 EditLog
        txnState.setState(TransactionState.State.COMMITTED);
        _editLog.logTransactionState(txnState);
        
        // 4. 更新 Tablet 版本
        for (Tablet tablet : txnState.getTablets()) {
            tablet.addVersion(txnState.getVersion());
        }
        
        // 5. 标记可见
        txnState.setState(TransactionState.State.VISIBLE);
        _editLog.logTransactionState(txnState);
        
        // 6. 清理事务
        _labelToTxn.remove(txnState.getLabel());
    }
    
    // 回滚事务
    public void abortTransaction(long txnId, String reason) {
        TransactionState txnState = _txnMap.get(txnId);
        
        // 1. 通知所有 BE 回滚
        for (Backend backend : txnState.getBackends()) {
            try {
                backendService.abortTransaction(txnId);
            } catch (Exception e) {
                // 忽略回滚失败
            }
        }
        
        // 2. 更新事务状态
        txnState.setState(TransactionState.State.ABORTED);
        txnState.setReason(reason);
        _editLog.logTransactionState(txnState);
        
        // 3. 清理事务
        _labelToTxn.remove(txnState.getLabel());
    }
}
```

```cpp
// BE 端事务处理
class LoadChannel {
public:
    LoadChannel(int64_t txn_id, const std::string& label);
    
    // 打开
    Status open();
    
    // 添加数据
    Status add_batch(const TabletBatch& batch);
    
    // 提交
    Status commit(int64_t* commit_version) {
        // 1. 刷新所有 DeltaWriter
        for (auto& [tablet_id, writer] : _writers) {
            RETURN_IF_ERROR(writer->flush());
        }
        
        // 2. 生成提交版本
        *commit_version = _next_version++;
        
        // 3. 发布 Rowset
        for (auto& [tablet_id, writer] : _writers) {
            RETURN_IF_ERROR(writer->commit());
        }
        
        return Status::OK();
    }
    
    // 回滚
    Status abort() {
        // 删除所有未提交的 Rowset
        for (auto& [tablet_id, writer] : _writers) {
            writer->abort();
        }
        return Status::OK();
    }
    
private:
    int64_t _txn_id;
    std::string _label;
    std::map<int64_t, std::unique_ptr<DeltaWriter>> _writers;
    int64_t _next_version;
};
```

## 副本一致性

### 副本写入

```
┌─────────────────────────────────────────────────────────────┐
│                    副本写入流程                               │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  3 副本写入:                                                 │
│                                                              │
│  FE (Leader)                                                 │
│  │                                                           │
│  │  1. 分配版本号                                            │
│  │                                                           │
│  ├──→ BE 1 (Replica 1): 写入 Rowset                        │
│  │    ├── 成功 ✓                                            │
│  │    └── 返回 ACK                                          │
│  │                                                           │
│  ├──→ BE 2 (Replica 2): 写入 Rowset                        │
│  │    ├── 成功 ✓                                            │
│  │    └── 返回 ACK                                          │
│  │                                                           │
│  └──→ BE 3 (Replica 3): 写入 Rowset                        │
│       ├── 超时 ✗                                            │
│       └── 无 ACK                                            │
│                                                              │
│  2/3 成功 → Quorum 达成 → 事务提交                          │
│  BE 3 的副本后续通过 Clone 补齐                              │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Quorum 写入

```java
// FE 端 Quorum 写入
public class QuorumWriter {
    
    // 等待 Quorum 确认
    public boolean waitForQuorum(long txnId, int replicationNum) {
        int quorum = replicationNum / 2 + 1;
        int successCount = 0;
        int failCount = 0;
        
        for (Replica replica : _replicas) {
            try {
                // 等待副本确认
                ReplicaStatus status = waitForReplicaAck(replica, txnId, _timeout);
                
                if (status == ReplicaStatus.SUCCESS) {
                    successCount++;
                } else {
                    failCount++;
                }
            } catch (TimeoutException e) {
                failCount++;
            }
            
            // 检查是否达到 Quorum
            if (successCount >= quorum) {
                return true;
            }
            
            // 检查是否不可能达到 Quorum
            if (failCount > replicationNum - quorum) {
                return false;
            }
        }
        
        return successCount >= quorum;
    }
}
```

### 副本修复

```
┌─────────────────────────────────────────────────────────────┐
│                    副本修复流程                               │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. 故障检测                                                 │
│     └── 心跳超时 / 版本落后 / 副本异常                       │
│                                                              │
│  2. 选择源副本                                               │
│     └── 选择版本最新的健康副本                               │
│                                                              │
│  3. 执行 Clone                                               │
│     ┌─────────────────────────────────────────────────┐     │
│     │  Source BE ──────→ Destination BE               │     │
│     │  (源副本)          (目标副本)                    │     │
│     │                                                   │     │
│     │  1. 请求源 BE 发送数据                           │     │
│     │  2. 源 BE 读取 Rowset                            │     │
│     │  3. 通过 RPC 传输数据                            │     │
│     │  4. 目标 BE 写入数据                             │     │
│     │  5. 更新元数据                                   │     │
│     └─────────────────────────────────────────────────┘     │
│                                                              │
│  4. 验证修复                                                 │
│     └── 检查副本版本是否一致                                 │
│                                                              │
│  5. 更新元数据                                               │
│     └── 更新 FE 中的副本状态                                 │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

```java
// 副本修复
public class CloneManager {
    
    // 检查并修复副本
    public void checkAndRepair() {
        // 1. 扫描所有 Tablet
        for (Tablet tablet : getAllTablets()) {
            // 2. 检查副本健康状态
            TabletHealthStatus status = checkTabletHealth(tablet);
            
            if (!status.isHealthy()) {
                // 3. 创建 Clone 任务
                CloneTask task = createCloneTask(tablet, status);
                
                // 4. 执行 Clone
                executeClone(task);
            }
        }
    }
    
    private TabletHealthStatus checkTabletHealth(Tablet tablet) {
        int healthyReplicas = 0;
        int staleReplicas = 0;
        int missingReplicas = 0;
        
        for (Replica replica : tablet.getReplicas()) {
            if (replica.isAlive() && replica.getVersion() == tablet.getMaxVersion()) {
                healthyReplicas++;
            } else if (replica.isAlive() && replica.getVersion() < tablet.getMaxVersion()) {
                staleReplicas++;
            } else {
                missingReplicas++;
            }
        }
        
        return new TabletHealthStatus(
            healthyReplicas, staleReplicas, missingReplicas);
    }
    
    private CloneTask createCloneTask(Tablet tablet, TabletHealthStatus status) {
        // 选择源副本 (版本最新、健康的)
        Replica sourceReplica = selectSourceReplica(tablet);
        
        // 选择目标 BE
        Backend targetBackend = selectTargetBackend(tablet);
        
        return new CloneTask(tablet, sourceReplica, targetBackend);
    }
}
```

## 数据均衡

### Tablet 均衡

```
┌─────────────────────────────────────────────────────────────┐
│                    Tablet 均衡策略                           │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  均衡目标:                                                   │
│  ├── 磁盘使用率均衡                                         │
│  ├── 副本数均衡                                             │
│  └── 跨可用区分布                                           │
│                                                              │
│  均衡流程:                                                   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  1. 计算每个 BE 的负载分数                           │   │
│  │     load_score = disk_usage * 0.5 +                  │   │
│  │                   replica_count * 0.3 +              │   │
│  │                   cpu_usage * 0.2                    │   │
│  │                                                      │   │
│  │  2. 选择高负载 BE (Source)                           │   │
│  │     source = max(load_scores)                        │   │
│  │                                                      │   │
│  │  3. 选择低负载 BE (Destination)                      │   │
│  │     dest = min(load_scores)                          │   │
│  │                                                      │   │
│  │  4. 选择要迁移的 Tablet                              │   │
│  │     - 优先迁移小 Tablet                              │   │
│  │     - 保证副本数不减少                               │   │
│  │                                                      │   │
│  │  5. 执行迁移                                         │   │
│  │     - Clone 到目标 BE                                │   │
│  │     - 验证新副本                                     │   │
│  │     - 删除旧副本                                     │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

```java
// 均衡调度器
public class BalanceManager {
    
    // 执行均衡
    public void balance() {
        // 1. 计算负载分数
        Map<Backend, Double> loadScores = calculateLoadScores();
        
        // 2. 选择源和目标
        Backend source = selectSource(loadScores);
        Backend destination = selectDestination(loadScores);
        
        if (source == null || destination == null) {
            return;
        }
        
        // 3. 选择要迁移的 Tablet
        List<Tablet> tablets = selectTabletsToMove(source, destination);
        
        // 4. 执行迁移
        for (Tablet tablet : tablets) {
            moveTablet(tablet, source, destination);
        }
    }
    
    private Map<Backend, Double> calculateLoadScores() {
        Map<Backend, Double> scores = new HashMap<>();
        
        for (Backend backend : getAllBackends()) {
            double diskUsage = backend.getDiskUsagePercent() / 100.0;
            double replicaRatio = (double) backend.getReplicaCount() / 
                                  getTotalReplicaCount();
            double cpuUsage = backend.getCpuUsagePercent() / 100.0;
            
            double score = diskUsage * 0.5 + replicaRatio * 0.3 + cpuUsage * 0.2;
            scores.put(backend, score);
        }
        
        return scores;
    }
}
```

## 故障恢复

### FE 故障恢复

```
┌─────────────────────────────────────────────────────────────┐
│                    FE 故障恢复                               │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Leader 故障                                              │
│     ┌─────────────────────────────────────────────────┐     │
│     │  a. 心跳超时检测 (5s)                            │     │
│     │  b. Follower 发起选举                            │     │
│     │  c. 多数派投票选出新 Leader                      │     │
│     │  d. 新 Leader 加载元数据                         │     │
│     │     ├── 加载最新 Image                           │     │
│     │     └── 回放 EditLog                             │     │
│     │  e. 恢复服务                                     │     │
│     └─────────────────────────────────────────────────┘     │
│                                                              │
│  2. Follower 故障                                            │
│     ┌─────────────────────────────────────────────────┐     │
│     │  a. Leader 检测到 Follower 心跳超时             │     │
│     │  b. 标记 Follower 为不可用                       │     │
│     │  c. Follower 恢复后自动同步元数据                │     │
│     │     ├── 请求缺失的 EditLog                       │     │
│     │     └── 回放日志                                 │     │
│     │  d. 恢复为可用状态                               │     │
│     └─────────────────────────────────────────────────┘     │
│                                                              │
│  3. 元数据恢复                                               │
│     ┌─────────────────────────────────────────────────┐     │
│     │  a. 从其他 FE 拷贝元数据                         │     │
│     │  b. 加载 Image 文件                              │     │
│     │  c. 回放 EditLog                                 │     │
│     │  d. 追赶进度                                     │     │
│     │  e. 加入集群                                     │     │
│     └─────────────────────────────────────────────────┘     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### BE 故障恢复

```
┌─────────────────────────────────────────────────────────────┐
│                    BE 故障恢复                               │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. BE 节点故障                                              │
│     ┌─────────────────────────────────────────────────┐     │
│     │  a. FE 检测到 BE 心跳超时 (默认 30s)           │     │
│     │  b. 标记 BE 为 DECOMMISSION                     │     │
│     │  c. 触发副本修复                                │     │
│     │     ├── 选择健康的源副本                        │     │
│     │     ├── 选择目标 BE                             │     │
│     │     └── 执行 Clone                              │     │
│     │  d. 验证新副本                                  │     │
│     │  e. 更新元数据                                  │     │
│     └─────────────────────────────────────────────────┘     │
│                                                              │
│  2. BE 恢复上线                                              │
│     ┌─────────────────────────────────────────────────┐     │
│     │  a. BE 重启                                      │     │
│     │  b. 加载 Tablet 元数据                           │     │
│     │  c. 检查本地数据完整性                           │     │
│     │  d. 向 FE 注册                                   │     │
│     │  e. FE 更新 BE 状态为 AVAILABLE                  │     │
│     │  f. 开始接收新的查询和导入请求                   │     │
│     └─────────────────────────────────────────────────┘     │
│                                                              │
│  3. 数据恢复                                                 │
│     ┌─────────────────────────────────────────────────┐     │
│     │  a. 检查本地 Tablet 版本                         │     │
│     │  b. 与 FE 元数据对比                             │     │
│     │  c. 版本落后的 Tablet:                           │     │
│     │     └── 通过 Clone 补齐缺失版本                 │     │
│     │  d. 版本超前的 Tablet:                           │     │
│     │     └── 删除多余的 Rowset                       │     │
│     │  e. 损坏的 Tablet:                               │     │
│     │     └── 从其他副本 Clone 修复                   │     │
│     └─────────────────────────────────────────────────┘     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 数据一致性校验

```sql
-- 检查 Tablet 健康状态
SHOW TABLET FROM table_name;

-- 检查副本状态
SHOW REPLICA STATUS FROM table_name;

-- 检查元数据一致性
SHOW PROC '/statistic';

-- 检查集群健康状态
SHOW PROC '/backends';
SHOW PROC '/frontends';

-- 修复损坏的 Tablet
ADMIN REPAIR TABLE table_name;

-- 设置副本状态
ADMIN SET REPLICA STATUS PROPERTIES(
    "tablet_id" = "xxx",
    "status" = "ok"
);

-- 检查 Compaction 状态
SHOW COMPACTION FROM table_name;
```

## 并发控制

### Label 去重

```java
// Label 去重机制
public class LabelCleaner {
    
    // 清理过期 Label
    public void cleanExpiredLabels() {
        long currentTime = System.currentTimeMillis();
        
        for (Map.Entry<String, LoadJob> entry : _labelToJob.entrySet()) {
            LoadJob job = entry.getValue();
            
            // 检查是否过期
            if (job.getState() == LabelState.FINISHED || 
                job.getState() == LabelState.CANCELLED) {
                long elapsed = currentTime - job.getFinishTime();
                
                if (elapsed > _labelRetentionMs) {
                    // 清理过期 Label
                    _labelToJob.remove(entry.getKey());
                }
            }
        }
    }
}
```

### 写写互斥

```java
// 写写互斥保证
public class LoadManager {
    
    // 同一 Tablet 同时只允许一个导入
    private ConcurrentHashMap<Long, ReentrantLock> _tabletLocks = 
        new ConcurrentHashMap<>();
    
    // 获取 Tablet 锁
    public boolean tryLockTablet(long tabletId) {
        ReentrantLock lock = _tabletLocks.computeIfAbsent(
            tabletId, k -> new ReentrantLock());
        return lock.tryLock();
    }
    
    // 释放 Tablet 锁
    public void unlockTablet(long tabletId) {
        ReentrantLock lock = _tabletLocks.get(tabletId);
        if (lock != null) {
            lock.unlock();
        }
    }
}
```

## 事务配置

### 关键参数

```properties
# FE 配置
# 事务超时时间
streaming_load_max_txn_timeout_ms = 3600000

# Label 保留时间
label_retain_duration_hour = 72

# 最大运行事务数
max_running_txn_num_per_db = 100

# 事务清理间隔
transaction_clean_interval_second = 30

# 副本写入超时
replica_write_timeout_seconds = 60

# BE 配置
# 导入内存限制
memtable_limit_size = 1073741824

# 写入缓冲区大小
write_buffer_size = 104857600

# 导入超时
streaming_load_rpc_max_alive_time_sec = 1200

# 副本同步超时
replica_sync_timeout_seconds = 60
```

## 事务监控

```sql
-- 查看正在运行的事务
SHOW RUNNING TRANSACTIONS;

-- 查看导入任务状态
SHOW LOAD WHERE LABEL = 'xxx';

-- 查看 Routine Load 状态
SHOW ROUTINE LOAD FOR xxx;

-- 查看事务详情
SHOW TRANSACTION WHERE ID = xxx;

-- 查看副本分布
SHOW TABLET FROM table_name ORDER BY BackendId;

-- 查看集群统计
SHOW PROC '/statistic';
```

## 参考资料

- [事务文档](https://doris.apache.org/docs/data-operate/import/import-transaction/)
- [副本管理](https://doris.apache.org/docs/administration/replica-management/)
- [数据均衡](https://doris.apache.org/docs/administration/balance/)
- [故障恢复](https://doris.apache.org/docs/administration/failure-handling/)
