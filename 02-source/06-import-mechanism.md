# 数据导入机制

## 概述

Doris 提供多种数据导入方式，支持实时和批量导入，保证数据的一致性和可靠性。

## 导入方式对比

```
┌─────────────────────────────────────────────────────────────┐
│                      导入方式对比                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                   Stream Load                        │   │
│  │  - 方式: HTTP PUT                                   │   │
│  │  - 场景: 实时导入、小批量导入                       │   │
│  │  - 大小: 建议 < 10GB                                │   │
│  │  - 格式: CSV, JSON, Parquet, ORC                    │   │
│  │  - 特点: 同步返回结果                               │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                   Broker Load                        │   │
│  │  - 方式: SQL 语句                                   │   │
│  │  - 场景: 批量导入、外部存储导入                     │   │
│  │  - 大小: 无限制                                     │   │
│  │  - 格式: CSV, Parquet, ORC                          │   │
│  │  - 特点: 异步执行，支持大文件                       │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                   Insert                             │   │
│  │  - 方式: INSERT INTO SELECT                         │   │
│  │  - 场景: 数据转换、表间复制                         │   │
│  │  - 大小: 建议 < 100MB                               │   │
│  │  - 特点: 同步执行                                   │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                 Routine Load                         │   │
│  │  - 方式: 持续从 Kafka 消费                          │   │
│  │  - 场景: 实时流式导入                               │   │
│  │  - 格式: CSV, JSON                                  │   │
│  │  - 特点: 自动重试、断点续传                         │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                 Binlog Load                          │   │
│  │  - 方式: MySQL Binlog 同步                          │   │
│  │  - 场景: MySQL 数据同步                             │   │
│  │  - 特点: CDC 实时同步                               │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Stream Load

### 导入流程

```
┌─────────────────────────────────────────────────────────────┐
│                    Stream Load 流程                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Client                    FE                      BE        │
│    │                        │                        │       │
│    │  1. HTTP PUT           │                        │       │
│    │  (数据 + Label)        │                        │       │
│    │───────────────────────→│                        │       │
│    │                        │                        │       │
│    │                        │  2. 检查 Label         │       │
│    │                        │  (防止重复导入)        │       │
│    │                        │                        │       │
│    │                        │  3. 分配 BE 节点       │       │
│    │                        │  (轮询/负载均衡)       │       │
│    │                        │                        │       │
│    │  4. HTTP 307 Redirect │                        │       │
│    │←───────────────────────│                        │       │
│    │                        │                        │       │
│    │  5. HTTP PUT           │                        │       │
│    │  (数据发送到 BE)       │                        │       │
│    │────────────────────────────────────────────────→│       │
│    │                        │                        │       │
│    │                        │                        │  6. 创建 Load Channel
│    │                        │                        │  7. 写入 MemTable
│    │                        │                        │  8. 刷新到磁盘
│    │                        │                        │  9. 构建索引
│    │                        │                        │
│    │                        │  10. 提交事务          │       │
│    │                        │←───────────────────────│       │
│    │                        │                        │       │
│    │                        │  11. 写入 EditLog      │       │
│    │                        │  (持久化事务)          │       │
│    │                        │                        │       │
│    │  12. 返回结果          │                        │       │
│    │←───────────────────────│                        │       │
│    │                        │                        │       │
└─────────────────────────────────────────────────────────────┘
```

### 源码实现

```java
// FE 端 Stream Load 处理
public class StreamLoadAction extends HttpBaseAction {
    
    @Override
    public void execute(HttpServletRequest request, HttpServletResponse response) {
        // 1. 解析请求
        StreamLoadTask task = parseStreamLoadTask(request);
        
        // 2. 检查 Label (防止重复导入)
        if (Catalog.getCurrentCatalog().getLoadManager().hasLabel(task.getLabel())) {
            sendResponse(response, HttpStatus.OK, 
                "Label already exists: " + task.getLabel());
            return;
        }
        
        // 3. 选择 BE 节点
        Backend backend = selectBackend(task);
        
        // 4. 重定向到 BE
        String redirectUrl = String.format("http://%s:%d/api/%s/%s/_stream_load",
            backend.getHost(), backend.getHttpPort(),
            task.getDb(), task.getTable());
        
        response.sendRedirect(redirectUrl);
    }
    
