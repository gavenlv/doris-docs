# 存储引擎原理

## 概述

Doris 存储引擎负责数据的持久化存储和高效读取。采用列式存储、LSM-Tree 架构，支持实时写入和高效查询。

## 存储架构

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         存储引擎整体架构                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                         写入路径 (Write Path)                          │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │  │
│  │  │   Memory    │→ │   Rowset    │→ │   Segment   │→ │   Column    │  │  │
│  │  │   Buffer    │  │   Writer    │  │   Writer    │  │   Writer    │  │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘  │  │
│  │                           │              │              │              │  │
│  │                           ▼              ▼              ▼              │  │
│  │                    ┌─────────────────────────────────────────────┐    │  │
│  │                    │              索引构建                        │    │  │
│  │                    │  Short Key | Zone Map | Bloom Filter | ...  │    │  │
│  │                    └─────────────────────────────────────────────┘    │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                    │                                         │
│                                    ▼                                         │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                         存储层 (Storage Layer)                         │  │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │  │
│  │  │                      Tablet Manager                             │  │  │
│  │  │  ┌───────────┐  ┌───────────┐  ┌───────────┐                  │  │  │
│  │  │  │  Tablet 1 │  │  Tablet 2 │  │  Tablet 3 │  ...             │  │  │
│  │  │  └───────────┘  └───────────┘  └───────────┘                  │  │  │
│  │  └─────────────────────────────────────────────────────────────────┘  │  │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │  │
│  │  │                      Rowset Manager                             │  │  │
│  │  │  ┌───────────┐  ┌───────────┐  ┌───────────┐                  │  │  │
│  │  │  │  Rowset 1 │  │  Rowset 2 │  │  Rowset 3 │  ...             │  │  │
│  │  │  │  (v1-v10) │  │ (v11-v20) │  │ (v21-v30) │                  │  │  │
│  │  │  └───────────┘  └───────────┘  └───────────┘                  │  │  │
│  │  └─────────────────────────────────────────────────────────────────┘  │  │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │  │
│  │  │                      Segment Files                              │  │  │
│  │  │  ┌─────────────────────────────────────────────────────────┐   │  │  │
│  │  │  │  Segment.dat  │  Segment.idx  │  Segment.meta            │   │  │  │
│  │  │  └─────────────────────────────────────────────────────────┘   │  │  │
│  │  └─────────────────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                    │                                         │
│                                    ▼                                         │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                         读取路径 (Read Path)                           │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │  │
│  │  │   Tablet    │→ │   Rowset    │→ │   Segment   │→ │   Column    │  │  │
│  │  │   Reader    │  │   Reader    │  │   Reader    │  │   Reader    │  │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘  │  │
│  │                           │              │              │              │  │
│  │                           ▼              ▼              ▼              │  │
│  │                    ┌─────────────────────────────────────────────┐    │  │
│  │                    │              索引过滤                        │    │  │
│  │                    │  Zone Map | Bloom Filter | Bitmap | ...     │    │  │
│  │                    └─────────────────────────────────────────────┘    │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 数据模型

### 三种数据模型

```
┌─────────────────────────────────────────────────────────────┐
│                      数据模型对比                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Duplicate Key (明细模型)                                 │
│     ┌─────────────────────────────────────────────────┐     │
│     │  Key1, Key2, Value1, Value2, Value3, ...       │     │
│     │  ─────────────────────────────────────────────  │     │
│     │  不做任何聚合，保留所有数据                      │     │
│     │  适用场景：日志、事件流、原始数据存储            │     │
│     └─────────────────────────────────────────────────┘     │
│                                                              │
│  2. Aggregate Key (聚合模型)                                 │
│     ┌─────────────────────────────────────────────────┐     │
│     │  Key1, Key2, SUM(Value1), MAX(Value2), ...     │     │
│     │  ─────────────────────────────────────────────  │     │
│     │  按 Key 预聚合，相同 Key 合并                   │     │
│     │  适用场景：报表、统计、预聚合                   │     │
│     │  聚合函数：SUM, MIN, MAX, REPLACE, HLL, ...    │     │
│     └─────────────────────────────────────────────────┘     │
│                                                              │
│  3. Unique Key (唯一主键模型)                                │
│     ┌─────────────────────────────────────────────────┐     │
│     │  Key1, Key2, Value1, Value2, Value3, ...       │     │
│     │  ─────────────────────────────────────────────  │     │
│     │  按 Key 唯一，相同 Key 覆盖更新                 │     │
│     │  适用场景：维度表、状态表、需要更新的表         │     │
│     │  实现方式：Merge-on-Read / Merge-on-Write      │     │
│     └─────────────────────────────────────────────────┘     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 数据模型实现

```cpp
// 数据模型类型
enum class KeysType {
    DUP_KEYS,       // 明细模型
    AGG_KEYS,       // 聚合模型
    UNIQUE_KEYS,    // 唯一主键模型
};

