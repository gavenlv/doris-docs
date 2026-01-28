# 增删改查操作

## 插入数据

### 单条插入

```sql
-- 基本插入
INSERT INTO users (user_id, user_name, age, city, register_date)
VALUES (1, 'Alice', 25, 'Beijing', '2024-01-01');

-- 指定列插入
INSERT INTO users (user_id, user_name, age)
VALUES (2, 'Bob', 30);

-- 全列插入
INSERT INTO users VALUES (3, 'Charlie', 35, 'Shanghai', '2024-01-03');
```

### 批量插入

```sql
-- 多值插入
INSERT INTO users VALUES
    (4, 'David', 28, 'Guangzhou', '2024-01-04'),
    (5, 'Eve', 32, 'Shenzhen', '2024-01-05'),
    (6, 'Frank', 27, 'Hangzhou', '2024-01-06');

-- 使用 VALUES 批量插入
INSERT INTO users (user_id, user_name, age, city)
VALUES
    (7, 'Grace', 29, 'Chengdu'),
    (8, 'Henry', 31, 'Chongqing'),
    (9, 'Ivy', 26, 'Wuhan');
```

### 从查询插入

```sql
-- 从其他表插入
INSERT INTO users_archive
SELECT * FROM users WHERE age > 30;

-- 插入指定列
INSERT INTO users (user_id, user_name, age)
SELECT user_id, user_name, age FROM temp_users;
```

### 使用 Stream Load 导入

```bash
# 导入 CSV 文件
curl --location-trusted -u root: \
    -H "label:label_20240101" \
    -H "column_separator:," \
    -T data.csv \
    http://127.0.0.1:8030/api/my_database/users/_stream_load

# 导入 JSON 文件
curl --location-trusted -u root: \
    -H "label:label_20240101" \
    -H "format:json" \
    -H "strip_outer_array:true" \
    -T data.json \
    http://127.0.0.1:8030/api/my_database/users/_stream_load
```

## 查询数据

### 基本查询

```sql
-- 查询所有列
SELECT * FROM users;

-- 查询指定列
SELECT user_id, user_name, age FROM users;

-- 查询并去重
SELECT DISTINCT city FROM users;

-- 查询并排序
SELECT * FROM users ORDER BY age DESC;

-- 查询并限制数量
SELECT * FROM users LIMIT 10;

-- 查询并分页
SELECT * FROM users LIMIT 10 OFFSET 20;
```

### 条件查询

```sql
-- WHERE 条件
SELECT * FROM users WHERE age > 30;

-- 多条件查询
SELECT * FROM users WHERE age > 25 AND city = 'Beijing';

-- OR 条件
SELECT * FROM users WHERE city = 'Beijing' OR city = 'Shanghai';

-- IN 条件
SELECT * FROM users WHERE city IN ('Beijing', 'Shanghai', 'Guangzhou');

-- NOT IN 条件
SELECT * FROM users WHERE city NOT IN ('Beijing', 'Shanghai');

-- BETWEEN 条件
SELECT * FROM users WHERE age BETWEEN 25 AND 35;

-- LIKE 模糊查询
SELECT * FROM users WHERE user_name LIKE 'A%';

-- 正则表达式
SELECT * FROM users WHERE user_name REGEXP '^A.*e$';
```

### 聚合查询

```sql
-- COUNT
SELECT COUNT(*) FROM users;
SELECT COUNT(DISTINCT city) FROM users;

-- SUM
SELECT SUM(age) FROM users;

-- AVG
SELECT AVG(age) FROM users;

-- MAX/MIN
SELECT MAX(age), MIN(age) FROM users;

-- GROUP BY
SELECT city, COUNT(*), AVG(age)
FROM users
GROUP BY city;

-- HAVING
SELECT city, COUNT(*)
FROM users
GROUP BY city
HAVING COUNT(*) > 2;
```

### 连接查询

```sql
-- INNER JOIN
SELECT u.user_name, o.order_id, o.amount
FROM users u
INNER JOIN orders o ON u.user_id = o.user_id;

-- LEFT JOIN
SELECT u.user_name, o.order_id, o.amount
FROM users u
LEFT JOIN orders o ON u.user_id = o.user_id;

-- RIGHT JOIN
SELECT u.user_name, o.order_id, o.amount
FROM users u
RIGHT JOIN orders o ON u.user_id = o.user_id;

-- FULL JOIN
SELECT u.user_name, o.order_id, o.amount
FROM users u
FULL JOIN orders o ON u.user_id = o.user_id;
```

### 子查询

```sql
-- WHERE 子查询
SELECT * FROM users
WHERE user_id IN (SELECT user_id FROM orders WHERE amount > 1000);

-- FROM 子查询
SELECT * FROM (
    SELECT city, COUNT(*) as user_count
    FROM users
    GROUP BY city
) t
WHERE user_count > 2;

-- EXISTS 子查询
SELECT * FROM users u
WHERE EXISTS (
    SELECT 1 FROM orders o
    WHERE o.user_id = u.user_id AND o.amount > 1000
);
```

### 窗口函数

