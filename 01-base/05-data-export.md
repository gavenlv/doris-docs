# 数据导出

## SELECT INTO OUTFILE

SELECT INTO OUTFILE 是 Doris 提供的一种简单导出方式，将查询结果导出到本地文件或远程存储。

### 基本语法

```sql
SELECT ...
INTO OUTFILE "file_path"
[FORMAT AS <format>]
[PROPERTIES ("key" = "value", ...)];
```

### 导出为 CSV

```sql
-- 基本导出
SELECT * FROM users
INTO OUTFILE "/tmp/users.csv"
FORMAT AS CSV
PROPERTIES (
    "delimiter" = ",",
    "line_delimiter" = "\n"
);

-- 指定列导出
SELECT user_id, user_name, age, city
FROM users
WHERE age > 25
INTO OUTFILE "/tmp/users_25plus.csv"
FORMAT AS CSV
PROPERTIES (
    "delimiter" = ",",
    "line_delimiter" = "\n",
    "header" = "true"
);

-- 导出带表头
SELECT * FROM users
INTO OUTFILE "/tmp/users_with_header.csv"
FORMAT AS CSV
PROPERTIES (
    "delimiter" = ",",
    "line_delimiter" = "\n",
    "header" = "true"
);
```

### 导出为 JSON

```sql
-- 基本导出
SELECT * FROM users
INTO OUTFILE "/tmp/users.json"
FORMAT AS JSON
PROPERTIES (
    "line_delimiter" = "\n"
);

-- 导出为 JSON 数组
SELECT * FROM users
INTO OUTFILE "/tmp/users_array.json"
FORMAT AS JSON
PROPERTIES (
    "line_delimiter" = "\n",
    "array_delimited" = "true"
);
```

### 导出到 HDFS

```sql
-- 导出到 HDFS
SELECT * FROM users
INTO OUTFILE "hdfs://namenode:8020/export/users.csv"
FORMAT AS CSV
PROPERTIES (
    "delimiter" = ",",
    "line_delimiter" = "\n"
)
WITH BROKER hdfs_broker
(
    "username" = "hdfs",
    "password" = "password"
);
```

### 导出到 S3

```sql
-- 导出到 S3
SELECT * FROM users
INTO OUTFILE "s3://bucket/export/users.csv"
FORMAT AS CSV
PROPERTIES (
    "delimiter" = ",",
    "line_delimiter" = "\n"
)
WITH BROKER s3_broker
(
    "aws_access_key" = "your_access_key",
    "aws_secret_key" = "your_secret_key",
    "aws_region" = "us-west-2"
);
```

### 导出到 OSS

```sql
-- 导出到 OSS
SELECT * FROM users
INTO OUTFILE "oss://bucket/export/users.csv"
FORMAT AS CSV
PROPERTIES (
    "delimiter" = ",",
    "line_delimiter" = "\n"
)
WITH BROKER oss_broker
(
    "oss_endpoint" = "oss-cn-hangzhou.aliyuncs.com",
    "access_key_id" = "your_access_key_id",
    "access_key_secret" = "your_access_key_secret"
);
```

### 导出参数说明

| 参数 | 说明 | 示例 |
|------|------|------|
| delimiter | 列分隔符 | , \| \| \t |
| line_delimiter | 行分隔符 | \n |
| header | 是否包含表头 | true, false |
| max_file_size | 单文件最大大小 | 10GB |
| compress_type | 压缩类型 | GZIP, ZSTD, SNAPPY |

## 使用 MySQL 客户端导出

### 导出为 CSV

```bash
# 基本导出
mysql -h 127.0.0.1 -P 9030 -u root -e "SELECT * FROM users" > users.csv

# 导出指定列
mysql -h 127.0.0.1 -P 9030 -u root -e "SELECT user_id, user_name, age FROM users" > users_simple.csv

# 导出带表头
mysql -h 127.0.0.1 -P 9030 -u root -e "SELECT * FROM users" --batch --skip-column-names > users.csv
```

### 导出为 SQL

```bash
# 导出建表语句
mysql -h 127.0.0.1 -P 9030 -u root -e "SHOW CREATE TABLE users" > users_schema.sql

# 导出数据和建表语句
mysqldump -h 127.0.0.1 -P 9030 -u root users > users_backup.sql
```

## 使用 curl 导出

### 通过 HTTP API 导出

```bash
# 基本导出
curl -u root: \
    -H "Content-Type: application/json" \
    -d '{"stmt":"SELECT * FROM users"}' \
    http://127.0.0.1:8030/api/my_database/_export

# 导出为 CSV
curl -u root: \
    -H "Content-Type: application/json" \
    -d '{
        "stmt":"SELECT * FROM users",
        "format":"csv",
        "properties":{"delimiter":","}
    }' \
    http://127.0.0.1:8030/api/my_database/_export

# 导出为 JSON
curl -u root: \
    -H "Content-Type: application/json" \
    -d '{
        "stmt":"SELECT * FROM users",
        "format":"json"
    }' \
    http://127.0.0.1:8030/api/my_database/_export
```