// 聚合函数类型
enum class AggregationType {
    SUM,
    MIN,
    MAX,
    REPLACE,
    REPLACE_IF_NOT_NULL,
    HLL_UNION,
    BITMAP_UNION,
    NONE,  // Duplicate Key 使用
};

// Tablet Schema
class TabletSchema {
public:
    int64_t schema_id() const { return _schema_id; }
    KeysType keys_type() const { return _keys_type; }
    
    // 获取列
    const TabletColumn& column(size_t index) const { return _cols[index]; }
    size_t num_columns() const { return _cols.size(); }
    
    // 获取 Key 列数量
    size_t num_key_columns() const { return _num_key_columns; }
    
private:
    int64_t _schema_id;
    KeysType _keys_type;
    std::vector<TabletColumn> _cols;
    size_t _num_key_columns;
};

// Tablet Column
class TabletColumn {
public:
    int32_t unique_id() const { return _unique_id; }
    std::string name() const { return _name; }
    FieldType type() const { return _type; }
    bool is_key() const { return _is_key; }
    AggregationType aggregation() const { return _aggregation; }
    
private:
    int32_t _unique_id;
    std::string _name;
    FieldType _type;
    bool _is_key;
    AggregationType _aggregation;
};
```

## 存储格式

### Segment V2 格式

```
┌─────────────────────────────────────────────────────────────┐
│                    Segment V2 文件结构                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  文件布局:                                                   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Column 0 Data                                        │   │
│  │ ├── Page 0 (Data Page)                              │   │
│  │ ├── Page 1 (Data Page)                              │   │
│  │ └── ...                                             │   │
│  ├─────────────────────────────────────────────────────┤   │
│  │ Column 1 Data                                        │   │
│  │ ├── Page 0 (Data Page)                              │   │
│  │ └── ...                                             │   │
│  ├─────────────────────────────────────────────────────┤   │
│  │ ...                                                  │   │
│  ├─────────────────────────────────────────────────────┤   │
│  │ Column N Data                                        │   │
│  ├─────────────────────────────────────────────────────┤   │
│  │ Short Key Index                                      │   │
│  │ ├── Keys (sorted)                                   │   │
│  │ └── Offsets                                         │   │
│  ├─────────────────────────────────────────────────────┤   │
│  │ Column Indexes                                       │   │
│  │ ├── Column 0 Index (Zone Map, Bloom Filter, ...)   │   │
│  │ ├── Column 1 Index                                  │   │
│  │ └── ...                                             │   │
│  ├─────────────────────────────────────────────────────┤   │
│  │ Ordinal Index                                        │   │
│  │ └── Page offset -> Row ordinal                       │   │
│  ├─────────────────────────────────────────────────────┤   │
│  │ Segment Footer                                       │   │
│  │ ├── Column Metas                                    │   │
│  │ ├── Short Key Index Meta                            │   │
│  │ ├── Num Rows                                        │   │
│  │ └── Footer Position                                 │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Page 结构

```cpp
// Page 类型
enum class PageType {
    DATA_PAGE,          // 数据页
    INDEX_PAGE,         // 索引页
    DICTIONARY_PAGE,    // 字典页
    SHORT_KEY_PAGE,     // 短键索引页
};

// Page 编码
enum class EncodingType {
    PLAIN,              // 原始编码
    PREFIX,             // 前缀编码
    RLE,                // 游程编码
    BIT_SHUFFLE,        // 位洗牌编码
    DICT,               // 字典编码
    FOR,                // Frame of Reference
};

// Page 压缩
enum class CompressionType {
    NO_COMPRESSION,
    SNAPPY,
    LZ4,
    LZ4HC,
    ZLIB,
    ZSTD,
};

// Data Page 结构
struct DataPageHeader {
    PageType type;
    EncodingType encoding;
    CompressionType compression;
    uint32_t uncompressed_size;
    uint32_t compressed_size;
    uint32_t num_rows;
    uint32_t first_ordinal;
    uint32_t null_bitmap_offset;
    uint32_t data_offset;
};

// Page 写入
class PageWriter {
public:
    // 添加值
    void add_value(const Datum& value);
    
    // 添加 NULL
    void add_null();
    
    // 完成当前 Page
    Status finish();
    
private:
    // 编码数据
    Status encode();
    
    // 压缩数据
    Status compress();
    
    // 计算 checksum
    uint32_t compute_checksum();
    
    std::unique_ptr<Encoder> _encoder;
    std::unique_ptr<Compressor> _compressor;
    std::vector<uint8_t> _data;
    std::vector<uint8_t> _null_bitmap;
    size_t _num_rows;
};
```

