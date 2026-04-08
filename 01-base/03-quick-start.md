# 快速上手

## 10 分钟完成你的第一次 Doris 操作

本教程将带你完成：
1. 连接 Doris
2. 创建数据库和表
3. 导入数据
4. 查询数据
5. 简单分析

---

## 第一步：连接 Doris

### 使用 MySQL 客户端

```bash
# 连接 Doris
mysql -h 127.0.0.1 -P 9030 -u root

# 欢迎信息
Welcome to the MySQL monitor.
Commands end with ; or \g.
Your MySQL connection id is 1
Server version: 5.7.99 Doris version 2.0.3

mysql>
```

### 查看集群状态

```sql
-- 查看 FE 节点
SHOW FRONTENDS\G

-- 查看 BE 节点
SHOW BACKENDS\G

-- 输出示例
*************************** 1. row ***************************
         Name: 192.168.1.10_9010_1704067200000
           IP: 192.168.1.10
    HostName: doris-fe1
       Port: 9010
     HttpPort: 8030
        Role: LEADER
       Alive: true
```

---

## 第二步：创建数据库和表

### 创建数据库

```sql
-- 创建电商分析数据库
CREATE DATABASE ecommerce;

-- 使用数据库
USE ecommerce;
```

### 创建用户表

```sql
-- 创建用户表
CREATE TABLE users (
    user_id BIGINT COMMENT '用户ID',
    user_name VARCHAR(100) COMMENT '用户名',
    age INT COMMENT '年龄',
    gender VARCHAR(10) COMMENT '性别',
    city VARCHAR(50) COMMENT '城市',
    register_date DATE COMMENT '注册日期'
)
DUPLICATE KEY(user_id)
COMMENT '用户表'
DISTRIBUTED BY HASH(user_id) BUCKETS 10
PROPERTIES (
    "replication_num" = "1"
);
```

### 创建订单表

```sql
-- 创建订单表
CREATE TABLE orders (
    order_id BIGINT COMMENT '订单ID',
    user_id BIGINT COMMENT '用户ID',
    product_id BIGINT COMMENT '商品ID',
    product_name VARCHAR(200) COMMENT '商品名称',
    category VARCHAR(50) COMMENT '商品类别',
    amount DECIMAL(10, 2) COMMENT '订单金额',
    quantity INT COMMENT '购买数量',
    order_time DATETIME COMMENT '下单时间',
    order_date DATE COMMENT '下单日期'
)
DUPLICATE KEY(order_id)
COMMENT '订单表'
PARTITION BY RANGE(order_date) (
    PARTITION p202401 VALUES LESS THAN ('2024-02-01'),
    PARTITION p202402 VALUES LESS THAN ('2024-03-01'),
    PARTITION p202403 VALUES LESS THAN ('2024-04-01')
)
DISTRIBUTED BY HASH(order_id) BUCKETS 10
PROPERTIES (
    "replication_num" = "1"
);
```

### 查看表结构

```sql
-- 查看所有表
SHOW TABLES;

-- 查看表结构
DESC users;

-- 查看建表语句
SHOW CREATE TABLE orders\G
```

---

## 第三步：导入数据

### 方式一：INSERT 语句

