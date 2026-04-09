# 数据导入

## 概述

Doris 提供多种数据导入方式，适用于不同的场景和需求。

```
┌─────────────────────────────────────────────────────────────┐
│                    数据导入方式                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Stream Load    HTTP 接口，适合小批量实时导入         │   │
│  │  ─────────────────────────────────────────────────── │   │
│  │  特点：简单、实时、支持 CSV/JSON                      │   │
│  │  场景：实时数据接入、小批量导入                       │   │
│  │  吞吐：单次 < 10GB                                   │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Broker Load    外部存储导入，适合大批量离线导入      │   │
│  │  ─────────────────────────────────────────────────── │   │
│  │  特点：支持 HDFS/S3、大批量、异步                     │   │
│  │  场景：离线数据迁移、批量导入                        │   │
│  │  吞吐：无限制                                        │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Routine Load    Kafka 持续导入                       │   │
│  │  ─────────────────────────────────────────────────── │   │
│  │  特点：持续消费、自动重试、Exactly-Once               │   │
│  │  场景：实时数据流、CDC 同步                          │   │
│  │  吞吐：持续                                          │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Insert    SQL 插入                                   │   │
│  │  ─────────────────────────────────────────────────── │   │
│  │  特点：简单、灵活、支持子查询                         │   │
│  │  场景：测试、小数据量、数据转换                       │   │
│  │  吞吐：较低                                          │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Flink Doris Connector    Flink 实时导入              │   │
│  │  ─────────────────────────────────────────────────── │   │
│  │  特点：高吞吐、Exactly-Once、支持 CDC                 │   │
│  │  场景：实时数仓、数据同步                            │   │
│  │  吞吐：高                                            │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 一、Stream Load

### 基本用法

```bash
# 基本语法
curl --location-trusted -u user:password \
    -H "label:label_name" \
    -H "column_separator:separator" \
    -T data_file \
    http://fe_host:http_port/api/db/table/_stream_load

# 示例：导入 CSV 文件
curl --location-trusted -u root: \
    -H "label:load_users_001" \
    -H "column_separator:," \
    -T users.csv \
    http://127.0.0.1:8030/api/mydb/users/_stream_load
```

### 参数详解

```bash
curl --location-trusted -u root:password \
    -H "label:load_20240115_001" \           # 导入标签，保证幂等性
    -H "column_separator:," \                # 列分隔符
    -H "line_delimiter:\n" \                 # 行分隔符
    -H "skip_header:1" \                     # 跳过首行
    -H "format:csv" \                        # 格式：csv/json
    -H "max_filter_ratio:0.1" \              # 最大错误率 10%
    -H "timeout:600" \                       # 超时时间（秒）
    -H "columns:user_id,user_name,age,city" \ # 列映射
    -H "where:age>18" \                      # 过滤条件
    -H "partitions:p202401,p202402" \        # 指定分区
    -T data.csv \
    http://127.0.0.1:8030/api/mydb/users/_stream_load
```

### 导入 CSV

```bash
# 准备数据文件 users.csv
cat > users.csv << EOF
user_id,user_name,age,city
1,张三,25,北京
2,李四,30,上海
3,王五,28,广州
EOF

# 导入
curl --location-trusted -u root: \
    -H "label:load_users_csv" \
    -H "column_separator:," \
    -H "skip_header:1" \
    -T users.csv \
    http://127.0.0.1:8030/api/mydb/users/_stream_load

# 返回结果
{
    "TxnId": 7001,
    "Label": "load_users_csv",
    "Status": "Success",
    "Message": "OK",
    "NumberTotalRows": 3,
    "NumberLoadedRows": 3,
    "NumberFilteredRows": 0,
    "NumberUnselectedRows": 0,
    "LoadBytes": 1024,
    "LoadTimeMs": 100,
    "BeginTxnTimeMs": 10,
    "StreamLoadPutTimeMs": 20,
    "ReadDataTimeMs": 50,
    "WriteDataTimeMs": 30
}
```

### 导入 JSON

```bash
# 准备 JSON 文件 users.json
cat > users.json << EOF
{"user_id": 1, "user_name": "张三", "age": 25, "city": "北京"}
{"user_id": 2, "user_name": "李四", "age": 30, "city": "上海"}
{"user_id": 3, "user_name": "王五", "age": 28, "city": "广州"}
EOF