### 列编码

```
┌─────────────────────────────────────────────────────────────┐
│                      列编码策略                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Plain Encoding (原始编码)                                │
│     └── 直接存储原始值                                       │
│         └── 适用：高基数列、浮点数                           │
│                                                              │
│  2. Dictionary Encoding (字典编码)                           │
│     ┌─────────────────────────────────────────────────┐     │
│     │  Dictionary: [value1, value2, value3, ...]     │     │
│     │  Data: [1, 2, 1, 3, 2, 1, ...]                 │     │
│     └─────────────────────────────────────────────────┘     │
│     └── 适用：低基数字符串列                                 │
│                                                              │
│  3. RLE Encoding (游程编码)                                  │
│     ┌─────────────────────────────────────────────────┐     │
│     │  原始: [1, 1, 1, 2, 2, 3, 3, 3, 3]              │     │
│     │  编码: [(1, 3), (2, 2), (3, 4)]                │     │
│     └─────────────────────────────────────────────────┘     │
│     └── 适用：有序低基数列                                   │
│                                                              │
│  4. Prefix Encoding (前缀编码)                               │
│     ┌─────────────────────────────────────────────────┐     │
│     │  原始: ["abc_1", "abc_2", "abc_3"]              │     │
│     │  前缀: "abc_"                                   │     │
│     │  后缀: ["1", "2", "3"]                          │     │
│     └─────────────────────────────────────────────────┘     │
│     └── 适用：有公共前缀的字符串                             │
│                                                              │
│  5. Bit Shuffle Encoding (位洗牌编码)                        │
│     ┌─────────────────────────────────────────────────┐     │
│     │  将数据的位重新排列，提高压缩率                  │     │
│     │  适用：浮点数、整数                              │     │
│     └─────────────────────────────────────────────────┘     │
│                                                              │
│  6. FOR Encoding (Frame of Reference)                        │
│     ┌─────────────────────────────────────────────────┐     │
│     │  原始: [1000, 1001, 1002, 1003]                 │     │
│     │  Min: 1000                                      │     │
│     │  编码: [0, 1, 2, 3]                             │     │
│     └─────────────────────────────────────────────────┘     │
│     └── 适用：范围较小的整数                                 │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## 索引系统

### 索引类型详解

```
┌─────────────────────────────────────────────────────────────┐
│                      索引类型                                │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Short Key Index (稀疏索引)                               │
│     ┌─────────────────────────────────────────────────┐     │
│     │  每 N 行记录一个 Key 和 Offset                   │     │
│     │  ┌─────────────────────────────────────────┐    │     │
│     │  │ Key1 → Offset1                          │    │     │
│     │  │ Key2 → Offset2                          │    │     │
│     │  │ Key3 → Offset3                          │    │     │
│     │  │ ...                                     │    │     │
│     │  └─────────────────────────────────────────┘    │     │
│     │  用途：快速定位数据行                          │     │
│     │  适用：排序键 (Sort Key)                       │     │
│     └─────────────────────────────────────────────────┘     │
│                                                              │
│  2. Zone Map Index (Zone Map)                                │
│     ┌─────────────────────────────────────────────────┐     │
│     │  每个 Page 记录统计信息                         │     │
│     │  ┌─────────────────────────────────────────┐    │     │
│     │  │ Page 0: min=1, max=100, null_count=0   │    │     │
│     │  │ Page 1: min=101, max=200, null_count=2 │    │     │
│     │  │ Page 2: min=201, max=300, null_count=0 │    │     │
│     │  └─────────────────────────────────────────┘    │     │
│     │  用途：快速过滤不需要的 Page                    │     │
│     │  适用：所有列                                  │     │
│     └─────────────────────────────────────────────────┘     │
│                                                              │
│  3. Bloom Filter Index (布隆过滤器)                          │
│     ┌─────────────────────────────────────────────────┐     │
│     │  每个 Page 一个 Bloom Filter                    │     │
│     │  ┌─────────────────────────────────────────┐    │     │
│     │  │ Page 0 BF: [可能包含的值集合]            │    │     │
│     │  │ Page 1 BF: [可能包含的值集合]            │    │     │
│     │  └─────────────────────────────────────────┘    │     │
│     │  用途：快速判断值是否可能存在                  │     │
│     │  适用：等值查询 (WHERE col = value)            │     │
│     └─────────────────────────────────────────────────┘     │
│                                                              │
│  4. Bitmap Index (位图索引)                                  │
│     ┌─────────────────────────────────────────────────┐     │
│     │  每个值对应一个位图                             │     │
│     │  ┌─────────────────────────────────────────┐    │     │
│     │  │ Value A: [1, 0, 1, 0, 1, ...]           │    │     │
│     │  │ Value B: [0, 1, 0, 1, 0, ...]           │    │     │
│     │  │ Value C: [0, 0, 0, 0, 1, ...]           │    │     │
│     │  └─────────────────────────────────────────┘    │     │
│     │  用途：低基数列的快速查询                      │     │
│     │  适用：枚举、状态等低基数列                    │     │
│     └─────────────────────────────────────────────────┘     │
│                                                              │
│  5. Inverted Index (倒排索引)                                │
│     ┌─────────────────────────────────────────────────┐     │
│     │  分词 → 行号列表                                │     │
│     │  ┌─────────────────────────────────────────┐    │     │
│     │  │ "hello" → [1, 5, 10, ...]               │    │     │
│     │  │ "world" → [2, 5, 8, ...]                │    │     │
│     │  │ "doris" → [3, 7, 9, ...]                │    │     │
│     │  └─────────────────────────────────────────┘    │     │
│     │  用途：全文检索                                │     │
│     │  适用：LIKE、全文搜索                          │     │
│     └─────────────────────────────────────────────────┘     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 索引实现

