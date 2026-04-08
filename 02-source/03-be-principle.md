# BE 核心原理

## BE 概述

Backend (BE) 是 Doris 的后端节点，负责数据存储和查询执行。BE 采用 C++ 实现，支持向量化执行引擎，提供高性能的数据处理能力。

## BE 架构

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              BE 内部架构                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                         服务层 (Service Layer)                          │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │  │
│  │  │ BE Service  │  │ HTTP Server │  │ Brpc Server │  │  Heartbeat  │  │  │
│  │  │  (9030)     │  │   (8040)    │  │   (9060)    │  │   (9050)    │  │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘  │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                    │                                         │
│                                    ▼                                         │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                         执行层 (Execution Layer)                        │  │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │  │
│  │  │                    Fragment Manager                              │  │  │
│  │  │  - Fragment 执行管理                                            │  │  │
│  │  │  - Pipeline 执行引擎                                            │  │  │
│  │  │  - Task 调度                                                    │  │  │
│  │  └─────────────────────────────────────────────────────────────────┘  │  │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │  │
│  │  │                    Query Engine                                 │  │  │
│  │  │  ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌───────────┐      │  │  │
│  │  │  │ Scan Node │ │ Join Node │ │ Agg Node  │ │ Sort Node │      │  │  │
│  │  │  └───────────┘ └───────────┘ └───────────┘ └───────────┘      │  │  │
│  │  └─────────────────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                    │                                         │
│                                    ▼                                         │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                         存储层 (Storage Layer)                          │  │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │  │
│  │  │                    Storage Engine                               │  │  │
│  │  │  ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌───────────┐      │  │  │
│  │  │  │  Tablet   │ │  Rowset   │ │  Segment  │ │   Page    │      │  │  │
│  │  │  │  Manager  │ │  Manager  │ │  Reader   │ │   Reader  │      │  │  │
│  │  │  └───────────┘ └───────────┘ └───────────┘ └───────────┘      │  │  │
│  │  └─────────────────────────────────────────────────────────────────┘  │  │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │  │
│  │  │                    Index Engine                                 │  │  │
│  │  │  ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌───────────┐      │  │  │
│  │  │  │   Zone    │ │  Bloom    │ │   Bitmap  │ │  Inverted │      │  │  │
│  │  │  │   Map     │ │  Filter   │ │   Index   │ │   Index   │      │  │  │
│  │  │  └───────────┘ └───────────┘ └───────────┘ └───────────┘      │  │  │
│  │  └─────────────────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                    │                                         │
│                                    ▼                                         │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                         缓存层 (Cache Layer)                            │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                    │  │
│  │  │ Page Cache  │  │ Block Cache │  │ IO Context  │                    │  │
│  │  │  (页缓存)   │  │  (块缓存)   │  │  (IO上下文) │                    │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                    │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 核心模块详解

### 1. 存储引擎 (Storage Engine)

#### 源码位置

```
be/src/olap/
├── storage_engine.cpp        # 存储引擎入口
├── tablet.cpp                # Tablet 实现
├── tablet_manager.cpp        # Tablet 管理器
├── tablet_meta.cpp           # Tablet 元数据
├── rowset/                   # Rowset 管理
│   ├── rowset.cpp
│   ├── rowset_writer.cpp
│   ├── rowset_reader.cpp
│   └── segment_v2/           # Segment V2 格式
│       ├── segment.cpp
│       ├── segment_writer.cpp
│       └── segment_reader.cpp
├── delta_writer.cpp          # 增量写入器
├── compaction/               # Compaction
│   ├── compaction.cpp
│   ├── base_compaction.cpp
│   └── cumulative_compaction.cpp
└── tablet_schema.cpp         # Tablet Schema
```

#### 存储层次结构

```
┌─────────────────────────────────────────────────────────────┐
│                      存储层次结构                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Tablet (分片)                                               │
│  └── 数据分布的最小单位                                      │
│      └── 一个表的一个分桶的一个副本                          │
│                                                              │
│  Rowset (行集合)                                             │
│  └── 一次导入的数据                                          │
│      └── 包含一个或多个 Segment                              │
│                                                              │
│  Segment (段)                                                │
│  └── Rowset 内的数据分片                                     │
│      └── 列式存储，每个列一个文件                            │
│                                                              │
│  Column (列)                                                 │
│  └── 单个列的数据                                            │
│      └── 包含多个 Page                                       │
│                                                              │
│  Page (页)                                                   │
│  └── 列数据的基本存储单位                                    │
│      └── 压缩存储，支持多种编码                              │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

#### Tablet 核心类

```cpp
// Tablet 定义
class Tablet {
public:
    Tablet(TabletMetaSharedPtr tablet_meta, DataDir* data_dir);
    
