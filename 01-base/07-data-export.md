# 数据导出

## 概述

Doris 提供多种数据导出方式，可以将数据导出到文件系统、对象存储或其他系统。

```
┌─────────────────────────────────────────────────────────────┐
│                    数据导出方式                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  SELECT INTO OUTFILE    查询结果导出                  │   │
│  │  ─────────────────────────────────────────────────── │   │
│  │  特点：灵活、支持多种格式、支持分区导出               │   │
│  │  格式：CSV、Parquet、ORC                              │   │
│  │  目标：本地文件、HDFS、S3                             │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  EXPORT    表数据导出                                 │   │
│  │  ─────────────────────────────────────────────────── │   │
│  │  特点：异步、大批量、支持并行导出                     │   │
│  │  格式：CSV、Parquet、ORC                              │   │
│  │  目标：HDFS、S3                                      │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  MySQL Dump    兼容 MySQL 导出                        │   │
│  │  ─────────────────────────────────────────────────── │   │
│  │  特点：MySQL 兼容、SQL 格式                           │   │
│  │  工具：mysqldump、MySQL 客户端                        │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 一、SELECT INTO OUTFILE

### 导出到本地文件

```sql
-- 导出为 CSV
SELECT * FROM users
INTO OUTFILE "file:///tmp/users_export"
FORMAT AS CSV
PROPERTIES (
    "column_separator" => ",",
    "line_delimiter" => "\n"
);

-- 导出为 CSV（带表头）
SELECT * FROM users
INTO OUTFILE "file:///tmp/users_with_header"
FORMAT AS CSV
PROPERTIES (
    "column_separator" => ",",
    "line_delimiter" => "\n",
    "with_header" => "true"
);

-- 导出为 Parquet
SELECT * FROM users
INTO OUTFILE "file:///tmp/users_parquet"
FORMAT AS PARQUET
PROPERTIES (
    "compression" => "snappy"
);

-- 导出为 ORC
SELECT * FROM users
INTO OUTFILE "file:///tmp/users_orc"
FORMAT AS ORC
PROPERTIES (
    "compression" => "zlib"
);
```

### 导出到 HDFS

```sql
-- 导出到 HDFS
SELECT * FROM users
INTO OUTFILE "hdfs://namenode:8020/export/users"
FORMAT AS PARQUET
PROPERTIES (
    "fs.defaultFS" = "hdfs://namenode:8020",
    "hadoop.username" = "hadoop",
    "compression" => "snappy"
);

-- 导出带分区
SELECT * FROM orders
WHERE order_date BETWEEN '2024-01-01' AND '2024-01-31'
INTO OUTFILE "hdfs://namenode:8020/export/orders/202401"
FORMAT AS PARQUET
PROPERTIES (
    "fs.defaultFS" = "hdfs://namenode:8020",
    "hadoop.username" = "hadoop"
);
```

### 导出到 S3

```sql
-- 导出到 S3
SELECT * FROM users
INTO OUTFILE "s3://my-bucket/export/users"
FORMAT AS PARQUET
PROPERTIES (
    "AWS_ACCESS_KEY" = "xxx",
    "AWS_SECRET_KEY" = "xxx",
    "AWS_ENDPOINT" = "s3.amazonaws.com",
    "AWS_REGION" = "us-east-1",
    "compression" => "snappy"
);

-- 导出到 MinIO
SELECT * FROM users
INTO OUTFILE "s3://my-bucket/export/users"
FORMAT AS CSV
PROPERTIES (
    "AWS_ACCESS_KEY" = "minioadmin",
    "AWS_SECRET_KEY" = "minioadmin",
    "AWS_ENDPOINT" = "http://minio:9000",
    "column_separator" => ","
);
```

### 并行导出

```sql
-- 并行导出多个文件
SELECT * FROM large_table
INTO OUTFILE "hdfs://namenode:8020/export/large_table"
FORMAT AS PARQUET
PROPERTIES (
    "parallel" => "true",
    "num_threads" => "4",
    "max_file_size" => "1073741824"  -- 1GB
);

-- 结果：
-- large_table_0.parquet
-- large_table_1.parquet
-- large_table_2.parquet
-- large_table_3.parquet
```

### 条件导出

```sql
-- 导出特定分区
SELECT * FROM orders
WHERE order_date = '2024-01-15'
INTO OUTFILE "file:///tmp/orders_20240115"
FORMAT AS CSV;

-- 导出聚合结果
SELECT 
    order_date,
    COUNT(*) as order_count,
    SUM(amount) as total_amount
FROM orders
GROUP BY order_date
INTO OUTFILE "file:///tmp/daily_summary"
FORMAT AS CSV
PROPERTIES (
    "with_header" => "true"
);
```

---

## 二、EXPORT 命令

### 基本语法

```sql
EXPORT TABLE table_name [PARTITION (p1, p2)]
TO "export_path"
PROPERTIES ("key"="value")
WITH BROKER broker_name
(
    "username" = "xxx",
    "password" = "xxx"
);
```

### 导出到 HDFS

```sql
-- 导出整张表
EXPORT TABLE users
TO "hdfs://namenode:8020/export/users"
PROPERTIES (
    "format" = "parquet",
    "compression" = "snappy",
    "parallel" = "4"
)
WITH BROKER hdfs_broker
(
    "username" = "hadoop"
);

-- 导出指定分区
EXPORT TABLE orders PARTITION (p202401, p202402)
TO "hdfs://namenode:8020/export/orders"
PROPERTIES (
    "format" = "csv",
    "column_separator" => ","
)
WITH BROKER hdfs_broker
(
    "username" = "hadoop"
);

-- 查看导出状态
SHOW EXPORT WHERE ID = 'export_xxx';