## 使用程序导出

### Python 导出

```python
import pymysql
import csv

# 连接 Doris
conn = pymysql.connect(
    host='127.0.0.1',
    port=9030,
    user='root',
    password='',
    database='my_database'
)

try:
    with conn.cursor() as cursor:
        # 执行查询
        cursor.execute("SELECT * FROM users")
        results = cursor.fetchall()
        
        # 获取列名
        columns = [desc[0] for desc in cursor.description]
        
        # 导出为 CSV
        with open('users.csv', 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(columns)
            writer.writerows(results)
            
finally:
    conn.close()
```

### Java 导出

```java
import java.io.FileWriter;
import java.io.IOException;
import java.sql.*;

public class DorisExport {
    public static void main(String[] args) {
        String url = "jdbc:mysql://127.0.0.1:9030/my_database";
        String user = "root";
        String password = "";

        try (Connection conn = DriverManager.getConnection(url, user, password);
             Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery("SELECT * FROM users");
             FileWriter writer = new FileWriter("users.csv")) {

            ResultSetMetaData metaData = rs.getMetaData();
            int columnCount = metaData.getColumnCount();

            // 写入表头
            for (int i = 1; i <= columnCount; i++) {
                writer.append(metaData.getColumnName(i));
                if (i < columnCount) writer.append(",");
            }
            writer.append("\n");

            // 写入数据
            while (rs.next()) {
                for (int i = 1; i <= columnCount; i++) {
                    writer.append(rs.getString(i));
                    if (i < columnCount) writer.append(",");
                }
                writer.append("\n");
            }

        } catch (SQLException | IOException e) {
            e.printStackTrace();
        }
    }
}
```

### Node.js 导出

```javascript
const mysql = require('mysql2/promise');
const fs = require('fs');

async function exportData() {
    const connection = await mysql.createConnection({
        host: '127.0.0.1',
        port: 9030,
        user: 'root',
        password: '',
        database: 'my_database'
    });

    try {
        const [rows] = await connection.execute('SELECT * FROM users');
        
        // 转换为 CSV
        const columns = Object.keys(rows[0]);
        const csvContent = [
            columns.join(','),
            ...rows.map(row => columns.map(col => row[col]).join(','))
        ].join('\n');

        // 写入文件
        fs.writeFileSync('users.csv', csvContent);
        console.log('Export completed!');
    } finally {
        await connection.end();
    }
}

exportData();
```

## 导出任务管理

### 查看导出任务

```sql
-- 查看所有导出任务
SHOW EXPORT;

-- 查看指定导出任务
SHOW EXPORT WHERE label = 'export_label';
```

### 取消导出任务

```sql
-- 取消导出任务
CANCEL EXPORT FROM my_database WHERE label = 'export_label';
```

## 导出最佳实践

### 1. 选择合适的导出方式

| 导出方式 | 适用场景 | 数据量 | 复杂度 |
|---------|---------|--------|--------|
| SELECT INTO OUTFILE | 简单查询导出 | 中等 | 低 |
| MySQL 客户端 | 命令行导出 | 小 | 低 |
| HTTP API | 程序化导出 | 中等 | 中 |
| 程序导出 | 自定义导出 | 大 | 高 |

### 2. 优化导出性能

```sql
-- 分批导出
SELECT * FROM users WHERE user_id BETWEEN 1 AND 10000
INTO OUTFILE "/tmp/users_1.csv"
FORMAT AS CSV;

SELECT * FROM users WHERE user_id BETWEEN 10001 AND 20000
INTO OUTFILE "/tmp/users_2.csv"
FORMAT AS CSV;
```

### 3. 压缩导出

```sql
-- 导出并压缩
SELECT * FROM users
INTO OUTFILE "/tmp/users.csv.gz"
FORMAT AS CSV
PROPERTIES (
    "delimiter" = ",",
    "line_delimiter" = "\n",
    "compress_type" = "GZIP"
);
```

## 常见问题

### 导出文件过大

```sql
-- 设置单文件最大大小
SELECT * FROM users
INTO OUTFILE "/tmp/users.csv"
FORMAT AS CSV
PROPERTIES (
    "delimiter" = ",",
    "line_delimiter" = "\n",
    "max_file_size" = "10GB"
);
```

### 导出中文乱码

```bash
# 使用 UTF-8 编码导出
mysql -h 127.0.0.1 -P 9030 -u root --default-character-set=utf8mb4 \
    -e "SELECT * FROM users" > users.csv
```

### 导出权限问题

```sql
-- 确保有导出权限
GRANT SELECT_PRIV ON my_database.users TO 'user'@'%';
```

## 下一步

- [分区管理](./06-partition.md) - 学习如何管理分区表