    // 获取 Tablet 元数据
    TabletMetaSharedPtr tablet_meta() const { return _tablet_meta; }
    
    // 获取所有 Rowset
    const RowsetSharedPtr& rowset() const { return _rowset; }
    
    // 增量写入
    Status add_rowset(RowsetSharedPtr rowset);
    
    // Compaction
    Status run_compaction(CompactionType type);
    
    // 读取数据
    Status capture_consistent_rowsets(const Version& version,
                                      std::vector<RowsetSharedPtr>* rowsets);
    
private:
    TabletMetaSharedPtr _tablet_meta;      // 元数据
    RowsetSharedPtr _rowset;               // 当前 Rowset
    std::shared_mutex _meta_lock;          // 元数据锁
    std::shared_mutex _rowset_update_lock; // Rowset 更新锁
};

// Tablet 元数据
class TabletMeta {
public:
    int64_t tablet_id() const { return _tablet_id; }
    int64_t table_id() const { return _table_id; }
    int64_t partition_id() const { return _partition_id; }
    TabletSchemaSPtr tablet_schema() const { return _schema; }
    
    // 版本信息
    const std::vector<Version>& all_rs_versions() const;
    Version max_version() const;
    
    // 序列化/反序列化
    Status serialize(std::string* meta_binary);
    Status deserialize(const std::string& meta_binary);
    
private:
    int64_t _tablet_id;
    int64_t _table_id;
    int64_t _partition_id;
    TabletSchemaSPtr _schema;
    std::vector<Version> _rs_versions;
};
```

### 2. Rowset 管理

#### Rowset 结构

```
┌─────────────────────────────────────────────────────────────┐
│                      Rowset 结构                             │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Rowset                                                      │
│  ├── RowsetMeta (元数据)                                     │
│  │   ├── rowset_id                                          │
│  │   ├── start_version / end_version                        │
│  │   ├── num_rows                                           │
│  │   ├── total_disk_size                                    │
│  │   └── tablet_schema                                      │
│  │                                                           │
│  └── Segments (数据文件)                                     │
│      ├── segment_0.dat                                      │
│      ├── segment_1.dat                                      │
│      ├── ...                                                │
│      └── segment_n.dat                                      │
│                                                              │
│  每个 Segment 文件包含:                                       │
│  ├── 列数据文件 (.dat)                                       │
│  ├── 索引文件 (.idx)                                         │
│  └── 元数据文件 (.meta)                                      │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

#### Rowset 写入流程

```cpp
// RowsetWriter 负责写入数据
class RowsetWriter {
public:
    // 初始化
    Status init(const RowsetWriterContext& context);
    
    // 添加一行数据
    Status add_row(const Tuple& tuple);
    
    // 添加一个 Block (向量化)
    Status add_block(const vectorized::Block& block);
    
    // 刷新到磁盘
    Status flush();
    
    // 构建索引
    Status finalize();
    
    // 获取生成的 Rowset
    RowsetSharedPtr build();
    
private:
    std::unique_ptr<SegmentWriter> _segment_writer;
    std::vector<std::string> _segment_files;
    RowsetMetaSharedPtr _rowset_meta;
};

// 写入流程
Status RowsetWriter::add_block(const vectorized::Block& block) {
    // 1. 写入列数据
    _segment_writer->append_block(block);
    
    // 2. 构建索引
    _segment_writer->add_row_indexes();
    
    // 3. 检查是否需要切换 Segment
    if (_segment_writer->is_full()) {
        flush();
        create_new_segment();
    }
    
    return Status::OK();
}
```

### 3. Segment V2 格式

#### Segment 文件结构