    private Backend selectBackend(StreamLoadTask task) {
        // 获取所有可用的 BE 节点
        List<Backend> backends = Catalog.getCurrentCatalog().getBackends();
        
        // 轮询选择
        int index = _roundRobinCounter.getAndIncrement() % backends.size();
        return backends.get(index);
    }
}
```

```cpp
// BE 端 Stream Load 处理
class StreamLoadAction : public HttpHandler {
public:
    void handle(HttpRequest* req) override {
        // 1. 解析请求参数
        StreamLoadContext ctx;
        ctx.db = req->param("db");
        ctx.table = req->param("table");
        ctx.label = req->header("label");
        ctx.format = req->header("format");
        ctx.column_separator = req->header("column_separator");
        
        // 2. 创建 Load Channel
        auto load_channel = std::make_shared<LoadChannel>(ctx);
        
        // 3. 创建 Delta Writer
        std::vector<DeltaWriter*> writers;
        for (auto& tablet : get_tablets(ctx)) {
            auto writer = new DeltaWriter(tablet, ctx);
            writer->open();
            writers.push_back(writer);
        }
        
        // 4. 读取并解析数据
        auto parser = create_parser(ctx.format, ctx.column_separator);
        parser->set_source(req->body());
        
        Block block;
        while (parser->has_next()) {
            parser->get_next_block(&block);
            
            // 5. 分发到对应的 Delta Writer
            for (auto& writer : writers) {
                writer->write(block);
            }
        }
        
        // 6. 刷新并提交
        for (auto& writer : writers) {
            writer->flush();
            writer->commit();
        }
        
        // 7. 返回结果
        send_response(req, HttpStatus::OK, build_result(ctx));
    }
};
```

### 使用示例

```bash
# 基本导入
curl --location-trusted -u root: \
    -H "label:load_20240101_001" \
    -H "column_separator:," \
    -T data.csv \
    http://fe:8030/api/db/table/_stream_load

# JSON 导入
curl --location-trusted -u root: \
    -H "label:load_20240101_002" \
    -H "format:json" \
    -H "strip_outer_array:true" \
    -T data.json \
    http://fe:8030/api/db/table/_stream_load

# 指定列映射
curl --location-trusted -u root: \
    -H "label:load_20240101_003" \
    -H "column_separator:," \
    -H "columns:col1,col2,col3=col1+col2" \
    -T data.csv \
    http://fe:8030/api/db/table/_stream_load

# 设置过滤条件
curl --location-trusted -u root: \
    -H "label:load_20240101_004" \
    -H "column_separator:," \
    -H "where:date > '2024-01-01'" \
    -T data.csv \
    http://fe:8030/api/db/table/_stream_load

# 并行导入
for i in {1..10}; do
    curl --location-trusted -u root: \
        -H "label:load_20240101_batch_${i}" \
        -H "column_separator:," \
        -T data_${i}.csv \
        http://fe:8030/api/db/table/_stream_load &
done
wait
```

## Broker Load

### 导入流程

```
┌─────────────────────────────────────────────────────────────┐
│                    Broker Load 流程                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Client                    FE                      BE        │
│    │                        │                        │       │
│    │  1. LOAD LABEL        │                        │       │
│    │───────────────────────→│                        │       │
│    │                        │                        │       │
│    │                        │  2. 解析 SQL          │       │
│    │                        │  3. 创建 Load Job     │       │
│    │                        │  4. 返回 Job ID       │       │
│    │←───────────────────────│                        │       │
│    │                        │                        │       │
│    │                        │  5. 异步执行           │       │
│    │                        │                        │       │
│    │                        │  ┌─────────────────┐  │       │
│    │                        │  │ Broker          │  │       │
│    │                        │  │ 读取外部存储    │  │       │
│    │                        │  │ (S3/GCS/HDFS)   │  │       │
│    │                        │  └─────────────────┘  │       │
│    │                        │         │              │       │
│    │                        │         ▼              │       │
│    │                        │  分发数据到 BE        │       │
│    │                        │────────────────────────→│      │
│    │                        │                        │       │
│    │                        │                        │  6. 写入数据
│    │                        │                        │  7. 构建索引
│    │                        │                        │
│    │                        │  8. 提交事务          │       │
│    │                        │←───────────────────────│       │
│    │                        │                        │       │
│    │  9. SHOW LOAD         │                        │       │
│    │───────────────────────→│                        │       │
│    │                        │                        │       │
│    │  10. 返回状态         │                        │       │
│    │←───────────────────────│                        │       │
│    │                        │                        │       │
└─────────────────────────────────────────────────────────────┘
```

### 源码实现

```java
// FE 端 Broker Load 处理
public class BrokerLoadJob extends LoadJob {
    