# 导入
curl --location-trusted -u root: \
    -H "label:load_users_json" \
    -H "format:json" \
    -H "strip_outer_array:false" \
    -T users.json \
    http://127.0.0.1:8030/api/mydb/users/_stream_load

# JSON 数组格式
cat > users_array.json << EOF
[
    {"user_id": 1, "user_name": "张三", "age": 25, "city": "北京"},
    {"user_id": 2, "user_name": "李四", "age": 30, "city": "上海"}
]
EOF

curl --location-trusted -u root: \
    -H "label:load_users_json_array" \
    -H "format:json" \
    -H "strip_outer_array:true" \
    -T users_array.json \
    http://127.0.0.1:8030/api/mydb/users/_stream_load
```

### 列映射与转换

```bash
# 源文件列与表列不一致
cat > data.csv << EOF
1,张三,25,北京,2024-01-15
2,李四,30,上海,2024-01-16
EOF

# 列映射：源文件列顺序 -> 表列顺序
curl --location-trusted -u root: \
    -H "label:load_with_mapping" \
    -H "column_separator:," \
    -H "columns:user_id,user_name,age,city,create_time" \
    -T data.csv \
    http://127.0.0.1:8030/api/mydb/users/_stream_load

# 列转换：使用函数处理数据
curl --location-trusted -u root: \
    -H "label:load_with_transform" \
    -H "column_separator:," \
    -H "columns:user_id,user_name,age=cast(age as int),city,create_time=now()" \
    -T data.csv \
    http://127.0.0.1:8030/api/mydb/users/_stream_load
```

### Python 示例

```python
import requests

def stream_load(file_path, table_name, label):
    url = f"http://127.0.0.1:8030/api/mydb/{table_name}/_stream_load"
    
    headers = {
        "label": label,
        "column_separator": ",",
        "format": "csv"
    }
    
    with open(file_path, 'rb') as f:
        response = requests.put(
            url,
            headers=headers,
            auth=('root', ''),
            data=f
        )
    
    return response.json()

result = stream_load('users.csv', 'users', 'load_python_001')
print(result)
```

---

## 二、Broker Load

### 基本语法

```sql
LOAD LABEL label_name
(
    DATA INFILE("file_path")
    INTO TABLE table_name
    [PARTITION (p1, p2)]
    [COLUMNS TERMINATED BY "separator"]
    [FORMAT AS "csv|json|parquet|orc"]
    [(column_list)]
    [SET (column_mapping)]
    [WHERE predicate]
)
WITH BROKER broker_name
(
    "username" = "xxx",
    "password" = "xxx"
)
[PROPERTIES ("key"="value", ...)];
```

### 从 HDFS 导入

```sql
-- 从 HDFS 导入 CSV
LOAD LABEL load_users_20240115
(
    DATA INFILE("hdfs://namenode:8020/data/users/*.csv")
    INTO TABLE users
    COLUMNS TERMINATED BY ","
    FORMAT AS "csv"
    (user_id, user_name, age, city)
    SET (create_time = NOW())
    WHERE age >= 18
)
WITH BROKER hdfs_broker
(
    "username" = "hadoop",
    "password" = ""
)
PROPERTIES
(
    "timeout" = "3600",
    "max_filter_ratio" = "0.01"
);

-- 查看导入状态
SHOW LOAD WHERE LABEL = 'load_users_20240115';
```

### 从 S3 导入

```sql
-- 从 S3 导入
LOAD LABEL load_from_s3
(
    DATA INFILE("s3://my-bucket/data/users/*.csv")
    INTO TABLE users
    COLUMNS TERMINATED BY ","
    FORMAT AS "csv"
)
WITH BROKER s3_broker
(
    "AWS_ACCESS_KEY" = "xxx",
    "AWS_SECRET_KEY" = "xxx",
    "AWS_ENDPOINT" = "s3.amazonaws.com",
    "AWS_REGION" = "us-east-1"
)
PROPERTIES
(
    "timeout" = "3600"
);
```

### 导入 Parquet/ORC

```sql
-- 导入 Parquet 文件
LOAD LABEL load_parquet
(
    DATA INFILE("hdfs://namenode:8020/data/users.parquet")
    INTO TABLE users
    FORMAT AS "parquet"
    (user_id, user_name, age, city)
)
WITH BROKER hdfs_broker
(
    "username" = "hadoop"
);

