# 聚合函数

## 基本聚合函数

### COUNT

```sql
-- COUNT(*): 统计所有行
SELECT COUNT(*) FROM users;

-- COUNT(column): 统计非 NULL 值
SELECT COUNT(user_name) FROM users;

-- COUNT(DISTINCT): 统计不同值的数量
SELECT COUNT(DISTINCT city) FROM users;

-- COUNT(DISTINCT) + 多列
SELECT COUNT(DISTINCT city, age) FROM users;

-- COUNT + GROUP BY
SELECT city, COUNT(*) as user_count
FROM users
GROUP BY city;
```

### SUM

```sql
-- SUM(column): 求和
SELECT SUM(amount) FROM orders;

-- SUM + DISTINCT
SELECT SUM(DISTINCT amount) FROM orders;

-- SUM + GROUP BY
SELECT user_id, SUM(amount) as total_amount
FROM orders
GROUP BY user_id;

-- SUM + WHERE
SELECT SUM(amount) as total_amount
FROM orders
WHERE order_date >= '2024-01-01' AND order_date < '2024-02-01';
```

### AVG

```sql
-- AVG(column): 平均值
SELECT AVG(age) FROM users;

-- AVG + GROUP BY
SELECT city, AVG(age) as avg_age
FROM users
GROUP BY city;

-- AVG + WHERE
SELECT AVG(amount) as avg_amount
FROM orders
WHERE order_date >= '2024-01-01' AND order_date < '2024-02-01';

-- AVG + ROUND
SELECT ROUND(AVG(age), 2) as avg_age FROM users;
```

### MIN/MAX

```sql
-- MIN(column): 最小值
SELECT MIN(age) FROM users;

-- MAX(column): 最大值
SELECT MAX(age) FROM users;

-- MIN/MAX + GROUP BY
SELECT city, MIN(age) as min_age, MAX(age) as max_age
FROM users
GROUP BY city;

-- MIN/MAX + WHERE
SELECT MIN(amount) as min_amount, MAX(amount) as max_amount
FROM orders
WHERE order_date >= '2024-01-01' AND order_date < '2024-02-01';
```

## GROUP BY

### 基本 GROUP BY

```sql
-- 单列分组
SELECT city, COUNT(*) as user_count
FROM users
GROUP BY city;

-- 多列分组
SELECT city, gender, COUNT(*) as user_count
FROM users
GROUP BY city, gender;

-- GROUP BY + 聚合函数
SELECT city, COUNT(*) as user_count, AVG(age) as avg_age, SUM(amount) as total_amount
FROM users u
LEFT JOIN orders o ON u.user_id = o.user_id
GROUP BY city;
```

### GROUP BY + ORDER BY

```sql
-- GROUP BY + ORDER BY
SELECT city, COUNT(*) as user_count
FROM users
GROUP BY city
ORDER BY user_count DESC;

-- GROUP BY + ORDER BY + LIMIT
SELECT city, COUNT(*) as user_count
FROM users
GROUP BY city
ORDER BY user_count DESC
LIMIT 10;
```

### GROUP BY + HAVING

```sql
-- HAVING 过滤分组
SELECT city, COUNT(*) as user_count
FROM users
GROUP BY city
HAVING COUNT(*) > 5;

-- HAVING + 多条件
SELECT city, COUNT(*) as user_count, AVG(age) as avg_age
FROM users
GROUP BY city
HAVING COUNT(*) > 5 AND AVG(age) > 30;

-- HAVING + WHERE
SELECT city, COUNT(*) as user_count
FROM users
WHERE age > 25
GROUP BY city
HAVING COUNT(*) > 5;
```

## 高级聚合函数

### GROUP_CONCAT

```sql
-- GROUP_CONCAT: 连接字符串
SELECT city, GROUP_CONCAT(user_name) as user_names
FROM users
GROUP BY city;

-- GROUP_CONCAT + SEPARATOR
SELECT city, GROUP_CONCAT(user_name SEPARATOR ', ') as user_names
FROM users
GROUP BY city;

-- GROUP_CONCAT + ORDER BY
SELECT city, GROUP_CONCAT(user_name ORDER BY age DESC SEPARATOR ', ') as user_names
FROM users
GROUP BY city;

-- GROUP_CONCAT + LIMIT
SELECT city, GROUP_CONCAT(user_name ORDER BY age DESC SEPARATOR ', ' LIMIT 5) as user_names
FROM users
GROUP BY city;
```