    @Override
    public void execute() {
        // 1. 获取文件列表
        List<String> files = listFiles(_brokerDesc);
        
        // 2. 计算文件大小，决定并行度
        int parallelism = calculateParallelism(files);
        
        // 3. 创建 Load Task
        for (int i = 0; i < parallelism; i++) {
            BrokerScanTask task = new BrokerScanTask(this, i, files);
            _tasks.add(task);
        }
        
        // 4. 提交任务到执行器
        for (BrokerScanTask task : _tasks) {
            Coordinator coordinator = new Coordinator(task);
            coordinator.exec();
        }
        
        // 5. 等待完成
        waitForCompletion();
    }
    
    private List<String> listFiles(BrokerDesc brokerDesc) {
        // 通过 Broker 访问外部存储
        BrokerReader reader = new BrokerReader(brokerDesc);
        return reader.listFiles(_path);
    }
}

// Broker Scan Task
public class BrokerScanTask {
    
    public void execute() {
        // 1. 连接 Broker
        BrokerReader reader = new BrokerReader(_brokerDesc);
        reader.open(_files, _offset, _length);
        
        // 2. 读取数据
        while (reader.hasNext()) {
            Block block = reader.getNextBlock(_batchSize);
            
            // 3. 发送到 BE
            for (Tablet tablet : _tablets) {
                Backend backend = selectBackend(tablet);
                sendBlockToBE(backend, block);
            }
        }
        
        // 4. 关闭连接
        reader.close();
    }
}
```

### 使用示例

```sql
-- 从 HDFS 导入
LOAD LABEL load_20240101_001
(
    DATA INFILE("hdfs://namenode:8020/data/*.parquet")
    INTO TABLE orders
    FORMAT AS "parquet"
    (order_id, user_id, amount, order_date)
)
WITH BROKER hdfs_broker
(
    "username" = "hadoop",
    "password" = ""
)
PROPERTIES
(
    "timeout" = "3600",
    "max_filter_ratio" = "0.1"
);

-- 从 S3 导入
LOAD LABEL load_20240101_002
(
    DATA INFILE("s3://bucket/data/*.csv")
    INTO TABLE orders
    COLUMNS TERMINATED BY ","
    (order_id, user_id, amount, order_date)
    SET (order_date = str_to_date(order_date, '%Y-%m-%d'))
)
WITH BROKER s3_broker
(
    "AWS_ACCESS_KEY" = "xxx",
    "AWS_SECRET_KEY" = "xxx",
    "AWS_ENDPOINT" = "s3.amazonaws.com"
)
PROPERTIES
(
    "timeout" = "3600"
);

-- 从 GCS 导入
LOAD LABEL load_20240101_003
(
    DATA INFILE("gs://bucket/data/*.parquet")
    INTO TABLE orders
    FORMAT AS "parquet"
)
WITH BROKER gcs_broker
(
    "gcs_endpoint" = "storage.googleapis.com"
)
PROPERTIES
(
    "timeout" = "3600"
);

-- 查看导入状态
SHOW LOAD WHERE LABEL = "load_20240101_001";