```sql
-- ROW_NUMBER
SELECT
    user_id,
    user_name,
    age,
    ROW_NUMBER() OVER (ORDER BY age DESC) as rank
FROM users;

-- RANK
SELECT
    user_id,
    user_name,
    age,
    RANK() OVER (ORDER BY age DESC) as rank
FROM users;

-- DENSE_RANK
SELECT
    user_id,
    user_name,
    age,
    DENSE_RANK() OVER (ORDER BY age DESC) as rank
FROM users;

-- LAG/LEAD
SELECT
    user_id,
    user_name,
    age,
    LAG(age) OVER (ORDER BY user_id) as prev_age,
    LEAD(age) OVER (ORDER BY user_id) as next_age
FROM users;
```

## 更新数据

### 单条更新

```sql
-- 更新单列
UPDATE users SET age = 26 WHERE user_id = 1;

-- 更新多列
UPDATE users
SET age = 26, city = 'Shanghai'
WHERE user_id = 1;
```

### 批量更新

```sql
-- 条件批量更新
UPDATE users SET age = age + 1 WHERE city = 'Beijing';

-- 使用 CASE 更新
UPDATE users
SET age = CASE
    WHEN city = 'Beijing' THEN age + 1
    WHEN city = 'Shanghai' THEN age + 2
    ELSE age
END;
```

### 从查询更新

```sql
-- 从其他表更新
UPDATE users u
SET age = t.new_age
FROM temp_ages t
WHERE u.user_id = t.user_id;
```

## 删除数据

### 单条删除

```sql
-- 删除单条记录
DELETE FROM users WHERE user_id = 1;
```

### 批量删除

```sql
-- 条件删除
DELETE FROM users WHERE age > 40;

-- 多条件删除
DELETE FROM users WHERE age > 30 AND city = 'Beijing';

-- IN 删除
DELETE FROM users WHERE city IN ('Beijing', 'Shanghai');
```

### 清空表

```sql
-- 清空表数据
TRUNCATE TABLE users;

-- 清空表（如果存在）
TRUNCATE TABLE IF EXISTS users;
```

### 分区删除

```sql
-- 删除分区
ALTER TABLE orders DROP PARTITION p202401;

-- 删除多个分区
ALTER TABLE orders DROP PARTITION p202401, p202402;
```

## 常用函数

### 字符串函数

```sql
-- 字符串长度
SELECT LENGTH(user_name) FROM users;

-- 字符串拼接
SELECT CONCAT(user_name, ' from ', city) FROM users;

-- 字符串截取
SELECT SUBSTRING(user_name, 1, 3) FROM users;

-- 大小写转换
SELECT UPPER(user_name), LOWER(user_name) FROM users;

-- 去除空格
SELECT TRIM(user_name) FROM users;

-- 字符串替换
SELECT REPLACE(user_name, 'Alice', 'Alicia') FROM users;
```

### 日期函数

```sql
-- 当前日期时间
SELECT NOW();
SELECT CURRENT_DATE();
SELECT CURRENT_TIME();

-- 日期加减
SELECT DATE_ADD(register_date, INTERVAL 7 DAY) FROM users;
SELECT DATE_SUB(register_date, INTERVAL 1 MONTH) FROM users;

-- 日期差
SELECT DATEDIFF(NOW(), register_date) FROM users;

-- 日期格式化
SELECT DATE_FORMAT(register_date, '%Y-%m-%d') FROM users;

-- 日期提取
SELECT YEAR(register_date), MONTH(register_date), DAY(register_date) FROM users;
```

### 数值函数

```sql
-- 四舍五入
SELECT ROUND(age) FROM users;
SELECT ROUND(age, 1) FROM users;

-- 向上取整
SELECT CEIL(age / 10) FROM users;

-- 向下取整
SELECT FLOOR(age / 10) FROM users;

-- 绝对值
SELECT ABS(age - 30) FROM users;

-- 取模
SELECT MOD(user_id, 10) FROM users;
```

### 条件函数

```sql
-- IF
SELECT user_id, user_name, IF(age > 30, 'Old', 'Young') as age_group
FROM users;

-- IFNULL
SELECT user_id, IFNULL(email, 'N/A') as email
FROM users;

-- CASE
SELECT user_id, user_name, age,
    CASE
        WHEN age < 20 THEN 'Teenager'
        WHEN age < 30 THEN 'Young Adult'
        WHEN age < 50 THEN 'Adult'
        ELSE 'Senior'
    END as age_group
FROM users;
```

## 性能优化

### 使用索引

```sql
-- 创建索引
CREATE INDEX idx_city ON users (city) USING BITMAP;

-- 使用索引查询
SELECT * FROM users WHERE city = 'Beijing';
```

### 分区裁剪

```sql
-- 使用分区键查询
SELECT * FROM orders
WHERE order_date >= '2024-01-01' AND order_date < '2024-02-01';
```

### 分桶裁剪

```sql
-- 使用分桶键查询
SELECT * FROM users WHERE user_id = 1;
```

### LIMIT 优化

```sql
-- 使用 LIMIT 限制结果集
SELECT * FROM users LIMIT 100;
```

## 下一步

- [数据导入](./04-data-import.md) - 学习如何导入数据到 Doris