```
┌─────────────────────────────────────────────────────────────┐
│                    Segment V2 文件结构                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Segment File                                                │
│  │                                                           │
│  ├── Footer (文件尾部)                                       │
│  │   ├── Segment Footer                                     │
│  │   │   ├── columns (列元数据)                             │
│  │   │   ├── num_rows                                       │
│  │   │   └── short_key_index_meta                           │
│  │   └── File Footer                                        │
│  │       ├── footer_position                                │
│  │       └── magic_number                                   │
│  │                                                           │
│  ├── Column Data (列数据)                                    │
│  │   ├── Column 0                                           │
│  │   │   ├── Page 0                                         │
│  │   │   │   ├── Data Page                                  │
│  │   │   │   │   ├── values (压缩)                          │
│  │   │   │   │   ├── offsets                                │
│  │   │   │   │   └── null_bitmap                            │
│  │   │   │   └── Page Footer                                │
│  │   │   ├── Page 1                                         │
│  │   │   └── ...                                            │
│  │   ├── Column 1                                           │
│  │   └── ...                                                │
│  │                                                           │
│  ├── Index Data (索引数据)                                   │
│  │   ├── Short Key Index (稀疏索引)                         │
│  │   │   ├── keys                                           │
│  │   │   └── offsets                                        │
│  │   ├── Column Index (列索引)                              │
│  │   │   ├── Zone Map (min/max/null_count)                  │
│  │   │   ├── Bloom Filter                                   │
│  │   │   └── Bitmap Index                                   │
│  │   └── Inverted Index (倒排索引)                          │
│  │                                                           │
│  └── Ordinal Index (行号索引)                                │
│      └── Page offset -> Row ordinal                          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

#### Page 结构

```cpp
// Page 是列数据的基本存储单位
class DataPage {
public:
    // Page 类型
    enum Type {
        DATA_PAGE,
        INDEX_PAGE,
        DICTIONARY_PAGE,
    };
    
    // 编码类型
    enum Encoding {
        PLAIN_ENCODING,
        PREFIX_ENCODING,
        RLE_ENCODING,
        BIT_SHUFFLE,
        DICT_ENCODING,
    };
    
    // 压缩类型
    enum Compression {
        NO_COMPRESSION,
        SNAPPY,
        LZ4,
        ZLIB,
        ZSTD,
    };
    
private:
    Type _type;
    Encoding _encoding;
    Compression _compression;
    
    std::string _data;          // 压缩后的数据
    std::string _offsets;       // 偏移量 (变长类型)
    std::string _null_bitmap;   // NULL 位图
    
    size_t _num_rows;           // 行数
    size_t _uncompressed_size;  // 未压缩大小
};

// Page 读取
class PageReader {
public:
    Status read_page(const PagePointer& page_pointer, PageHandle* handle);
    
private:
    Status decompress_page(const std::string& compressed_data,
                          std::string* decompressed_data);
    Status decode_page(const std::string& encoded_data,
                      vectorized::Column* column);
};
```

### 4. 索引系统

#### 索引类型

```
┌─────────────────────────────────────────────────────────────┐
│                      索引类型                                │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Short Key Index (稀疏索引)                               │
│     └── 用于快速定位数据行                                   │
│         └── 每 N 行记录一个 Key                              │
│                                                              │
│  2. Zone Map (Zone Map)                                      │
│     └── 每个 Page 的 min/max/null_count                      │
│         └── 用于快速过滤不需要的 Page                        │
│                                                              │
│  3. Bloom Filter (布隆过滤器)                                │
│     └── 快速判断值是否存在                                   │
│         └── 用于等值查询过滤                                 │
│                                                              │
│  4. Bitmap Index (位图索引)                                  │
│     └── 低基数列的快速查询                                   │
│         └── 用于等值和范围查询                               │
│                                                              │
│  5. Inverted Index (倒排索引)                                │
│     └── 全文检索                                             │
│         └── 用于 LIKE、全文搜索                              │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

#### 索引使用示例

```cpp
// Zone Map 索引
class ZoneMapIndex {
public:
    struct ZoneMap {
        Datum min_value;
        Datum max_value;
        size_t null_count;
        bool has_null;
    };
    
    // 检查是否满足谓词
    bool satisfy_predicate(const ColumnPredicate& pred) const {
        switch (pred.type()) {
            case EQ:
                return min_value <= pred.value() && max_value >= pred.value();
            case LT:
                return min_value < pred.value();
            case GT:
                return max_value > pred.value();
            case IS_NULL:
                return has_null;
            default:
                return true;
        }
    }
    
private:
    std::vector<ZoneMap> _zone_maps;  // 每个 Page 一个
};

// Bloom Filter 索引
class BloomFilterIndex {
public:
    // 检查值是否可能存在
    bool test(const Datum& value) const {
        return _bloom_filter.test(value.hash());
    }
    
    // 批量检查
    void test_batch(const std::vector<Datum>& values, 
                   std::vector<bool>* results) const {
        for (size_t i = 0; i < values.size(); i++) {
            (*results)[i] = test(values[i]);
        }
    }
    
private:
    BloomFilter _bloom_filter;
};
```