```cpp
// Zone Map Index
class ZoneMapIndex {
public:
    struct ZoneMap {
        Datum min_value;
        Datum max_value;
        size_t null_count;
        bool has_null;
        bool has_not_null;
    };
    
    // 检查是否满足谓词
    bool check_predicate(const ColumnPredicate& pred, size_t page_id) const {
        const ZoneMap& zone = _zone_maps[page_id];
        
        switch (pred.type()) {
            case PredicateType::EQ:
                return zone.min_value <= pred.value() && 
                       zone.max_value >= pred.value();
            
            case PredicateType::LT:
                return zone.min_value < pred.value();
            
            case PredicateType::GT:
                return zone.max_value > pred.value();
            
            case PredicateType::IS_NULL:
                return zone.has_null;
            
            case PredicateType::IS_NOT_NULL:
                return zone.has_not_null;
            
            default:
                return true;
        }
    }
    
private:
    std::vector<ZoneMap> _zone_maps;
};

// Bloom Filter Index
class BloomFilterIndex {
public:
    // 检查值是否可能存在
    bool check_value(const Datum& value, size_t page_id) const {
        return _bloom_filters[page_id].test(value.hash());
    }
    
    // 批量检查
    void check_values(const std::vector<Datum>& values,
                     std::vector<bool>* results) const {
        for (size_t i = 0; i < values.size(); i++) {
            (*results)[i] = check_value(values[i], i);
        }
    }
    
private:
    std::vector<BloomFilter> _bloom_filters;
};

// Bitmap Index
class BitmapIndex {
public:
    // 获取值的位图
    RoaringBitmap get_bitmap(const Datum& value) const {
        auto it = _bitmaps.find(value);
        if (it != _bitmaps.end()) {
            return it->second;
        }
        return RoaringBitmap();  // 空位图
    }
    
    // 范围查询
    RoaringBitmap get_range_bitmap(const Datum& min_value, 
                                   const Datum& max_value) const {
        RoaringBitmap result;
        for (const auto& [value, bitmap] : _bitmaps) {
            if (value >= min_value && value <= max_value) {
                result |= bitmap;
            }
        }
        return result;
    }
    
private:
    std::map<Datum, RoaringBitmap> _bitmaps;
};

// Inverted Index
class InvertedIndex {
public:
    // 搜索词
    RoaringBitmap search(const std::string& term) const {
        auto it = _postings.find(term);
        if (it != _postings.end()) {
            return it->second;
        }
        return RoaringBitmap();
    }
    
    // 搜索短语
    RoaringBitmap search_phrase(const std::string& phrase) const {
        std::vector<std::string> terms = tokenize(phrase);
        if (terms.empty()) {
            return RoaringBitmap();
        }
        
        RoaringBitmap result = search(terms[0]);
        for (size_t i = 1; i < terms.size(); i++) {
            result &= search(terms[i]);
        }
        return result;
    }
    
private:
    std::map<std::string, RoaringBitmap> _postings;
};
```

