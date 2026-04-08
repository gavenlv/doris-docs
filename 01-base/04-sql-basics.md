# SQL 基础

## 概述

Doris 支持标准 SQL，兼容 MySQL 协议，本教程将带你掌握 Doris SQL 的核心语法。

---

## 数据定义语言 (DDL)

### 数据库操作

```sql
-- 创建数据库
CREATE DATABASE mydb;

-- 创建数据库（如果不存在）
CREATE DATABASE IF NOT EXISTS mydb;

-- 指定字符集
CREATE DATABASE mydb 
PROPERTIES ("charset" = "utf8mb4");

-- 查看所有数据库
SHOW DATABASES;

-- 查看数据库信息
SHOW CREATE DATABASE mydb;

-- 使用数据库
USE mydb;

-- 删除数据库
DROP DATABASE IF EXISTS mydb;
```

### 表操作

```sql
-- 创建表（明细模型）
CREATE TABLE users (
    user_id BIGINT COMMENT '用户ID',
    user_name VARCHAR(100) COMMENT '用户名',
    age INT COMMENT '年龄',
    city VARCHAR(50) COMMENT '城市',
    create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间'
)
DUPLICATE KEY(user_id)
COMMENT '用户表'
PARTITION BY RANGE(create_time) (
    PARTITION p202401 VALUES LESS THAN ('2024-02-01'),
    PARTITION p202402 VALUES LESS THAN ('2024-03-01')
)
DISTRIBUTED BY HASH(user_id) BUCKETS 10
PROPERTIES (
    "replication_num" = "3"
);

-- 创建表（聚合模型）
CREATE TABLE sales_summary (
    sale_date DATE COMMENT '销售日期',
    product_id BIGINT COMMENT '商品ID',
    sale_count INT SUM COMMENT '销售数量',
    sale_amount DECIMAL(10,2) SUM COMMENT '销售金额'
)
AGGREGATE KEY(sale_date, product_id)
COMMENT '销售汇总表'
DISTRIBUTED BY HASH(product_id) BUCKETS 10;

-- 创建表（唯一主键模型）
CREATE TABLE products (
    product_id BIGINT COMMENT '商品ID',
    product_name VARCHAR(200) COMMENT '商品名称',
    price DECIMAL(10,2) COMMENT '价格',
    stock INT COMMENT '库存',
    update_time DATETIME COMMENT '更新时间'
)
UNIQUE KEY(product_id)
COMMENT '商品表'
DISTRIBUTED BY HASH(product_id) BUCKETS 10;

-- 查看所有表
SHOW TABLES;

-- 查看表结构
DESC users;
DESCRIBE users;

-- 查看建表语句
SHOW CREATE TABLE users;

-- 修改表名
ALTER TABLE users RENAME user_info;

-- 添加列
ALTER TABLE users ADD COLUMN email VARCHAR(100) AFTER user_name;

-- 删除列
ALTER TABLE users DROP COLUMN email;

-- 修改列类型
ALTER TABLE users MODIFY COLUMN age BIGINT;

-- 删除表
DROP TABLE IF EXISTS users;
```

### 分区操作

```sql
-- 添加分区
ALTER TABLE users ADD PARTITION p202403 
VALUES LESS THAN ('2024-04-01');

-- 删除分区
ALTER TABLE users DROP PARTITION p202401;

-- 查看分区
SHOW PARTITIONS FROM users;

-- 修改分区属性
ALTER TABLE users MODIFY PARTITION p202402 
SET ("replication_num" = "2");
```

---

## 数据操作语言 (DML)

### INSERT 插入数据

```sql
-- 插入单条数据
INSERT INTO users VALUES (1, '张三', 25, '北京', NOW());

-- 插入多条数据
INSERT INTO users VALUES 
    (2, '李四', 30, '上海', NOW()),
    (3, '王五', 28, '广州', NOW()),
    (4, '赵六', 35, '深圳', NOW());

-- 指定列插入
INSERT INTO users (user_id, user_name, city) 
VALUES (5, '钱七', '杭州');

-- 从查询结果插入
INSERT INTO users_backup 
SELECT * FROM users WHERE age > 25;

-- 聚合模型插入（自动聚合）
INSERT INTO sales_summary VALUES
    ('2024-01-01', 1, 10, 1000.00),
    ('2024-01-01', 1, 5, 500.00);  -- 会自动聚合
-- 结果：('2024-01-01', 1, 15, 1500.00)
```

### UPDATE 更新数据