```sql
-- 插入用户数据
INSERT INTO users VALUES
    (1, '张三', 25, '男', '北京', '2023-01-15'),
    (2, '李四', 30, '女', '上海', '2023-02-20'),
    (3, '王五', 28, '男', '广州', '2023-03-10'),
    (4, '赵六', 35, '女', '深圳', '2023-04-05'),
    (5, '钱七', 22, '男', '杭州', '2023-05-12');

-- 插入订单数据
INSERT INTO orders VALUES
    (1001, 1, 101, 'iPhone 15', '手机', 6999.00, 1, '2024-01-15 10:30:00', '2024-01-15'),
    (1002, 1, 102, 'MacBook Pro', '电脑', 14999.00, 1, '2024-01-20 14:20:00', '2024-01-20'),
    (1003, 2, 103, 'iPad Air', '平板', 4799.00, 2, '2024-01-25 09:15:00', '2024-01-25'),
    (1004, 3, 101, 'iPhone 15', '手机', 6999.00, 1, '2024-02-01 16:45:00', '2024-02-01'),
    (1005, 4, 104, 'AirPods Pro', '耳机', 1899.00, 3, '2024-02-10 11:30:00', '2024-02-10'),
    (1006, 5, 105, 'Apple Watch', '手表', 2999.00, 1, '2024-02-15 13:20:00', '2024-02-15'),
    (1007, 1, 106, 'Magic Keyboard', '配件', 999.00, 1, '2024-02-20 15:00:00', '2024-02-20'),
    (1008, 2, 102, 'MacBook Pro', '电脑', 14999.00, 1, '2024-03-01 10:10:00', '2024-03-01'),
    (1009, 3, 107, 'HomePod', '音箱', 2299.00, 2, '2024-03-05 17:30:00', '2024-03-05'),
    (1010, 4, 103, 'iPad Air', '平板', 4799.00, 1, '2024-03-10 12:45:00', '2024-03-10');
```

### 方式二：Stream Load (推荐)

```bash
# 准备数据文件 users.csv
cat > users.csv << EOF
6,孙八,27,女,成都,2023-06-01
7,周九,32,男,武汉,2023-07-15
8,吴十,29,女,南京,2023-08-20
EOF

# 使用 Stream Load 导入
curl --location-trusted -u root: \
    -H "label:load_users_001" \
    -H "column_separator:," \
    -T users.csv \
    http://127.0.0.1:8030/api/ecommerce/users/_stream_load

# 返回结果
{
    "TxnId": 1,
    "Label": "load_users_001",
    "Status": "Success",
    "Message": "OK",
    "NumberTotalRows": 3,
    "NumberLoadedRows": 3,
    "NumberFilteredRows": 0,
    "NumberUnselectedRows": 0,
    "LoadBytes": 1024,
    "LoadTimeMs": 100
}
```

---

## 第四步：查询数据

### 基础查询

```sql
-- 查询所有用户
SELECT * FROM users;

-- 查询特定用户
SELECT * FROM users WHERE user_id = 1;

-- 查询北京用户
SELECT user_id, user_name, age 
FROM users 
WHERE city = '北京';

-- 排序查询
SELECT * FROM users ORDER BY age DESC;

-- 分页查询
SELECT * FROM users LIMIT 5 OFFSET 0;
```

### 聚合查询

```sql
-- 统计用户数量
SELECT COUNT(*) as total_users FROM users;

-- 按城市统计用户数
SELECT city, COUNT(*) as user_count
FROM users
GROUP BY city
ORDER BY user_count DESC;

-- 统计订单总金额
SELECT 
    COUNT(*) as order_count,
    SUM(amount) as total_amount,
    AVG(amount) as avg_amount,
    MAX(amount) as max_amount,
    MIN(amount) as min_amount
FROM orders;

-- 按日期统计销售
SELECT 
    order_date,
    COUNT(*) as order_count,
    SUM(amount) as total_amount
FROM orders
GROUP BY order_date
ORDER BY order_date;
```

### 关联查询

```sql
-- 查询用户及其订单
SELECT 
    u.user_name,
    u.city,
    o.order_id,
    o.product_name,
    o.amount,
    o.order_date
FROM users u
JOIN orders o ON u.user_id = o.user_id
ORDER BY u.user_id, o.order_date;

-- 统计每个用户的订单金额
SELECT 
    u.user_name,
    u.city,
    COUNT(o.order_id) as order_count,
    SUM(o.amount) as total_amount
FROM users u
LEFT JOIN orders o ON u.user_id = o.user_id
GROUP BY u.user_id, u.user_name, u.city
ORDER BY total_amount DESC;
```

---

## 第五步：数据分析

### 销售分析