## 数据写入

### 写入流程

```
┌─────────────────────────────────────────────────────────────┐
│                      数据写入流程                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. 接收数据                                                 │
│     └── FE 分配 BE 节点，创建 Load Channel                  │
│                                                              │
│  2. 内存缓冲                                                 │
│     ┌─────────────────────────────────────────────────┐     │
│     │  MemTable                                        │     │
│     │  ├── Row 1                                       │     │
│     │  ├── Row 2                                       │     │
│     │  └── ...                                         │     │
│     │                                                   │     │
│     │  排序、去重、聚合 (根据数据模型)                  │     │
│     └─────────────────────────────────────────────────┘     │
│                                                              │
│  3. 刷新到磁盘                                               │
│     ┌─────────────────────────────────────────────────┐     │
│     │  MemTable → Rowset                               │     │
│     │  ├── Segment 1                                   │     │
│     │  ├── Segment 2                                   │     │
│     │  └── ...                                         │     │
│     │                                                   │     │
│     │  构建索引、压缩、写入文件                        │     │
│     └─────────────────────────────────────────────────┘     │
│                                                              │
│  4. 提交事务                                                 │
│     ┌─────────────────────────────────────────────────┐     │
│     │  FE 写入 EditLog                                 │     │
│     │  更新 Tablet 元数据                              │     │
│     │  发布 Rowset (数据可见)                          │     │
│     └─────────────────────────────────────────────────┘     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 写入实现

```cpp
// Delta Writer
class DeltaWriter {
public:
    DeltaWriter(const TabletSharedPtr& tablet, const RowsetWriterContext& context);
    
    // 打开
    Status open();
    
    // 写入一行
    Status write(const Tuple& tuple) {
        // 添加到 MemTable
        return _mem_table->insert(tuple);
    }
    
    // 写入 Block (向量化)
    Status write(const Block& block) {
        return _mem_table->insert_block(block);
    }
    
    // 刷新到磁盘
    Status flush() {
        // 1. 排序 MemTable
        _mem_table->sort();
        
        // 2. 创建 Rowset Writer
        RowsetWriterContext context;
        RETURN_IF_ERROR(_rowset_writer->init(context));
        
        // 3. 写入数据
        while (_mem_table->has_next()) {
            Block block;
            _mem_table->get_next_block(&block);
            RETURN_IF_ERROR(_rowset_writer->add_block(block));
        }
        
        // 4. 构建索引
        RETURN_IF_ERROR(_rowset_writer->finalize());
        
        // 5. 生成 Rowset
        _rowset = _rowset_writer->build();
        
        return Status::OK();
    }
    
    // 提交
    Status commit() {
        // 发布 Rowset
        return _tablet->add_rowset(_rowset);
    }
    
private:
    TabletSharedPtr _tablet;
    std::unique_ptr<MemTable> _mem_table;
    std::unique_ptr<RowsetWriter> _rowset_writer;
    RowsetSharedPtr _rowset;
};

// MemTable
class MemTable {
public:
    // 插入数据
    Status insert(const Tuple& tuple) {
        // 根据数据模型处理
        if (_keys_type == KeysType::DUP_KEYS) {
            // 明细模型：直接插入
            _rows.push_back(tuple);
        } else if (_keys_type == KeysType::AGG_KEYS) {
            // 聚合模型：聚合相同 Key
            _aggregate(tuple);
        } else if (_keys_type == KeysType::UNIQUE_KEYS) {
            // 唯一主键模型：覆盖相同 Key
            _upsert(tuple);
        }
        return Status::OK();
    }
    
    // 排序
    void sort() {
        std::sort(_rows.begin(), _rows.end(), _comparator);
    }
    
    // 获取下一个 Block
    void get_next_block(Block* block) {
        size_t batch_size = std::min(_rows.size() - _cursor, BLOCK_SIZE);
        
        for (size_t i = 0; i < _schema.num_columns(); i++) {
            ColumnPtr column = block->get_column(i);
            for (size_t j = 0; j < batch_size; j++) {
                column->insert(_rows[_cursor + j].get(i));
            }
        }
        
        _cursor += batch_size;
    }
    
private:
    void _aggregate(const Tuple& tuple) {
        // 计算 Key Hash
        size_t hash = _compute_key_hash(tuple);
        
        auto it = _key_to_index.find(hash);
        if (it == _key_to_index.end()) {
            // 新 Key，插入
            _rows.push_back(tuple);
            _key_to_index[hash] = _rows.size() - 1;
        } else {
            // 已存在 Key，聚合
            _aggregate_row(_rows[it->second], tuple);
        }
    }
    