-- 导入 ORC 文件
LOAD LABEL load_orc
(
    DATA INFILE("hdfs://namenode:8020/data/users.orc")
    INTO TABLE users
    FORMAT AS "orc"
)
WITH BROKER hdfs_broker
(
    "username" = "hadoop"
);
```

### 多表导入

```sql
-- 一次导入多个表
LOAD LABEL load_multi_tables
(
    DATA INFILE("hdfs://namenode:8020/data/users/*.csv")
    INTO TABLE users
    COLUMNS TERMINATED BY ","
    (user_id, user_name, age, city),
    
    DATA INFILE("hdfs://namenode:8020/data/orders/*.csv")
    INTO TABLE orders
    COLUMNS TERMINATED BY ","
    (order_id, user_id, amount, order_date)
)
WITH BROKER hdfs_broker
(
    "username" = "hadoop"
);
```

---

## 三、Routine Load

### 基本语法

```sql
CREATE ROUTINE LOAD job_name ON table_name
[PROPERTIES ("key"="value", ...)]
FROM KAFKA
(
    "kafka_broker_list" = "broker1:port,broker2:port",
    "kafka_topic" = "topic_name",
    "kafka_partitions" = "0,1,2",
    "property.group.id" = "group_id"
);
```

### 从 Kafka 导入 CSV

```sql
-- 创建 Routine Load 任务
CREATE ROUTINE LOAD load_users_from_kafka ON users
COLUMNS TERMINATED BY ",",
COLUMNS (user_id, user_name, age, city)
PROPERTIES
(
    "desired_concurrent_number" = "3",
    "max_batch_rows" = "100000",
    "max_batch_size" = "104857600",
    "max_error_number" = "1000"
)
FROM KAFKA
(
    "kafka_broker_list" = "kafka1:9092,kafka2:9092",
    "kafka_topic" = "user_events",
    "property.group.id" = "doris_loader"
);

-- 查看任务状态
SHOW ROUTINE LOAD FOR load_users_from_kafka;

-- 暂停任务
PAUSE ROUTINE LOAD FOR load_users_from_kafka;

-- 恢复任务
RESUME ROUTINE LOAD FOR load_users_from_kafka;

-- 停止任务
STOP ROUTINE LOAD FOR load_users_from_kafka;
```

### 从 Kafka 导入 JSON

```sql
CREATE ROUTINE LOAD load_json_from_kafka ON users
COLUMNS (user_id, user_name, age, city)
PROPERTIES
(
    "format" = "json",
    "jsonpaths" = "[\"$.user_id\",\"$.user_name\",\"$.age\",\"$.city\"]"
)
FROM KAFKA
(
    "kafka_broker_list" = "kafka1:9092",
    "kafka_topic" = "user_json",
    "property.group.id" = "doris_json_loader"
);
```

### 指定分区

```sql
CREATE ROUTINE LOAD load_to_partition ON users
COLUMNS TERMINATED BY ",",
COLUMNS (user_id, user_name, age, city, create_time),
PARTITION (p202401, p202402)
FROM KAFKA
(
    "kafka_broker_list" = "kafka1:9092",
    "kafka_topic" = "user_events",
    "property.group.id" = "doris_loader"
);
```

### 过滤与转换

```sql
CREATE ROUTINE LOAD load_with_filter ON users
COLUMNS TERMINATED BY ",",
COLUMNS (user_id, user_name, age, city, create_time = NOW()),
WHERE age >= 18
FROM KAFKA
(
    "kafka_broker_list" = "kafka1:9092",
    "kafka_topic" = "user_events",
    "property.group.id" = "doris_loader"
);
```

---

## 四、Insert 导入

### INSERT VALUES

```sql
-- 插入单条
INSERT INTO users VALUES (1, '张三', 25, '北京', NOW());

-- 插入多条
INSERT INTO users VALUES 
    (1, '张三', 25, '北京', NOW()),
    (2, '李四', 30, '上海', NOW()),
    (3, '王五', 28, '广州', NOW());

-- 指定列
INSERT INTO users (user_id, user_name, city) 
VALUES (4, '赵六', '深圳');
```

### INSERT SELECT

```sql
-- 从其他表导入
INSERT INTO users_backup 
SELECT * FROM users WHERE create_time > '2024-01-01';

