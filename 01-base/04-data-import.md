# 数据导入

## Stream Load

Stream Load 是 Doris 提供的一种同步导入方式，用户通过 HTTP 协议发送请求将本地文件或数据流导入到 Doris。

### 基本语法

```bash
curl --location-trusted -u <user>:<password> \
    -H "label:<label>" \
    -H "format:<format>" \
    -T <file_path> \
    http://<fe_host>:<fe_http_port>/api/<database>/<table>/_stream_load
```

### 导入 CSV 文件

```bash
# 基本导入
curl --location-trusted -u root: \
    -H "label:label_20240101" \
    -H "column_separator:," \
    -T users.csv \
    http://127.0.0.1:8030/api/my_database/users/_stream_load

# 指定列映射
curl --location-trusted -u root: \
    -H "label:label_20240101" \
    -H "column_separator:," \
    -H "columns:user_id,user_name,age,city,register_date" \
    -T users.csv \
    http://127.0.0.1:8030/api/my_database/users/_stream_load

# 跳过表头
curl --location-trusted -u root: \
    -H "label:label_20240101" \
    -H "column_separator:," \
    -H "skip_header:1" \
    -T users.csv \
    http://127.0.0.1:8030/api/my_database/users/_stream_load
```

### 导入 JSON 文件

```bash
# 基本导入
curl --location-trusted -u root: \
    -H "label:label_20240101" \
    -H "format:json" \
    -T users.json \
    http://127.0.0.1:8030/api/my_database/users/_stream_load

# 导入 JSON 数组
curl --location-trusted -u root: \
    -H "label:label_20240101" \
    -H "format:json" \
    -H "strip_outer_array:true" \
    -T users_array.json \
    http://127.0.0.1:8030/api/my_database/users/_stream_load

# 指定 JSON 路径
curl --location-trusted -u root: \
    -H "label:label_20240101" \
    -H "format:json" \
    -H "json_root:$.data" \
    -T users_nested.json \
    http://127.0.0.1:8030/api/my_database/users/_stream_load
```

### 导入压缩文件

```bash
# 导入 GZIP 压缩文件
curl --location-trusted -u root: \
    -H "label:label_20240101" \
    -H "column_separator:," \
    -H "compress_type:GZIP" \
    -T users.csv.gz \
    http://127.0.0.1:8030/api/my_database/users/_stream_load

# 导入 ZIP 压缩文件
curl --location-trusted -u root: \
    -H "label:label_20240101" \
    -H "column_separator:," \
    -H "compress_type:ZIP" \
    -T users.csv.zip \
    http://127.0.0.1:8030/api/my_database/users/_stream_load
```

### Stream Load 参数

| 参数 | 说明 | 示例 |
|------|------|------|
| label | 导入任务的唯一标识 | label_20240101 |
| format | 数据格式 | json, csv |
| column_separator | 列分隔符 | , \| \t |
| line_delimiter | 行分隔符 | \n |
| columns | 列映射 | user_id,user_name,age |
| skip_header | 跳过表头行数 | 1 |
| max_filter_ratio | 最大容忍错误率 | 0.1 |
| timeout | 超时时间（秒） | 600 |
| strict_mode | 严格模式 | true |

## Broker Load

Broker Load 通过 Broker 进程访问外部存储系统（如 HDFS、S3、OSS）的数据。

### 基本语法

```sql
LOAD LABEL <label>
(
    DATA INFILE ("<file_path>", ...)
    INTO TABLE <table>
    [PARTITION (<partition>, ...)]
    [COLUMNS TERMINATED BY '<separator>']
    [FORMAT AS <format>]
    [(<columns>)]
)
WITH BROKER <broker_name>
(
    "key1" = "value1",
    "key2" = "value2"
)
[PROPERTIES ("key" = "value", ...)];
```

### 从 HDFS 导入