    void _upsert(const Tuple& tuple) {
        // 计算 Key Hash
        size_t hash = _compute_key_hash(tuple);
        
        auto it = _key_to_index.find(hash);
        if (it == _key_to_index.end()) {
            // 新 Key，插入
            _rows.push_back(tuple);
            _key_to_index[hash] = _rows.size() - 1;
        } else {
            // 已存在 Key，覆盖
            _rows[it->second] = tuple;
        }
    }
    
    TabletSchema _schema;
    KeysType _keys_type;
    std::vector<Tuple> _rows;
    std::unordered_map<size_t, size_t> _key_to_index;
    size_t _cursor = 0;
};
```

## Compaction

### Compaction 策略

```
┌─────────────────────────────────────────────────────────────┐
│                    Compaction 策略                           │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Rowset 版本链:                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ [v1] → [v2-v3] → [v4-v6] → [v7-v10] → [v11-v15]    │   │
│  │  ↑         ↑          ↑           ↑            ↑     │   │
│  │ Base    Cumulative  Cumulative  Cumulative  Cumulative│   │
│  │                                                      │   │
│  │ Cumulative Point: v7                                 │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  1. Cumulative Compaction (增量合并)                         │
│     ┌─────────────────────────────────────────────────┐     │
│     │  合并多个小的增量 Rowset                         │     │
│     │  [v7-v10] + [v11-v15] → [v7-v15]                │     │
│     │                                                   │     │
│     │  触发条件:                                        │     │
│     │  - 累积 Rowset 数量 >= threshold                 │     │
│     │  - 累积数据大小 >= threshold                     │     │
│     └─────────────────────────────────────────────────┘     │
│                                                              │
│  2. Base Compaction (基线合并)                               │
│     ┌─────────────────────────────────────────────────┐     │
│     │  合并基线和所有增量                              │     │
│     │  [v1] + [v2-v6] + [v7-v15] → [v1-v15]          │     │
│     │                                                   │     │
│     │  触发条件:                                        │     │
│     │  - 增量数据比例 >= threshold                     │     │
│     │  - 手动触发                                      │     │
│     └─────────────────────────────────────────────────┘     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Compaction 实现

```cpp
// Compaction 基类
class Compaction {
public:
    Compaction(const TabletSharedPtr& tablet);
    
    // 执行 Compaction
    Status compact();
    
protected:
    // 选择要合并的 Rowsets
    virtual Status pick_rowsets() = 0;
    
    // 执行合并
    Status do_compaction();
    
    // 修改 Tablet 元数据
    Status modify_rowsets();
    
    TabletSharedPtr _tablet;
    std::vector<RowsetSharedPtr> _input_rowsets;
    RowsetSharedPtr _output_rowset;
};

// Cumulative Compaction
class CumulativeCompaction : public Compaction {
protected:
    Status pick_rowsets() override {
        // 获取 Cumulative Point
        Version cumulative_point = _tablet->cumulative_point();
        
        // 选择连续的增量 Rowsets
        for (const auto& rowset : _tablet->rowsets()) {
            if (rowset->start_version() >= cumulative_point) {
                _input_rowsets.push_back(rowset);
            }
        }
        
        // 检查是否满足触发条件
        if (_input_rowsets.size() < config::cumulative_compaction_num_threshold) {
            return Status::NotSatisfied("not enough rowsets");
        }
        
        return Status::OK();
    }
};

// Base Compaction
class BaseCompaction : public Compaction {
protected:
    Status pick_rowsets() override {
        // 选择所有 Rowsets
        for (const auto& rowset : _tablet->rowsets()) {
            _input_rowsets.push_back(rowset);
        }
        
        // 检查是否满足触发条件
        size_t base_size = _tablet->base_rowset()->data_size();
        size_t total_size = _tablet->total_data_size();
        
        if (total_size < base_size * config::base_compaction_num_ratio) {
            return Status::NotSatisfied("not enough delta data");
        }
        
        return Status::OK();
    }
};

// Compaction 执行
Status Compaction::do_compaction() {
    // 1. 创建 Rowset Writer
    RowsetWriterContext context;
    context.tablet_schema = _tablet->tablet_schema();
    context.rowset_type = BETA_ROWSET;
    
    auto writer = std::make_unique<RowsetWriter>(context);
    RETURN_IF_ERROR(writer->init());
    
    // 2. 合并数据
    std::vector<RowsetReaderSharedPtr> readers;
    for (const auto& rowset : _input_rowsets) {
        RowsetReaderSharedPtr reader;
        RETURN_IF_ERROR(rowset->create_reader(&reader));
        readers.push_back(reader);
    }
    
    // 使用 Merger 合并
    Merger merger(_tablet->tablet_schema(), readers);
    
    Block block;
    bool eos = false;
    while (!eos) {
        RETURN_IF_ERROR(merger.get_next(&block, &eos));
        if (!eos) {
            RETURN_IF_ERROR(writer->add_block(block));
        }
    }
    
    // 3. 完成写入
    RETURN_IF_ERROR(writer->finalize());
    _output_rowset = writer->build();
    
    // 4. 修改元数据
    return modify_rowsets();
}
```