### PERCENTILE

```sql
-- PERCENTILE: 百分位数
SELECT PERCENTILE(age, 0.5) as median_age FROM users;

-- PERCENTILE + GROUP BY
SELECT city, PERCENTILE(age, 0.5) as median_age
FROM users
GROUP BY city;

-- PERCENTILE + 多个百分位数
SELECT PERCENTILE(age, 0.25) as p25,
       PERCENTILE(age, 0.5) as p50,
       PERCENTILE(age, 0.75) as p75
FROM users;
```

### HLL

```sql
-- HLL: HyperLogLog 基数估计
SELECT HLL_COUNT(HLL_HASH(user_id)) as estimated_user_count
FROM users;

-- HLL + GROUP BY
SELECT city, HLL_COUNT(HLL_HASH(user_id)) as estimated_user_count
FROM users
GROUP BY city;

-- HLL + DISTINCT
SELECT COUNT(DISTINCT user_id) as exact_user_count,
       HLL_COUNT(HLL_HASH(user_id)) as estimated_user_count
FROM users;
```

### BITMAP

```sql
-- BITMAP: 位图聚合
SELECT BITMAP_COUNT(BITMAP_HASH(user_id)) as user_count
FROM users;

-- BITMAP + GROUP BY
SELECT city, BITMAP_COUNT(BITMAP_HASH(user_id)) as user_count
FROM users
GROUP BY city;

-- BITMAP + INTERSECT
SELECT BITMAP_COUNT(BITMAP_INTERSECT(
    BITMAP_HASH(user_id)
)) as user_count
FROM users
WHERE city = 'Beijing';
```

## 窗口函数

### ROW_NUMBER

```sql
-- ROW_NUMBER: 行号
SELECT user_id, user_name, age,
       ROW_NUMBER() OVER (ORDER BY age DESC) as rank
FROM users;

-- ROW_NUMBER + PARTITION BY
SELECT city, user_name, age,
       ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) as rank
FROM users;

-- ROW_NUMBER + 过滤
SELECT * FROM (
    SELECT city, user_name, age,
           ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) as rank
    FROM users
) t
WHERE rank <= 3;
```

### RANK

```sql
-- RANK: 排名（有并列，跳过）
SELECT user_id, user_name, age,
       RANK() OVER (ORDER BY age DESC) as rank
FROM users;

-- RANK + PARTITION BY
SELECT city, user_name, age,
       RANK() OVER (PARTITION BY city ORDER BY age DESC) as rank
FROM users;
```

### DENSE_RANK

```sql
-- DENSE_RANK: 排名（有并列，不跳过）
SELECT user_id, user_name, age,
       DENSE_RANK() OVER (ORDER BY age DESC) as rank
FROM users;

-- DENSE_RANK + PARTITION BY
SELECT city, user_name, age,
       DENSE_RANK() OVER (PARTITION BY city ORDER BY age DESC) as rank
FROM users;
```

### LAG/LEAD

```sql
-- LAG: 前一行值
SELECT user_id, user_name, age,
       LAG(age) OVER (ORDER BY user_id) as prev_age
FROM users;

-- LEAD: 后一行值
SELECT user_id, user_name, age,
       LEAD(age) OVER (ORDER BY user_id) as next_age
FROM users;

-- LAG/LEAD + PARTITION BY
SELECT city, user_name, age,
       LAG(age) OVER (PARTITION BY city ORDER BY user_id) as prev_age,
       LEAD(age) OVER (PARTITION BY city ORDER BY user_id) as next_age
FROM users;
```

### SUM/MIN/MAX/AVG 窗口函数

```sql
-- SUM 窗口函数
SELECT user_id, user_name, amount,
       SUM(amount) OVER (ORDER BY order_date) as running_total
FROM orders;

-- MIN/MAX 窗口函数
SELECT user_id, user_name, amount,
       MIN(amount) OVER (ORDER BY order_date) as min_amount,
       MAX(amount) OVER (ORDER BY order_date) as max_amount
FROM orders;

-- AVG 窗口函数
SELECT user_id, user_name, amount,
       AVG(amount) OVER (ORDER BY order_date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) as avg_amount
FROM orders;
```