```sql
-- 创建 Broker
CREATE BROKER hdfs_broker
PROPERTIES (
    "username" = "hdfs",
    "password" = "password"
);

-- 导入数据
LOAD LABEL label_hdfs_20240101
(
    DATA INFILE ("hdfs://namenode:8020/data/users.csv")
    INTO TABLE users
    COLUMNS TERMINATED BY ','
    FORMAT AS 'CSV'
    (user_id, user_name, age, city, register_date)
)
WITH BROKER hdfs_broker
(
    "nameservice" = "mycluster"
)
PROPERTIES (
    "timeout" = "3600"
);
```

### 从 S3 导入

```sql
LOAD LABEL label_s3_20240101
(
    DATA INFILE ("s3://bucket/path/users.csv")
    INTO TABLE users
    COLUMNS TERMINATED BY ','
    FORMAT AS 'CSV'
    (user_id, user_name, age, city, register_date)
)
WITH BROKER s3_broker
(
    "aws_access_key" = "your_access_key",
    "aws_secret_key" = "your_secret_key",
    "aws_region" = "us-west-2"
)
PROPERTIES (
    "timeout" = "3600"
);
```

### 从 OSS 导入

```sql
LOAD LABEL label_oss_20240101
(
    DATA INFILE ("oss://bucket/path/users.csv")
    INTO TABLE users
    COLUMNS TERMINATED BY ','
    FORMAT AS 'CSV'
    (user_id, user_name, age, city, register_date)
)
WITH BROKER oss_broker
(
    "oss_endpoint" = "oss-cn-hangzhou.aliyuncs.com",
    "access_key_id" = "your_access_key_id",
    "access_key_secret" = "your_access_key_secret"
)
PROPERTIES (
    "timeout" = "3600"
);
```

## Routine Load

Routine Load 是一种持续导入方式，从 Kafka 等消息队列中持续消费数据。

### 基本语法

```sql
CREATE ROUTINE LOAD <database>.<job_name> ON <table>
[PROPERTIES ("key" = "value", ...)]
FROM KAFKA
(
    "kafka_broker_list" = "<broker_list>",
    "kafka_topic" = "<topic>",
    "kafka_partitions" = "<partitions>",
    "kafka_offsets" = "<offsets>"
);
```

### 从 Kafka 导入 JSON

```sql
CREATE ROUTINE LOAD my_database.kafka_users ON users
PROPERTIES (
    "format" = "json",
    "jsonpaths" = "$.user_id, $.user_name, $.age, $.city, $.register_date"
)
FROM KAFKA (
    "kafka_broker_list" = "kafka-broker1:9092,kafka-broker2:9092",
    "kafka_topic" = "users_topic",
    "kafka_partitions" = "0,1,2",
    "kafka_offsets" = "OFFSET_BEGINNING"
);
```

### 从 Kafka 导入 CSV

```sql
CREATE ROUTINE LOAD my_database.kafka_orders ON orders
PROPERTIES (
    "format" = "csv",
    "column_separator" = ",",
    "skip_header" = "1"
)
FROM KAFKA (
    "kafka_broker_list" = "kafka-broker1:9092,kafka-broker2:9092",
    "kafka_topic" = "orders_topic",
    "kafka_partitions" = "0,1,2",
    "kafka_offsets" = "OFFSET_BEGINNING"
);
```

### 管理 Routine Load

```sql
-- 查看所有 Routine Load
SHOW ROUTINE LOAD;

-- 查看指定 Routine Load
SHOW ROUTINE LOAD FOR my_database.kafka_users;

-- 暂停 Routine Load
PAUSE ROUTINE LOAD FOR my_database.kafka_users;

-- 恢复 Routine Load
RESUME ROUTINE LOAD FOR my_database.kafka_users;

-- 停止 Routine Load
STOP ROUTINE LOAD FOR my_database.kafka_users;
```

## Insert Into

### 从查询插入

```sql
-- 从其他表插入
INSERT INTO users_archive
SELECT * FROM users WHERE age > 30;

-- 插入指定列
INSERT INTO users (user_id, user_name, age)
SELECT user_id, user_name, age FROM temp_users;

-- 聚合后插入
INSERT INTO user_stats
SELECT city, COUNT(*) as user_count, AVG(age) as avg_age
FROM users
GROUP BY city;
```