## 数据读取

### 读取流程

```
┌─────────────────────────────────────────────────────────────┐
│                      数据读取流程                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. 创建 Tablet Reader                                       │
│     └── 根据查询版本选择 Rowsets                             │
│                                                              │
│  2. 创建 Rowset Reader                                       │
│     └── 每个 Rowset 创建一个 Reader                          │
│                                                              │
│  3. 创建 Segment Reader                                      │
│     └── 每个 Segment 创建一个 Reader                         │
│                                                              │
│  4. 索引过滤                                                 │
│     ┌─────────────────────────────────────────────────┐     │
│     │  根据谓词过滤不需要的 Page                        │     │
│     │  ├── Zone Map 过滤                              │     │
│     │  ├── Bloom Filter 过滤                          │     │
│     │  ├── Bitmap Index 过滤                          │     │
│     │  └── Inverted Index 过滤                        │     │
│     └─────────────────────────────────────────────────┘     │
│                                                              │
│  5. 读取数据                                                 │
│     ┌─────────────────────────────────────────────────┐     │
│     │  读取需要的 Page                                 │     │
│     │  ├── 解压缩                                      │     │
│     │  ├── 解码                                        │     │
│     │  └── 返回 Block                                  │     │
│     └─────────────────────────────────────────────────┘     │
│                                                              │
│  6. 后处理                                                   │
│     ┌─────────────────────────────────────────────────┐     │
│     │  应用剩余谓词                                     │     │
│     │  投影需要的列                                     │     │
│     │  返回给上层算子                                   │     │
│     └─────────────────────────────────────────────────┘     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 读取实现

```cpp
// Tablet Reader
class TabletReader {
public:
    TabletReader(const TabletSharedPtr& tablet, const Version& version);
    
    // 打开
    Status open();
    
    // 读取下一个 Block
    Status get_next(Block* block, bool* eos);
    
private:
    TabletSharedPtr _tablet;
    std::vector<RowsetReaderSharedPtr> _rowset_readers;
    std::unique_ptr<Merger> _merger;
};

// Segment Reader
class SegmentReader {
public:
    // 打开
    Status open();
    
    // 读取下一个 Block
    Status get_next_block(Block* block, bool* eos) {
        // 1. 获取下一个 Page
        PagePointer page_pointer;
        RETURN_IF_ERROR(_get_next_page(&page_pointer));
        
        // 2. 读取 Page
        PageHandle page_handle;
        RETURN_IF_ERROR(_page_reader->read_page(page_pointer, &page_handle));
        
        // 3. 解压缩和解码
        RETURN_IF_ERROR(_decode_page(page_handle, block));
        
        return Status::OK();
    }
    
    // 设置谓词
    void set_predicates(const std::vector<ColumnPredicate>& predicates) {
        _predicates = predicates;
    }
    
private:
    // 获取下一个需要读取的 Page
    Status _get_next_page(PagePointer* page_pointer) {
        while (_next_page_id < _num_pages) {
            // 检查索引是否满足谓词
            if (_check_index(_next_page_id)) {
                *page_pointer = _page_pointers[_next_page_id];
                _next_page_id++;
                return Status::OK();
            }
            _next_page_id++;
        }
        return Status::EndOfFile("no more pages");
    }
    
    // 检查索引
    bool _check_index(size_t page_id) {
        for (const auto& pred : _predicates) {
            // Zone Map 过滤
            if (!_zone_map_index.check_predicate(pred, page_id)) {
                return false;
            }
            
            // Bloom Filter 过滤
            if (pred.type() == PredicateType::EQ) {
                if (!_bloom_filter_index.check_value(pred.value(), page_id)) {
                    return false;
                }
            }
        }
        return true;
    }
    
    SegmentSharedPtr _segment;
    std::unique_ptr<PageReader> _page_reader;
    std::vector<ColumnPredicate> _predicates;
    