### 5. Compaction 机制

#### Compaction 类型

```
┌─────────────────────────────────────────────────────────────┐
│                    Compaction 类型                           │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Cumulative Compaction (增量合并)                         │
│     └── 合并多个小的 Rowset                                  │
│         └── 减少文件数量，提高查询性能                       │
│                                                              │
│  2. Base Compaction (基线合并)                               │
│     └── 合并增量数据和基线数据                               │
│         └── 生成新的基线，释放旧数据                         │
│                                                              │
│  Compaction 触发条件:                                        │
│  ├── 累积 Rowset 数量 >= cumulative_compaction_num_threshold │
│  ├── 累积数据大小 >= cumulative_compaction_size_threshold   │
│  └── 手动触发: ALTER TABLE COMPACT                          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

#### Compaction 流程

```cpp
// Compaction 执行
class Compaction {
public:
    Status compact();
    
protected:
    // 选择需要合并的 Rowsets
    virtual Status pick_rowsets_to_compact() = 0;
    
    // 执行合并
    Status do_compaction();
    
    // 修改 Tablet 元数据
    Status modify_rowsets();
    
private:
    TabletSharedPtr _tablet;
    std::vector<RowsetSharedPtr> _input_rowsets;
    RowsetSharedPtr _output_rowset;
};

// Cumulative Compaction
class CumulativeCompaction : public Compaction {
protected:
    Status pick_rowsets_to_compaction() override {
        // 选择连续的增量 Rowsets
        // 从最新的 cumulative point 开始
        // 选择满足条件的 Rowsets
    }
};

// Base Compaction
class BaseCompaction : public Compaction {
protected:
    Status pick_rowsets_to_compaction() override {
        // 选择所有增量 Rowsets + 基线 Rowset
        // 合并成新的基线
    }
};
```

### 6. 查询执行

#### 向量化执行引擎

```cpp
// 向量化执行节点
namespace vectorized {

class VScanNode : public ExecNode {
public:
    // 打开扫描节点
    Status open(RuntimeState* state) override;
    
    // 获取下一个 Block
    Status get_next(RuntimeState* state, Block* block, bool* eos) override;
    
    // 关闭扫描节点
    Status close(RuntimeState* state) override;
    
private:
    // 扫描参数
    std::vector<TabletReader> _tablet_readers;
    std::vector<SlotDescriptor*> _slots;
    std::vector<ExprContext*> _conjunct_ctxs;
    
    // 读取器
    std::unique_ptr<RowsetReader> _reader;
};

class VHashJoinNode : public ExecNode {
public:
    Status open(RuntimeState* state) override;
    Status get_next(RuntimeState* state, Block* block, bool* eos) override;
    
private:
    // 构建哈希表
    Status build_hash_table();
    
    // 探测哈希表
    Status probe_hash_table(Block* probe_block, Block* output_block);
    
    // 哈希表
    std::unique_ptr<HashTable> _hash_table;
    
    // 构建端/探测端
    VScanNode* _build_child;
    VScanNode* _probe_child;
};

class VAggregationNode : public ExecNode {
public:
    Status open(RuntimeState* state) override;
    Status get_next(RuntimeState* state, Block* block, bool* eos) override;
    
private:
    // 聚合函数
    std::vector<AggregateFunction> _agg_functions;
    
    // 聚合状态
    std::unique_ptr<AggregationState> _agg_state;
    
    // 分组键
    std::vector<SlotDescriptor*> _group_by_slots;
};

} // namespace vectorized
```

#### Pipeline 执行引擎

```cpp
// Pipeline 执行引擎
class Pipeline {
public:
    // 创建 Pipeline
    static Status create(const ExecPlan& plan, std::unique_ptr<Pipeline>* pipeline);
    
    // 准备执行
    Status prepare(RuntimeState* state);
    