### 批量插入

```sql
-- 多值插入
INSERT INTO users VALUES
    (1, 'Alice', 25, 'Beijing', '2024-01-01'),
    (2, 'Bob', 30, 'Shanghai', '2024-01-02'),
    (3, 'Charlie', 35, 'Guangzhou', '2024-01-03');
```

## Spark Load

Spark Load 通过 Spark 集群进行大规模数据导入。

### 基本语法

```sql
LOAD LABEL <label>
(
    DATA INFILE ("<file_path>", ...)
    INTO TABLE <table>
    [PARTITION (<partition>, ...)]
    [COLUMNS TERMINATED BY '<separator>']
    [FORMAT AS <format>]
    [(<columns>)]
)
WITH RESOURCE <resource_name>
[PROPERTIES ("key" = "value", ...)];
```

### 创建 Spark 资源

```sql
CREATE EXTERNAL RESOURCE "spark_resource"
PROPERTIES (
    "type" = "spark",
    "spark.master" = "yarn",
    "spark.submit.deployMode" = "cluster",
    "spark.jars" = "http://127.0.0.1:8000/doris-spark-2.3.2.jar",
    "spark.hadoop.yarn.resourcemanager.hostname" = "rm1",
    "spark.hadoop.yarn.resourcemanager.address" = "rm1:8032",
    "spark.hadoop.fs.defaultFS" = "hdfs://namenode:8020",
    "working_dir" = "hdfs://namenode:8020/tmp/doris",
    "broker" = "hdfs_broker"
);
```

### 使用 Spark Load

```sql
LOAD LABEL label_spark_20240101
(
    DATA INFILE ("hdfs://namenode:8020/data/users.csv")
    INTO TABLE users
    COLUMNS TERMINATED BY ','
    FORMAT AS 'CSV'
    (user_id, user_name, age, city, register_date)
)
WITH RESOURCE "spark_resource"
PROPERTIES (
    "timeout" = "86400"
);
```

## 导入任务管理

### 查看导入任务

```sql
-- 查看 Stream Load 任务
SHOW LOAD WHERE label = 'label_20240101';

-- 查看 Broker Load 任务
SHOW LOAD WHERE label = 'label_hdfs_20240101';

-- 查看所有导入任务
SHOW LOAD;
```

### 取消导入任务

```sql
-- 取消 Broker Load
CANCEL LOAD FROM my_database WHERE label = 'label_hdfs_20240101';
```

### 查看导入状态

```sql
-- 查看任务详情
SHOW LOAD WHERE label = 'label_20240101'\G
```

## 导入最佳实践

### 1. 选择合适的导入方式

| 导入方式 | 适用场景 | 数据量 | 实时性 |
|---------|---------|--------|--------|
| Stream Load | 小批量、实时导入 | < 10GB | 高 |
| Broker Load | 大批量、离线导入 | 10GB - 100GB | 低 |
| Routine Load | 持续导入 | 无限制 | 高 |
| Spark Load | 超大批量导入 | > 100GB | 低 |

### 2. 优化导入性能

```bash
# 增加并发
curl --location-trusted -u root: \
    -H "label:label_20240101" \
    -H "column_separator:," \
    -H "max_filter_ratio:0.1" \
    -H "timeout:600" \
    -T users.csv \
    http://127.0.0.1:8030/api/my_database/users/_stream_load?parallelism=2
```

### 3. 错误处理

```bash
# 设置最大容忍错误率
curl --location-trusted -u root: \
    -H "label:label_20240101" \
    -H "column_separator:," \
    -H "max_filter_ratio:0.1" \
    -T users.csv \
    http://127.0.0.1:8030/api/my_database/users/_stream_load
```

## 下一步

- [数据导出](./05-data-export.md) - 学习如何从 Doris 导出数据