-- 查看导入详情
SHOW LOAD WARNINGS WHERE LABEL = "load_20240101_001";
```

## Routine Load

### 导入流程

```
┌─────────────────────────────────────────────────────────────┐
│                   Routine Load 流程                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                    Kafka Cluster                     │   │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐             │   │
│  │  │Partition│  │Partition│  │Partition│             │   │
│  │  │    0    │  │    1    │  │    2    │             │   │
│  │  └─────────┘  └─────────┘  └─────────┘             │   │
│  └─────────────────────────────────────────────────────┘   │
│         │              │              │                      │
│         ▼              ▼              ▼                      │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                   FE (Job Scheduler)                 │   │
│  │  ┌─────────────────────────────────────────────┐    │   │
│  │  │  Task 0 (P0)  │  Task 1 (P1)  │  Task 2 (P2)│    │   │
│  │  └─────────────────────────────────────────────┘    │   │
│  └─────────────────────────────────────────────────────┘   │
│         │              │              │                      │
│         ▼              ▼              ▼                      │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                      BE Cluster                      │   │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐             │   │
│  │  │   BE 1  │  │   BE 2  │  │   BE 3  │             │   │
│  │  │Consume  │  │Consume  │  │Consume  │             │   │
│  │  │ & Load  │  │ & Load  │  │ & Load  │             │   │
│  │  └─────────┘  └─────────┘  └─────────┘             │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  特点:                                                       │
│  - 每个 Partition 对应一个 Task                              │
│  - Task 分布式执行在 BE 节点上                               │
│  - 自动重试、断点续传                                        │
│  - 支持 Exactly-Once 语义                                    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 源码实现

```java
// FE 端 Routine Load Job
public class RoutineLoadJob extends LoadJob {
    
    // 任务调度
    private void scheduleTasks() {
        // 获取 Kafka 分区信息
        List<KafkaPartitionInfo> partitions = getKafkaPartitions();
        
        // 为每个分区创建 Task
        for (KafkaPartitionInfo partition : partitions) {
            RoutineLoadTask task = new RoutineLoadTask(
                this, partition.getId(), partition.getOffset());
            _tasks.add(task);
        }
        
        // 分配 Task 到 BE
        for (RoutineLoadTask task : _tasks) {
            Backend backend = selectBackend();
            task.setBackend(backend);
            
            // 发送任务到 BE
            sendTaskToBE(backend, task);
        }
    }
    
    // 处理 Task 结果
    private void handleTaskResult(RoutineLoadTaskResult result) {
        if (result.isSuccess()) {
            // 更新消费 Offset
            updateOffset(result.getPartitionId(), result.getEndOffset());
        } else {
            // 重试任务
            retryTask(result.getTaskId());
        }
    }
}
```

```cpp
// BE 端 Routine Load Task
class RoutineLoadTask {
public:
    Status execute() {
        // 1. 创建 Kafka Consumer
        KafkaConsumer consumer(_kafka_info);
        consumer.subscribe(_partition, _offset);
        
        // 2. 消费消息
        std::vector<KafkaMessage> messages;
        consumer.consume(&messages, _batch_size, _timeout);
        
        if (messages.empty()) {
            return Status::OK();
        }
        
        // 3. 解析消息
        auto parser = create_parser(_format);
        Block block;
        for (const auto& msg : messages) {
            parser->parse(msg.value(), &block);
        }
        
        // 4. 写入数据
        for (auto& writer : _writers) {
            RETURN_IF_ERROR(writer->write(block));
        }
        
        // 5. 刷新并提交
        for (auto& writer : _writers) {
            RETURN_IF_ERROR(writer->flush());
            RETURN_IF_ERROR(writer->commit());
        }
        
        // 6. 返回结果
        _result.set_success(true);
        _result.set_end_offset(messages.back().offset() + 1);
        
        return Status::OK();
    }
    
private:
    KafkaInfo _kafka_info;
    int32_t _partition;
    int64_t _offset;
    std::vector<std::unique_ptr<DeltaWriter>> _writers;
};
```

### 使用示例

```sql
-- 创建 Kafka Routine Load
CREATE ROUTINE LOAD load_kafka_orders ON orders
COLUMNS TERMINATED BY ","
PROPERTIES
(
    "desired_concurrent_number" = "3",
    "max_batch_rows" = "100000",
    "max_batch_size" = "104857600"
)
FROM KAFKA
(
    "kafka_broker_list" = "kafka1:9092,kafka2:9092,kafka3:9092",
    "kafka_topic" = "orders",
    "kafka_partitions" = "0,1,2",
    "property.group.id" = "doris_group",
    "property.client.id" = "doris_client",
    "property.kafka_default_offsets" = "OFFSET_BEGINNING"
);

-- JSON 格式
CREATE ROUTINE LOAD load_kafka_events ON events
COLUMNS (event_id, event_type, event_time, user_id)
PROPERTIES
(
    "format" = "json",
    "strip_outer_array" = "true"
)
FROM KAFKA
(
    "kafka_broker_list" = "kafka:9092",
    "kafka_topic" = "events"
);

-- 查看任务状态
SHOW ROUTINE LOAD FOR load_kafka_orders;

-- 暂停任务
PAUSE ROUTINE LOAD FOR load_kafka_orders;

-- 恢复任务
RESUME ROUTINE LOAD FOR load_kafka_orders;

-- 停止任务
STOP ROUTINE LOAD FOR load_kafka_orders;
```

