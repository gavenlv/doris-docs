# 连接 Doris

## 使用 MySQL 客户端连接

### 基本连接

```bash
mysql -h <FE_HOST> -P <FE_PORT> -u <USER> -p
```

### 示例

```bash
# 连接到本地 Doris
mysql -h 127.0.0.1 -P 9030 -u root

# 连接到远程 Doris
mysql -h 192.168.1.100 -P 9030 -u admin -p

# 使用密码连接
mysql -h 127.0.0.1 -P 9030 -u root -p'your_password'
```

## 使用 Docker 连接

```bash
# 进入 FE 容器
docker exec -it doris-fe bash

# 在容器内连接
mysql -h 127.0.0.1 -P 9030 -u root

# 直接执行 SQL
docker exec -it doris-fe mysql -h 127.0.0.1 -P 9030 -u root -e "SHOW DATABASES;"
```

## 使用 JDBC 连接

```java
import java.sql.*;

public class DorisConnection {
    public static void main(String[] args) {
        String url = "jdbc:mysql://127.0.0.1:9030/default";
        String user = "root";
        String password = "";

        try {
            Connection conn = DriverManager.getConnection(url, user, password);
            Statement stmt = conn.createStatement();
            ResultSet rs = stmt.executeQuery("SHOW DATABASES;");

            while (rs.next()) {
                System.out.println(rs.getString(1));
            }

            rs.close();
            stmt.close();
            conn.close();
        } catch (SQLException e) {
            e.printStackTrace();
        }
    }
}
```

## 使用 Python 连接

```python
import pymysql

# 连接配置
config = {
    'host': '127.0.0.1',
    'port': 9030,
    'user': 'root',
    'password': '',
    'database': 'default'
}

# 建立连接
conn = pymysql.connect(**config)

try:
    with conn.cursor() as cursor:
        # 执行查询
        cursor.execute("SHOW DATABASES;")
        result = cursor.fetchall()
        
        for row in result:
            print(row[0])
finally:
    conn.close()
```

## 使用 Node.js 连接

```javascript
const mysql = require('mysql2/promise');

async function connectToDoris() {
    const connection = await mysql.createConnection({
        host: '127.0.0.1',
        port: 9030,
        user: 'root',
        password: ''
    });

    try {
        const [rows] = await connection.execute('SHOW DATABASES;');
        console.log(rows);
    } finally {
        await connection.end();
    }
}

connectToDoris();
```

## 连接参数说明

| 参数 | 说明 | 默认值 |
|------|------|--------|
| -h | FE 主机地址 | 127.0.0.1 |
| -P | FE 查询端口 | 9030 |
| -u | 用户名 | root |
| -p | 密码 | 空 |
| -D | 数据库名 | default |

## 查看连接信息

```sql
-- 查看当前连接的用户
SELECT USER();

-- 查看当前数据库
SELECT DATABASE();

-- 查看连接的 FE 节点
SHOW FRONTENDS;

-- 查看所有 BE 节点
SHOW BACKENDS;
```

## 常见问题

### 连接被拒绝

```bash
# 检查 FE 是否正常运行
docker ps | grep doris-fe

# 检查 FE 日志
docker logs doris-fe
```

### 权限不足

```sql
-- 创建新用户
CREATE USER 'admin'@'%' IDENTIFIED BY 'password';

-- 授予权限
GRANT ALL PRIVILEGES ON *.* TO 'admin'@'%';

-- 刷新权限
FLUSH PRIVILEGES;
```

### 网络不通

```bash
# 检查端口是否开放
telnet 127.0.0.1 9030

# 检查防火墙
# Linux
sudo ufw status

# Windows
netsh advfirewall show allprofiles state
```

## 连接池配置

### Java (HikariCP)

```java
HikariConfig config = new HikariConfig();
config.setJdbcUrl("jdbc:mysql://127.0.0.1:9030/default");
config.setUsername("root");
config.setPassword("");
config.setMaximumPoolSize(10);
config.setMinimumIdle(2);
config.setConnectionTimeout(30000);

HikariDataSource dataSource = new HikariDataSource(config);
```

### Python (SQLAlchemy)

```python
from sqlalchemy import create_engine

engine = create_engine(
    'mysql+pymysql://root:@127.0.0.1:9030/default',
    pool_size=5,
    max_overflow=10,
    pool_timeout=30
)
```

## 下一步

- [数据库和表管理](./02-database-table.md) - 学习如何创建和管理数据库、表