    ZoneMapIndex _zone_map_index;
    BloomFilterIndex _bloom_filter_index;
    
    std::vector<PagePointer> _page_pointers;
    size_t _next_page_id = 0;
    size_t _num_pages;
};
```

## 缓存系统

### 缓存类型

```
┌─────────────────────────────────────────────────────────────┐
│                      缓存类型                                │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Page Cache (页缓存)                                      │
│     └── 缓存解压后的 Page 数据                               │
│         └── LRU 淘汰策略                                    │
│                                                              │
│  2. Block Cache (块缓存)                                     │
│     └── 缓存原始的磁盘块                                     │
│         └── 减少磁盘 IO                                      │
│                                                              │
│  3. Index Cache (索引缓存)                                   │
│     └── 缓存索引数据                                         │
│         └── Zone Map, Bloom Filter, Bitmap Index            │
│                                                              │
│  4. Segment Cache (段缓存)                                   │
│     └── 缓存 Segment 元数据                                  │
│         └── 减少 Segment 打开开销                            │
│                                                              │
│  5. Tablet Schema Cache                                      │
│     └── 缓存 Tablet Schema                                   │
│         └── 减少元数据解析开销                               │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 缓存实现

```cpp
// Page Cache
class PageCache {
public:
    static PageCache* instance() {
        static PageCache cache;
        return &cache;
    }
    
    // 初始化
    void init(size_t capacity) {
        _capacity = capacity;
        _lru_cache = std::make_unique<LRUCache>(capacity);
    }
    
    // 查找 Page
    bool lookup(const PageKey& key, PageHandle* handle) {
        Cache::Handle* cache_handle = _lru_cache->lookup(key.encode());
        if (cache_handle != nullptr) {
            handle->set_cache_handle(cache_handle);
            return true;
        }
        return false;
    }
    
    // 插入 Page
    void insert(const PageKey& key, const Slice& data, PageHandle* handle) {
        Cache::Handle* cache_handle = _lru_cache->insert(
            key.encode(), data.data, data.size, nullptr);
        handle->set_cache_handle(cache_handle);
    }
    
    // 释放 Page
    void release(PageHandle* handle) {
        if (handle->valid()) {
            _lru_cache->release(handle->cache_handle());
        }
    }
    
private:
    size_t _capacity;
    std::unique_ptr<LRUCache> _lru_cache;
};

// LRU Cache
class LRUCache : public Cache {
public:
    LRUCache(size_t capacity);
    
    Handle* lookup(const std::string& key) override {
        std::lock_guard<std::mutex> lock(_mutex);
        
        auto it = _cache_map.find(key);
        if (it == _cache_map.end()) {
            return nullptr;
        }
        
        // 移动到链表头部
        _lru_list.splice(_lru_list.begin(), _lru_list, it->second);
        return it->second->handle.get();
    }
    
    Handle* insert(const std::string& key, void* value, 
                   size_t size, Deleter deleter) override {
        std::lock_guard<std::mutex> lock(_mutex);
        
        // 淘汰旧条目
        while (_usage + size > _capacity && !_lru_list.empty()) {
            _evict();
        }
        
        // 插入新条目
        auto entry = std::make_unique<CacheEntry>();
        entry->key = key;
        entry->value = value;
        entry->size = size;
        entry->deleter = deleter;
        
        _lru_list.push_front(std::move(entry));
        _cache_map[key] = _lru_list.begin();
        _usage += size;
        
        return _lru_list.front()->handle.get();
    }
    
    void release(Handle* handle) override {
        // 引用计数减一
    }
    
private:
    void _evict() {
        auto& entry = _lru_list.back();
        _usage -= entry->size;
        _cache_map.erase(entry->key);
        
        if (entry->deleter) {
            entry->deleter(entry->value);
        }
        
        _lru_list.pop_back();
    }
    
    size_t _capacity;
    size_t _usage = 0;
    std::mutex _mutex;
    std::list<std::unique_ptr<CacheEntry>> _lru_list;
    std::unordered_map<std::string, 
                       std::list<std::unique_ptr<CacheEntry>>::iterator> _cache_map;
};
```

## 参考资料

- [Storage Engine 源码](https://github.com/apache/doris/tree/master/be/src/olap)
- [Segment V2 设计文档](https://doris.apache.org/docs/design/segment-v2-design/)
- [Compaction 文档](https://doris.apache.org/docs/administration/compaction/)
- [索引文档](https://doris.apache.org/docs/query/optimization/index/)