```sql
-- 按商品类别统计销售
SELECT 
    category,
    COUNT(*) as order_count,
    SUM(quantity) as total_quantity,
    SUM(amount) as total_amount
FROM orders
GROUP BY category
ORDER BY total_amount DESC;

-- 输出
+----------+-------------+----------------+--------------+
| category | order_count | total_quantity | total_amount |
+----------+-------------+----------------+--------------+
| 电脑     |           2 |              2 |     29998.00 |
| 手机     |           2 |              2 |     13998.00 |
| 平板     |           2 |              3 |      9598.00 |
| 耳机     |           1 |              3 |      1899.00 |
| 手表     |           1 |              1 |      2999.00 |
| 音箱     |           1 |              2 |      2299.00 |
| 配件     |           1 |              1 |       999.00 |
+----------+-------------+----------------+--------------+
```

### 用户分析

```sql
-- 用户消费排名
SELECT 
    u.user_name,
    u.city,
    u.age,
    COUNT(o.order_id) as order_count,
    SUM(o.amount) as total_amount
FROM users u
JOIN orders o ON u.user_id = o.user_id
GROUP BY u.user_id, u.user_name, u.city, u.age
ORDER BY total_amount DESC
LIMIT 5;

-- 月度销售趋势
SELECT 
    DATE_FORMAT(order_date, '%Y-%m') as month,
    COUNT(*) as order_count,
    SUM(amount) as total_amount
FROM orders
GROUP BY DATE_FORMAT(order_date, '%Y-%m')
ORDER BY month;
```

### 高级分析

```sql
-- RFM 分析 (最近购买时间、购买频率、消费金额)
SELECT 
    u.user_name,
    DATEDIFF(CURRENT_DATE, MAX(o.order_date)) as recency,
    COUNT(o.order_id) as frequency,
    SUM(o.amount) as monetary
FROM users u
JOIN orders o ON u.user_id = o.user_id
GROUP BY u.user_id, u.user_name
ORDER BY monetary DESC;

-- 商品销售排行
SELECT 
    product_name,
    COUNT(*) as order_count,
    SUM(quantity) as total_quantity,
    SUM(amount) as total_amount
FROM orders
GROUP BY product_name
ORDER BY total_amount DESC
LIMIT 10;
```

---

## 进阶操作

### 添加分区

```sql
-- 添加新分区
ALTER TABLE orders ADD PARTITION p202404 
VALUES LESS THAN ('2024-05-01');

-- 查看分区
SHOW PARTITIONS FROM orders;
```

### 创建物化视图

```sql
-- 创建每日销售汇总物化视图
CREATE MATERIALIZED VIEW mv_daily_sales
AS SELECT
    order_date,
    category,
    COUNT(*) as order_count,
    SUM(amount) as total_amount
FROM orders
GROUP BY order_date, category;

-- 查询自动使用物化视图
SELECT 
    order_date,
    SUM(total_amount)
FROM mv_daily_sales
GROUP BY order_date;
```

### 导出数据

```sql
-- 导出查询结果
SELECT * FROM users
INTO OUTFILE "file:///tmp/users_export"
FORMAT AS CSV
PROPERTIES (
    "column_separator" => ","
);

-- 导出为 CSV
SELECT * FROM orders WHERE order_date >= '2024-02-01'
INTO OUTFILE "file:///tmp/orders_feb.csv"
FORMAT AS CSV;
```

---

## 清理资源

```sql
-- 删除测试数据
DROP DATABASE IF EXISTS ecommerce;

-- 或者只删除表
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS users;
```

---

## 小结

恭喜你完成了 Doris 的快速上手！你已经学会了：

- [x] 连接 Doris 数据库
- [x] 创建数据库和表
- [x] 使用 INSERT 和 Stream Load 导入数据
- [x] 执行基础 SQL 查询
- [x] 进行数据聚合和关联分析
- [x] 创建分区和物化视图
- [x] 导出数据

---

## 下一步

- [SQL 基础](./04-sql-basics.md) - 深入学习 SQL 语法
- [数据模型](./05-data-model.md) - 理解三种数据模型
- [数据导入](./06-data-import.md) - 掌握更多导入方式