-- 从查询结果导入
INSERT INTO user_summary (user_id, order_count, total_amount)
SELECT 
    user_id,
    COUNT(*) as order_count,
    SUM(amount) as total_amount
FROM orders
GROUP BY user_id;
```

### 导入 Parquet/ORC

```sql
-- 通过 Catalog 导入 Parquet
INSERT INTO users
SELECT * FROM parquet_catalog.db.users;

-- 通过 S3 导入
INSERT INTO users
SELECT * FROM s3(
    "URI" = "s3://bucket/users.parquet",
    "ACCESS_KEY" = "xxx",
    "SECRET_KEY" = "xxx"
);
```

---

## 五、Flink Doris Connector

### Maven 依赖

```xml
<dependency>
    <groupId>org.apache.doris</groupId>
    <artifactId>doris-flink-connector</artifactId>
    <version>1.0.3</version>
</dependency>
```

### Flink SQL 示例

```sql
-- 创建 Doris 表
CREATE TABLE doris_users (
    user_id BIGINT,
    user_name STRING,
    age INT,
    city STRING,
    create_time TIMESTAMP
) WITH (
    'connector' = 'doris',
    'fenodes' = '127.0.0.1:8030',
    'table.identifier' = 'mydb.users',
    'username' = 'root',
    'password' = '',
    'sink.properties.format' = 'json',
    'sink.properties.strip_outer_array' = 'true',
    'sink.enable-delete' = 'true'
);

-- 从 Kafka 写入 Doris
INSERT INTO doris_users
SELECT 
    CAST(user_id AS BIGINT),
    user_name,
    CAST(age AS INT),
    city,
    TO_TIMESTAMP(create_time) as create_time
FROM kafka_source;
```

### Flink DataStream 示例

```java
import org.apache.doris.flink.cfg.DorisOptions;
import org.apache.doris.flink.sink.DorisSink;
import org.apache.doris.flink.sink.writer.SimpleStringSerializer;

DorisOptions.Builder dorisBuilder = DorisOptions.builder()
    .setFenodes("127.0.0.1:8030")
    .setTableIdentifier("mydb.users")
    .setUsername("root")
    .setPassword("");

DorisSink<String> sink = DorisSink.<String>builder()
    .setDorisOptions(dorisBuilder.build())
    .setSerializer(new SimpleStringSerializer("json"))
    .build();

stream.sinkTo(sink);
```

---

## 六、导入最佳实践

### 1. 选择合适的导入方式

| 数据量 | 实时性 | 推荐方式 |
|--------|--------|---------|
| < 1GB | 实时 | Stream Load |
| > 1GB | 离线 | Broker Load |
| 持续流 | 实时 | Routine Load / Flink |
| CDC | 实时 | Flink CDC |

### 2. 性能优化

```bash
# Stream Load 优化
curl --location-trusted -u root: \
    -H "label:load_optimized" \
    -H "column_separator:\t" \           # 使用制表符分隔
    -H "exec_mem_limit:2147483648" \     # 增加内存限制
    -H "send_batch_parallelism:4" \      # 并行发送
    -H "load_to_single_tablet:true" \    # 单 Tablet 导入
    -T large_file.csv \
    http://127.0.0.1:8030/api/mydb/users/_stream_load
```

### 3. 错误处理

```sql
-- 查看导入错误
SHOW LOAD WARNINGS WHERE LABEL = 'load_xxx';

-- 设置最大错误率
curl --location-trusted -u root: \
    -H "label:load_with_error" \
    -H "max_filter_ratio:0.01" \         # 允许 1% 错误
    -T data.csv \
    http://127.0.0.1:8030/api/mydb/users/_stream_load
```

### 4. Label 幂等性

```bash
# 使用相同的 Label 重复导入会被拒绝
curl --location-trusted -u root: \
    -H "label:load_unique_001" \         # 唯一 Label
    -T data.csv \
    http://127.0.0.1:8030/api/mydb/users/_stream_load

# 返回：Status: "Label Already Exists"
```

---

## 下一步

- [数据导出](./07-data-export.md) - 学习数据导出
- [分区管理](./06-partition.md) - 深入学习分区设计