## Insert 导入

### 使用示例

```sql
-- INSERT INTO VALUES (小批量)
INSERT INTO orders VALUES 
    (1, 1001, 100.00, '2024-01-01'),
    (2, 1002, 200.00, '2024-01-01'),
    (3, 1003, 300.00, '2024-01-01');

-- INSERT INTO SELECT (表间复制)
INSERT INTO orders_archive
SELECT * FROM orders WHERE order_date < '2024-01-01';

-- INSERT INTO SELECT (跨库复制)
INSERT INTO db2.orders
SELECT * FROM db1.orders WHERE order_date >= '2024-01-01';

-- INSERT INTO SELECT (带转换)
INSERT INTO orders_summary
SELECT 
    order_date,
    user_id,
    SUM(amount) as total_amount,
    COUNT(*) as order_count
FROM orders
WHERE order_date >= '2024-01-01'
GROUP BY order_date, user_id;
```

## 导入事务

### 事务保证

```
┌─────────────────────────────────────────────────────────────┐
│                      导入事务保证                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. 原子性 (Atomicity)                                       │
│     └── 一个导入任务要么全部成功，要么全部失败              │
│                                                              │
│  2. 一致性 (Consistency)                                     │
│     └── 导入后数据满足表约束                                 │
│                                                              │
│  3. 隔离性 (Isolation)                                       │
│     └── 并发导入互不影响                                     │
│                                                              │
│  4. 持久性 (Durability)                                      │
│     └── 提交后数据持久化                                     │
│                                                              │
│  事务流程:                                                   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  1. 开始事务 (BEGIN)                                 │   │
│  │     └── 分配 Transaction ID                         │   │
│  │                                                      │   │
│  │  2. 写入数据 (WRITE)                                 │   │
│  │     └── 写入 Rowset (未提交)                        │   │
│  │                                                      │   │
│  │  3. 提交事务 (COMMIT)                                │   │
│  │     ├── FE 写入 EditLog                             │   │
│  │     ├── FE 更新 Tablet 版本                         │   │
│  │     └── BE 发布 Rowset (数据可见)                   │   │
│  │                                                      │   │
│  │  4. 事务完成                                         │   │
│  │     └── 数据对查询可见                               │   │
│  │                                                      │   │
│  │  失败时:                                             │   │
│  │  ┌─────────────────────────────────────────────┐    │   │
│  │  │ ROLLBACK                                      │    │   │
│  │  │ - 删除未提交的 Rowset                        │    │   │
│  │  │ - 释放资源                                   │    │   │
│  │  └─────────────────────────────────────────────┘    │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Label 机制

```java
// Label 去重机制
public class LoadManager {
    
    // Label 状态
    public enum LabelState {
        PENDING,    // 待处理
        RUNNING,    // 执行中
        FINISHED,   // 已完成
        CANCELLED,  // 已取消
        UNKNOWN,    // 未知
    }
    
    // 检查 Label
    public LabelState checkLabelState(String label) {
        LoadJob job = _labelToJob.get(label);
        if (job == null) {
            return LabelState.UNKNOWN;
        }
        return job.getState();
    }
    
    // 开始导入
    public void beginLoad(String label, LoadJob job) {
        // 检查 Label 是否已存在
        if (_labelToJob.containsKey(label)) {
            throw new LabelAlreadyExistsException(label);
        }
        
        // 注册 Label
        _labelToJob.put(label, job);
        
        // 设置超时清理
        scheduleCleanup(label);
    }
    