-- 查看所有导出任务
SHOW EXPORT;
```

### 导出到 S3

```sql
EXPORT TABLE users
TO "s3://my-bucket/export/users"
PROPERTIES (
    "format" = "parquet"
)
WITH BROKER s3_broker
(
    "AWS_ACCESS_KEY" = "xxx",
    "AWS_SECRET_KEY" = "xxx",
    "AWS_ENDPOINT" = "s3.amazonaws.com"
);
```

### 导出属性

```sql
EXPORT TABLE large_table
TO "hdfs://namenode:8020/export/large_table"
PROPERTIES (
    "format" = "parquet",              -- 格式
    "compression" = "snappy",          -- 压缩
    "parallel" = "8",                  -- 并行度
    "max_file_size" = "1073741824",    -- 单文件最大 1GB
    "column_separator" => ",",         -- CSV 分隔符
    "line_delimiter" => "\n"           -- 行分隔符
)
WITH BROKER hdfs_broker
(
    "username" = "hadoop"
);
```

---

## 三、MySQL Dump 导出

### 使用 mysqldump

```bash
# 导出数据库结构
mysqldump -h 127.0.0.1 -P 9030 -u root --no-data mydb > schema.sql

# 导出数据
mysqldump -h 127.0.0.1 -P 9030 -u root --no-create-info mydb users > users_data.sql

# 导出结构和数据
mysqldump -h 127.0.0.1 -P 9030 -u root mydb > mydb_full.sql

# 导出单个表
mysqldump -h 127.0.0.1 -P 9030 -u root mydb users > users.sql
```

### 使用 MySQL 客户端

```bash
# 导出查询结果
mysql -h 127.0.0.1 -P 9030 -u root -e "
SELECT * FROM users
" mydb > users.csv

# 导出为 CSV 格式
mysql -h 127.0.0.1 -P 9030 -u root --batch --silent -e "
SELECT * FROM users
" mydb | sed 's/\t/,/g' > users.csv

# 导出带表头的 CSV
mysql -h 127.0.0.1 -P 9030 -u root --batch -e "
SELECT * FROM users
" mydb | sed 's/\t/,/g' > users.csv
```

---

## 四、使用 Catalog 导出

### 导出到 Iceberg

```sql
-- 创建 Iceberg Catalog
CREATE CATALOG iceberg_catalog PROPERTIES (
    "type" = "iceberg",
    "iceberg.catalog.type" = "hadoop",
    "warehouse" = "hdfs://namenode:8020/warehouse"
);

-- 导出到 Iceberg
INSERT INTO iceberg_catalog.db.users
SELECT * FROM users;
```

### 导出到 Hive

```sql
-- 创建 Hive Catalog
CREATE CATALOG hive_catalog PROPERTIES (
    "type" = "hms",
    "hive.metastore.uris" = "thrift://metastore:9083"
);

-- 导出到 Hive
INSERT INTO hive_catalog.db.users
SELECT * FROM users;
```

---

## 五、Python 导出示例

### 使用 MySQL Connector

```python
import mysql.connector
import csv

def export_to_csv(host, port, user, database, table, output_file):
    conn = mysql.connector.connect(
        host=host,
        port=port,
        user=user,
        database=database
    )
    
    cursor = conn.cursor()
    cursor.execute(f"SELECT * FROM {table}")
    
    with open(output_file, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow([desc[0] for desc in cursor.description])
        writer.writerows(cursor)
    
    cursor.close()
    conn.close()

export_to_csv('127.0.0.1', 9030, 'root', 'mydb', 'users', 'users.csv')
```

### 使用 Stream Load 导出

```python
import requests

def export_query(query, output_file):
    url = f"http://127.0.0.1:8030/api/_query"
    
    response = requests.post(
        url,
        auth=('root', ''),
        headers={'Content-Type': 'application/json'},
        json={'query': query}
    )
    
    with open(output_file, 'w') as f:
        f.write(response.text)

export_query('SELECT * FROM users', 'users.json')
```

---

## 六、导出最佳实践

### 1. 选择合适的格式

| 格式 | 优点 | 缺点 | 适用场景 |
|------|------|------|---------|
| CSV | 通用、可读 | 无压缩、无类型 | 数据交换、人工查看 |
| Parquet | 高压缩、列存 | 需要工具读取 | 大数据分析 |
| ORC | 高压缩、列存 | Hive 生态 | Hive 兼容 |

### 2. 性能优化

```sql
-- 并行导出
SELECT * FROM large_table
INTO OUTFILE "hdfs://namenode/export/large_table"
FORMAT AS PARQUET
PROPERTIES (
    "parallel" => "true",
    "num_threads" => "8"
);

-- 限制单文件大小
EXPORT TABLE large_table
TO "hdfs://namenode/export/large_table"
PROPERTIES (
    "max_file_size" = "1073741824"  -- 1GB
)
WITH BROKER hdfs_broker;
```

### 3. 增量导出

```sql
-- 按时间增量导出
SELECT * FROM orders
WHERE update_time > '${last_export_time}'
INTO OUTFILE "hdfs://namenode/export/orders_incremental"
FORMAT AS PARQUET;

-- 按分区增量导出
EXPORT TABLE orders PARTITION (p202401)
TO "hdfs://namenode/export/orders/p202401"
WITH BROKER hdfs_broker;
```

### 4. 数据验证

```sql
-- 导出前统计
SELECT COUNT(*) as total_rows FROM users;

-- 导出后验证
-- 检查文件行数是否匹配
```

---

## 下一步

- [分区管理](./06-partition.md) - 深入学习分区设计
- [索引管理](./07-index.md) - 学习索引优化