```sql
-- 更新数据（仅 Unique Key 模型支持）
UPDATE products 
SET price = 999.00, stock = 100 
WHERE product_id = 1;

-- 条件更新
UPDATE products 
SET stock = stock - 1 
WHERE product_id = 1 AND stock > 0;

-- 使用子查询更新
UPDATE products 
SET price = (
    SELECT AVG(price) FROM products WHERE category = '手机'
)
WHERE product_id = 1;
```

### DELETE 删除数据

```sql
-- 删除数据
DELETE FROM users WHERE user_id = 5;

-- 条件删除
DELETE FROM users WHERE age < 18;

-- 删除分区数据
DELETE FROM users WHERE create_time < '2024-01-01';

-- 清空表（保留表结构）
TRUNCATE TABLE users;
```

---

## 数据查询语言 (DQL)

### SELECT 基础

```sql
-- 查询所有列
SELECT * FROM users;

-- 查询指定列
SELECT user_id, user_name, city FROM users;

-- 使用别名
SELECT 
    user_id AS id,
    user_name AS name,
    city AS city_name
FROM users;

-- 去重查询
SELECT DISTINCT city FROM users;

-- 常量列
SELECT 
    user_id,
    user_name,
    '活跃用户' AS user_type
FROM users;
```

### WHERE 条件

```sql
-- 等值条件
SELECT * FROM users WHERE city = '北京';

-- 比较条件
SELECT * FROM users WHERE age > 25;
SELECT * FROM users WHERE age >= 25;
SELECT * FROM users WHERE age < 30;
SELECT * FROM users WHERE age <= 30;
SELECT * FROM users WHERE age != 25;
SELECT * FROM users WHERE age <> 25;

-- 范围条件
SELECT * FROM users WHERE age BETWEEN 20 AND 30;
SELECT * FROM users WHERE create_time BETWEEN '2024-01-01' AND '2024-01-31';

-- IN 条件
SELECT * FROM users WHERE city IN ('北京', '上海', '广州');

-- NOT 条件
SELECT * FROM users WHERE city NOT IN ('北京', '上海');
SELECT * FROM users WHERE age NOT BETWEEN 20 AND 30;

-- LIKE 模糊匹配
SELECT * FROM users WHERE user_name LIKE '张%';    -- 以张开头
SELECT * FROM users WHERE user_name LIKE '%三';    -- 以三结尾
SELECT * FROM users WHERE user_name LIKE '%小%';   -- 包含小

-- 正则匹配
SELECT * FROM users WHERE user_name REGEXP '^张';

-- NULL 判断
SELECT * FROM users WHERE email IS NULL;
SELECT * FROM users WHERE email IS NOT NULL;

-- 逻辑运算
SELECT * FROM users WHERE city = '北京' AND age > 25;
SELECT * FROM users WHERE city = '北京' OR city = '上海';
SELECT * FROM users WHERE (city = '北京' OR city = '上海') AND age > 25;
```

### ORDER BY 排序

```sql
-- 升序排序（默认）
SELECT * FROM users ORDER BY age;

-- 降序排序
SELECT * FROM users ORDER BY age DESC;

-- 多列排序
SELECT * FROM users ORDER BY city ASC, age DESC;

-- NULL 排序
SELECT * FROM users ORDER BY email IS NULL, email;
```

### LIMIT 分页

```sql
-- 限制返回行数
SELECT * FROM users LIMIT 10;

-- 分页查询
SELECT * FROM users LIMIT 10 OFFSET 0;   -- 第1页
SELECT * FROM users LIMIT 10 OFFSET 10;  -- 第2页
SELECT * FROM users LIMIT 10 OFFSET 20;  -- 第3页

-- 简写形式
SELECT * FROM users LIMIT 0, 10;   -- 第1页
SELECT * FROM users LIMIT 10, 10;  -- 第2页
```

### GROUP BY 分组

```sql
-- 基础分组
SELECT city, COUNT(*) as user_count
FROM users
GROUP BY city;

-- 多列分组
SELECT city, gender, COUNT(*) as user_count
FROM users
GROUP BY city, gender;

-- 分组过滤（HAVING）
SELECT city, COUNT(*) as user_count
FROM users
GROUP BY city
HAVING COUNT(*) > 10;

-- GROUPING SETS
SELECT city, gender, COUNT(*) as user_count
FROM users
GROUP BY GROUPING SETS (
    (city, gender),
    (city),
    (gender),
    ()
);

-- ROLLUP
SELECT city, gender, COUNT(*) as user_count
FROM users
GROUP BY ROLLUP (city, gender);

-- CUBE
SELECT city, gender, COUNT(*) as user_count
FROM users
GROUP BY CUBE (city, gender);
```