## 聚合优化

### 使用索引优化聚合

```sql
-- 为聚合列创建索引
CREATE INDEX idx_city_bitmap ON users (city) USING BITMAP;

-- 使用索引优化聚合
SELECT city, COUNT(*) as user_count
FROM users
GROUP BY city;
```

### 使用分区裁剪优化聚合

```sql
-- 使用分区键查询
SELECT order_date, SUM(amount) as total_amount
FROM orders
WHERE order_date >= '2024-01-01' AND order_date < '2024-02-01'
GROUP BY order_date;
```

### 使用物化视图优化聚合

```sql
-- 创建物化视图
CREATE MATERIALIZED VIEW mv_user_city_stats
AS SELECT city, COUNT(*) as user_count, AVG(age) as avg_age
FROM users
GROUP BY city;

-- 查询物化视图
SELECT * FROM mv_user_city_stats;
```

## 聚合最佳实践

### 1. 选择合适的聚合函数

| 场景 | 推荐函数 | 示例 |
|------|---------|------|
| 统计行数 | COUNT | COUNT(*) |
| 求和 | SUM | SUM(amount) |
| 平均值 | AVG | AVG(age) |
| 最小/最大值 | MIN/MAX | MIN(age), MAX(age) |
| 连接字符串 | GROUP_CONCAT | GROUP_CONCAT(user_name) |
| 百分位数 | PERCENTILE | PERCENTILE(age, 0.5) |
| 基数估计 | HLL | HLL_COUNT(HLL_HASH(user_id)) |
| 位图聚合 | BITMAP | BITMAP_COUNT(BITMAP_HASH(user_id)) |

### 2. 优化聚合性能

```sql
-- 使用索引优化聚合
CREATE INDEX idx_city_bitmap ON users (city) USING BITMAP;

-- 使用分区裁剪优化聚合
SELECT order_date, SUM(amount) as total_amount
FROM orders
WHERE order_date >= '2024-01-01' AND order_date < '2024-02-01'
GROUP BY order_date;

-- 使用物化视图优化聚合
CREATE MATERIALIZED VIEW mv_user_city_stats
AS SELECT city, COUNT(*) as user_count, AVG(age) as avg_age
FROM users
GROUP BY city;
```

### 3. 避免全表聚合

```sql
-- 不好的写法：全表聚合
SELECT COUNT(*) FROM users;

-- 好的写法：使用 WHERE 限制范围
SELECT COUNT(*) FROM users WHERE city = 'Beijing';

-- 不好的写法：全表聚合 + GROUP BY
SELECT city, COUNT(*) FROM users GROUP BY city;

-- 好的写法：使用 WHERE 限制范围 + GROUP BY
SELECT city, COUNT(*) FROM users WHERE age > 25 GROUP BY city;
```

## 常见问题

### 聚合结果不正确

```sql
-- 检查 GROUP BY 列
SELECT city, COUNT(*) as user_count
FROM users
GROUP BY city;

-- 检查 WHERE 条件
SELECT city, COUNT(*) as user_count
FROM users
WHERE age > 25
GROUP BY city;

-- 检查 HAVING 条件
SELECT city, COUNT(*) as user_count
FROM users
GROUP BY city
HAVING COUNT(*) > 5;
```

### 聚合性能慢

```sql
-- 检查执行计划
EXPLAIN SELECT city, COUNT(*) as user_count
FROM users
GROUP BY city;

-- 为聚合列创建索引
CREATE INDEX idx_city_bitmap ON users (city) USING BITMAP;

-- 使用分区裁剪
SELECT order_date, SUM(amount) as total_amount
FROM orders
WHERE order_date >= '2024-01-01' AND order_date < '2024-02-01'
GROUP BY order_date;
```

### 聚合内存不足

```sql
-- 减少数据量
SELECT city, COUNT(*) as user_count
FROM users
WHERE age > 25
GROUP BY city;

-- 使用 LIMIT 限制结果
SELECT city, COUNT(*) as user_count
FROM users
GROUP BY city
LIMIT 100;
```

## 下一步

- [高级功能](./10-advanced.md) - 学习物化视图、动态分区等高级功能