    // 完成导入
    public void finishLoad(String label) {
        LoadJob job = _labelToJob.get(label);
        if (job != null) {
            job.setState(LabelState.FINISHED);
        }
    }
}
```

## 导入性能优化

### 优化策略

```
┌─────────────────────────────────────────────────────────────┐
│                    导入性能优化策略                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. 并行导入                                                 │
│     ┌─────────────────────────────────────────────────┐     │
│     │  多个并发导入任务                                │     │
│     │  - Stream Load: 多个 HTTP 请求                  │     │
│     │  - Broker Load: 多个 Scan Task                  │     │
│     │  - Routine Load: 多个 Partition 并行消费        │     │
│     └─────────────────────────────────────────────────┘     │
│                                                              │
│  2. 批量写入                                                 │
│     ┌─────────────────────────────────────────────────┐     │
│     │  增大批次大小                                    │     │
│     │  - streaming_load_max_mb: 10240                 │     │
│     │  - max_batch_rows: 100000                       │     │
│     │  - max_batch_size: 104857600                    │     │
│     └─────────────────────────────────────────────────┘     │
│                                                              │
│  3. 内存优化                                                 │
│     ┌─────────────────────────────────────────────────┐     │
│     │  调整 MemTable 大小                              │     │
│     │  - memtable_limit_size: 1GB                     │     │
│     │  - write_buffer_size: 100MB                     │     │
│     └─────────────────────────────────────────────────┘     │
│                                                              │
│  4. Compaction 优化                                          │
│     ┌─────────────────────────────────────────────────┐     │
│     │  增加 Compaction 线程                            │     │
│     │  - base_compaction_num_threads_per_disk: 4      │     │
│     │  - cumulative_compaction_num_threads_per_disk: 4│     │
│     │                                                   │     │
│     │  调整触发阈值                                     │     │
│     │  - cumulative_compaction_num_threshold: 10      │     │
│     │  - base_compaction_num_ratio: 0.3               │     │
│     └─────────────────────────────────────────────────┘     │
│                                                              │
│  5. 数据格式优化                                             │
│     ┌─────────────────────────────────────────────────┐     │
│     │  使用列式格式                                    │     │
│     │  - Parquet: 高压缩比，适合批量导入              │     │
│     │  - ORC: 高性能，适合大规模数据                  │     │
│     │                                                   │     │
│     │  压缩格式                                         │     │
│     │  - LZ4: 快速压缩                                 │     │
│     │  - ZSTD: 高压缩比                                │     │
│     └─────────────────────────────────────────────────┘     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 最佳实践

```sql
-- 1. 合理设置分区
CREATE TABLE orders (
    order_id BIGINT,
    user_id BIGINT,
    amount DECIMAL(10,2),
    order_date DATE
)
PARTITION BY RANGE(order_date) (
    PARTITION p202401 VALUES LESS THAN ('2024-02-01'),
    PARTITION p202402 VALUES LESS THAN ('2024-03-01'),
    ...
)
DISTRIBUTED BY HASH(order_id) BUCKETS 32;

-- 2. 使用动态分区
CREATE TABLE orders (
    ...
)
PARTITION BY RANGE(order_date) ()
DISTRIBUTED BY HASH(order_id) BUCKETS 32
PROPERTIES (
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-30",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p"
);

-- 3. 预聚合优化
CREATE TABLE orders_agg (
    order_date DATE,
    user_id BIGINT,
    total_amount SUM(DECIMAL(10,2)),
    order_count SUM(INT)
)
AGGREGATE KEY(order_date, user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 32;

-- 4. 导入时过滤
curl --location-trusted -u root: \
    -H "label:load_001" \
    -H "where:order_date >= '2024-01-01'" \
    -T data.csv \
    http://fe:8030/api/db/orders/_stream_load

-- 5. 导入时转换
curl --location-trusted -u root: \
    -H "label:load_002" \
    -H "columns:order_id,user_id,amount,order_date=str_to_date(order_date_str,'%Y-%m-%d')" \
    -T data.csv \
    http://fe:8030/api/db/orders/_stream_load
```

## 参考资料

- [Stream Load 文档](https://doris.apache.org/docs/data-operate/import/import-way/stream-load-manual/)
- [Broker Load 文档](https://doris.apache.org/docs/data-operate/import/import-way/broker-load-manual/)
- [Routine Load 文档](https://doris.apache.org/docs/data-operate/import/import-way/routine-load-manual/)
- [导入最佳实践](https://doris.apache.org/docs/data-operate/import/import-best-practice/)