### 聚合函数

```sql
-- 基础聚合
SELECT 
    COUNT(*) as total_count,           -- 总行数
    COUNT(DISTINCT city) as city_count, -- 去重计数
    SUM(amount) as total_amount,        -- 求和
    AVG(age) as avg_age,                -- 平均值
    MAX(age) as max_age,                -- 最大值
    MIN(age) as min_age                 -- 最小值
FROM users;

-- 条件聚合
SELECT 
    COUNT(*) as total,
    COUNT(CASE WHEN age > 30 THEN 1 END) as over_30,
    SUM(CASE WHEN city = '北京' THEN amount ELSE 0 END) as beijing_amount
FROM orders;

-- 百分位
SELECT 
    PERCENTILE(age, 0.5) as median,     -- 中位数
    PERCENTILE(age, 0.9) as p90         -- 90分位
FROM users;

-- 字符串聚合
SELECT 
    city,
    GROUP_CONCAT(user_name) as user_names,
    GROUP_CONCAT(user_name SEPARATOR '|') as names_pipe
FROM users
GROUP BY city;
```

---

## 多表关联

### JOIN 类型

```sql
-- INNER JOIN（内连接）
SELECT u.user_name, o.order_id, o.amount
FROM users u
INNER JOIN orders o ON u.user_id = o.user_id;

-- LEFT JOIN（左连接）
SELECT u.user_name, o.order_id
FROM users u
LEFT JOIN orders o ON u.user_id = o.user_id;

-- RIGHT JOIN（右连接）
SELECT u.user_name, o.order_id
FROM users u
RIGHT JOIN orders o ON u.user_id = o.user_id;

-- FULL OUTER JOIN（全外连接）
SELECT u.user_name, o.order_id
FROM users u
FULL OUTER JOIN orders o ON u.user_id = o.user_id;

-- CROSS JOIN（交叉连接）
SELECT u.user_name, p.product_name
FROM users u
CROSS JOIN products p;

-- 自连接
SELECT a.user_name, b.user_name as referrer
FROM users a
LEFT JOIN users b ON a.referrer_id = b.user_id;
```

### JOIN 优化

```sql
-- 使用 Colocate Join（同分布）
-- 需要两个表的分桶列和分桶数相同
SELECT u.user_name, o.order_id
FROM users u
JOIN orders o ON u.user_id = o.user_id;

-- 使用 Bucket Shuffle Join
SELECT /*+ SET_VAR(enable_bucket_shuffle_join=true) */
    u.user_name, o.order_id
FROM users u
JOIN orders o ON u.user_id = o.user_id;

-- 使用 Runtime Filter
SELECT /*+ SET_VAR(runtime_filter_type="IN_OR_BLOOM_FILTER") */
    u.user_name, o.order_id
FROM users u
JOIN orders o ON u.user_id = o.user_id
WHERE o.amount > 1000;
```

---

## 子查询

### 标量子查询

```sql
-- 返回单个值
SELECT * FROM users 
WHERE age > (SELECT AVG(age) FROM users);

-- 在 SELECT 中使用
SELECT 
    user_name,
    (SELECT COUNT(*) FROM orders WHERE user_id = u.user_id) as order_count
FROM users u;
```

### 列子查询

```sql
-- IN 子查询
SELECT * FROM users 
WHERE user_id IN (SELECT user_id FROM orders WHERE amount > 1000);

-- EXISTS 子查询
SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.user_id);
```

### 行子查询

```sql
-- 多列子查询
SELECT * FROM users 
WHERE (city, age) IN (
    SELECT city, MAX(age) FROM users GROUP BY city
);
```

### 派生表

```sql
-- 子查询作为表
SELECT t.city, t.user_count
FROM (
    SELECT city, COUNT(*) as user_count
    FROM users
    GROUP BY city
) t
WHERE t.user_count > 10;

-- WITH 子句（CTE）
WITH user_stats AS (
    SELECT city, COUNT(*) as user_count
    FROM users
    GROUP BY city
),
order_stats AS (
    SELECT city, SUM(amount) as total_amount
    FROM orders o
    JOIN users u ON o.user_id = u.user_id
    GROUP BY city
)
SELECT 
    us.city,
    us.user_count,
    os.total_amount
FROM user_stats us
LEFT JOIN order_stats os ON us.city = os.city;
```