    // 执行
    Status execute(RuntimeState* state);
    
private:
    std::vector<std::unique_ptr<Operator>> _operators;
    std::unique_ptr<RuntimeState> _runtime_state;
};

// Operator (算子)
class Operator {
public:
    virtual Status open(RuntimeState* state) = 0;
    virtual Status get_next(RuntimeState* state, Block* block, bool* eos) = 0;
    virtual Status close(RuntimeState* state) = 0;
};

// Scan Operator
class ScanOperator : public Operator {
public:
    Status get_next(RuntimeState* state, Block* block, bool* eos) override {
        // 从存储引擎读取数据
        return _reader->get_next(block, eos);
    }
    
private:
    std::unique_ptr<TabletReader> _reader;
};

// Join Operator
class JoinOperator : public Operator {
public:
    Status get_next(RuntimeState* state, Block* block, bool* eos) override {
        // 执行 Join 操作
        return probe_hash_table(block, eos);
    }
};
```

### 7. 内存管理

#### 内存池

```cpp
// 内存池管理
class MemPool {
public:
    MemPool(size_t chunk_size = 4096);
    ~MemPool();
    
    // 分配内存
    void* allocate(size_t size) {
        if (_current_chunk->remaining() < size) {
            allocate_chunk(std::max(size, _chunk_size));
        }
        return _current_chunk->allocate(size);
    }
    
    // 清空 (不释放内存)
    void clear() {
        for (auto& chunk : _chunks) {
            chunk->clear();
        }
        _current_chunk = _chunks[0].get();
    }
    
    // 释放所有内存
    void free_all() {
        _chunks.clear();
        _current_chunk = nullptr;
    }
    
private:
    std::vector<std::unique_ptr<MemChunk>> _chunks;
    MemChunk* _current_chunk;
    size_t _chunk_size;
};

// 内存追踪
class MemTracker {
public:
    MemTracker(int64_t limit = -1, const std::string& label = "");
    
    // 分配内存
    void consume(int64_t bytes) {
        _consumption += bytes;
        if (_limit > 0 && _consumption > _limit) {
            throw std::bad_alloc();
        }
    }
    
    // 释放内存
    void release(int64_t bytes) {
        _consumption -= bytes;
    }
    
    // 获取当前使用量
    int64_t consumption() const { return _consumption; }
    
private:
    int64_t _limit;
    std::atomic<int64_t> _consumption;
    std::string _label;
};
```

## 关键配置参数

### BE 配置文件 (be.conf)

```properties
# 存储配置
storage_root_path = /opt/doris/be/storage
enable_storage_vectorization = true

# 内存配置
mem_limit = 80%
query_memory_limit = 80%
storage_page_cache_limit = 40GB

# 线程池配置
scan_thread_pool_thread_num = 48
scan_thread_pool_queue_size = 102400
fragment_pool_thread_num_min = 64
fragment_pool_thread_num_max = 512

# Compaction 配置
base_compaction_num_threads_per_disk = 4
cumulative_compaction_num_threads_per_disk = 4
base_compaction_num_cumulative_deltas = 5
cumulative_compaction_num_cumulative_deltas = 10

# 导入配置
streaming_load_max_mb = 10240
streaming_load_rpc_max_alive_time_sec = 1200
max_send_batch_parallelism_per_job = 10

# 网络配置
be_port = 9060
webserver_port = 8040
heartbeat_service_port = 9050
brpc_port = 8060
```

## 常用运维命令

### BE 状态查看

```sql
-- 查看 BE 节点状态
SHOW BACKENDS;

-- 查看 Tablet 状态
SHOW TABLET FROM table_name;

-- 查看 Compaction 状态
SHOW COMPACTION FROM table_name;

-- 查看磁盘使用
SHOW DISK FROM table_name;
```

### Compaction 管理

```sql
-- 手动触发 Compaction
ALTER TABLE table_name COMPACT;

-- 查看 Compaction 进度
SHOW COMPACTION FROM table_name;

-- 取消 Compaction
CANCEL COMPACTION FROM table_name;
```

## 参考资料

- [BE 源码](https://github.com/apache/doris/tree/master/be)
- [Storage Engine 源码](https://github.com/apache/doris/tree/master/be/src/olap)
- [Vectorized Engine 源码](https://github.com/apache/doris/tree/master/be/src/vec)
- [Pipeline Engine 源码](https://github.com/apache/doris/tree/master/be/src/pipeline)