---

## 窗口函数

### 排名函数

```sql
-- ROW_NUMBER：连续编号
SELECT 
    user_name,
    amount,
    ROW_NUMBER() OVER (ORDER BY amount DESC) as rank
FROM orders;

-- RANK：并列跳过
SELECT 
    user_name,
    amount,
    RANK() OVER (ORDER BY amount DESC) as rank
FROM orders;

-- DENSE_RANK：并列不跳过
SELECT 
    user_name,
    amount,
    DENSE_RANK() OVER (ORDER BY amount DESC) as rank
FROM orders;

-- 分组排名
SELECT 
    city,
    user_name,
    amount,
    ROW_NUMBER() OVER (PARTITION BY city ORDER BY amount DESC) as city_rank
FROM orders;
```

### 聚合窗口函数

```sql
-- 累计求和
SELECT 
    order_date,
    amount,
    SUM(amount) OVER (ORDER BY order_date) as cumulative_amount
FROM orders;

-- 移动平均
SELECT 
    order_date,
    amount,
    AVG(amount) OVER (
        ORDER BY order_date 
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) as moving_avg
FROM orders;

-- 分组聚合
SELECT 
    city,
    user_name,
    amount,
    SUM(amount) OVER (PARTITION BY city) as city_total
FROM orders;
```

### 偏移函数

```sql
-- LAG：获取前一行
SELECT 
    order_date,
    amount,
    LAG(amount, 1) OVER (ORDER BY order_date) as prev_amount,
    amount - LAG(amount, 1) OVER (ORDER BY order_date) as diff
FROM orders;

-- LEAD：获取后一行
SELECT 
    order_date,
    amount,
    LEAD(amount, 1) OVER (ORDER BY order_date) as next_amount
FROM orders;

-- FIRST_VALUE / LAST_VALUE
SELECT 
    order_date,
    amount,
    FIRST_VALUE(amount) OVER (ORDER BY order_date) as first_amount,
    LAST_VALUE(amount) OVER (
        ORDER BY order_date 
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) as last_amount
FROM orders;
```

---

## 实用技巧

### 条件表达式

```sql
-- CASE WHEN
SELECT 
    user_name,
    CASE 
        WHEN age < 18 THEN '未成年'
        WHEN age < 30 THEN '青年'
        WHEN age < 50 THEN '中年'
        ELSE '老年'
    END as age_group
FROM users;

-- IF 函数
SELECT 
    user_name,
    IF(age >= 18, '成年', '未成年') as is_adult
FROM users;

-- NULLIF
SELECT NULLIF(amount, 0) FROM orders;

-- COALESCE
SELECT COALESCE(email, phone, 'N/A') as contact FROM users;
```

### 字符串函数

```sql
-- 字符串拼接
SELECT CONCAT(user_name, '-', city) FROM users;
SELECT CONCAT_WS('-', user_name, city) FROM users;

-- 字符串截取
SELECT SUBSTRING(user_name, 1, 3) FROM users;
SELECT LEFT(user_name, 3) FROM users;
SELECT RIGHT(user_name, 3) FROM users;

-- 字符串处理
SELECT LOWER(user_name) FROM users;
SELECT UPPER(user_name) FROM users;
SELECT TRIM(user_name) FROM users;
SELECT REPLACE(user_name, '张', '王') FROM users;

-- 字符串长度
SELECT LENGTH(user_name) FROM users;
```

### 日期函数

```sql
-- 当前日期时间
SELECT CURRENT_DATE();
SELECT CURRENT_TIMESTAMP();
SELECT NOW();

-- 日期提取
SELECT YEAR(create_time) FROM users;
SELECT MONTH(create_time) FROM users;
SELECT DAY(create_time) FROM users;
SELECT HOUR(create_time) FROM users;

-- 日期计算
SELECT DATE_ADD(create_time, INTERVAL 1 DAY) FROM users;
SELECT DATE_SUB(create_time, INTERVAL 1 MONTH) FROM users;
SELECT DATEDIFF('2024-01-31', '2024-01-01');

-- 日期格式化
SELECT DATE_FORMAT(create_time, '%Y-%m-%d') FROM users;
SELECT DATE_FORMAT(create_time, '%Y年%m月%d日') FROM users;
```

---

## 下一步

- [数据模型](./05-data-model.md) - 深入理解三种数据模型
- [数据导入](./06-data-import.md) - 掌握多种导入方式
- [数据导出](./07-data-export.md) - 学习数据导出
