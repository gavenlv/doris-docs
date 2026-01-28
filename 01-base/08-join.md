# JOIN 操作

## JOIN 类型

Doris 支持多种 JOIN 类型：

| JOIN 类型 | 说明 | 语法 |
|-----------|------|------|
| INNER JOIN | 内连接，只返回匹配的行 | INNER JOIN |
| LEFT JOIN | 左连接，返回左表所有行 | LEFT JOIN |
| RIGHT JOIN | 右连接，返回右表所有行 | RIGHT JOIN |
| FULL JOIN | 全连接，返回所有行 | FULL JOIN |
| CROSS JOIN | 交叉连接，笛卡尔积 | CROSS JOIN |
| SEMI JOIN | 半连接，只返回左表行 | IN, EXISTS |
| ANTI JOIN | 反连接，返回不匹配的行 | NOT IN, NOT EXISTS |

## INNER JOIN

### 基本 INNER JOIN

```sql
-- 基本 INNER JOIN
SELECT u.user_name, o.order_id, o.amount
FROM users u
INNER JOIN orders o ON u.user_id = o.user_id;

-- 带 WHERE 条件的 INNER JOIN
SELECT u.user_name, o.order_id, o.amount
FROM users u
INNER JOIN orders o ON u.user_id = o.user_id
WHERE o.amount > 1000;

-- 带 ORDER BY 的 INNER JOIN
SELECT u.user_name, o.order_id, o.amount
FROM users u
INNER JOIN orders o ON u.user_id = o.user_id
ORDER BY o.amount DESC
LIMIT 10;
```

### 多表 INNER JOIN

```sql
-- 三表 INNER JOIN
SELECT u.user_name, o.order_id, p.product_name, o.amount
FROM users u
INNER JOIN orders o ON u.user_id = o.user_id
INNER JOIN products p ON o.product_id = p.product_id;

-- 四表 INNER JOIN
SELECT u.user_name, o.order_id, p.product_name, c.category_name, o.amount
FROM users u
INNER JOIN orders o ON u.user_id = o.user_id
INNER JOIN products p ON o.product_id = p.product_id
INNER JOIN categories c ON p.category_id = c.category_id;
```

### INNER JOIN 聚合

```sql
-- INNER JOIN + 聚合
SELECT u.user_name, COUNT(o.order_id) as order_count, SUM(o.amount) as total_amount
FROM users u
INNER JOIN orders o ON u.user_id = o.user_id
GROUP BY u.user_id
ORDER BY total_amount DESC;

-- INNER JOIN + 聚合 + HAVING
SELECT u.user_name, COUNT(o.order_id) as order_count
FROM users u
INNER JOIN orders o ON u.user_id = o.user_id
GROUP BY u.user_id
HAVING COUNT(o.order_id) > 5
ORDER BY order_count DESC;
```

## LEFT JOIN

### 基本 LEFT JOIN

```sql
-- 基本 LEFT JOIN
SELECT u.user_name, o.order_id, o.amount
FROM users u
LEFT JOIN orders o ON u.user_id = o.user_id;

-- LEFT JOIN + COALESCE
SELECT u.user_name, COALESCE(o.order_id, 0) as order_id, COALESCE(o.amount, 0) as amount
FROM users u
LEFT JOIN orders o ON u.user_id = o.user_id;

-- LEFT JOIN + IFNULL
SELECT u.user_name, IFNULL(o.order_id, 0) as order_id, IFNULL(o.amount, 0) as amount
FROM users u
LEFT JOIN orders o ON u.user_id = o.user_id;
```

### LEFT JOIN 查找无订单用户

```sql
-- 查找没有订单的用户
SELECT u.user_id, u.user_name
FROM users u
LEFT JOIN orders o ON u.user_id = o.user_id
WHERE o.order_id IS NULL;

-- 统计没有订单的用户数量
SELECT COUNT(*) as user_count
FROM users u
LEFT JOIN orders o ON u.user_id = o.user_id
WHERE o.order_id IS NULL;
```

### LEFT JOIN 聚合

```sql
-- LEFT JOIN + 聚合
SELECT u.user_name, COUNT(o.order_id) as order_count, SUM(o.amount) as total_amount
FROM users u
LEFT JOIN orders o ON u.user_id = o.user_id
GROUP BY u.user_id
ORDER BY total_amount DESC;

-- LEFT JOIN + 聚合（包含无订单用户）
SELECT u.user_name, COALESCE(COUNT(o.order_id), 0) as order_count, COALESCE(SUM(o.amount), 0) as total_amount
FROM users u
LEFT JOIN orders o ON u.user_id = o.user_id
GROUP BY u.user_id
ORDER BY total_amount DESC;
```

## RIGHT JOIN

### 基本 RIGHT JOIN

```sql
-- 基本 RIGHT JOIN
SELECT u.user_name, o.order_id, o.amount
FROM users u
RIGHT JOIN orders o ON u.user_id = o.user_id;

-- RIGHT JOIN + COALESCE
SELECT COALESCE(u.user_name, 'Unknown') as user_name, o.order_id, o.amount
FROM users u
RIGHT JOIN orders o ON u.user_id = o.user_id;
```

## FULL JOIN

### 基本 FULL JOIN

```sql
-- 基本 FULL JOIN
SELECT u.user_name, o.order_id, o.amount
FROM users u
FULL JOIN orders o ON u.user_id = o.user_id;

-- FULL JOIN + COALESCE
SELECT COALESCE(u.user_name, 'Unknown') as user_name, COALESCE(o.order_id, 0) as order_id, COALESCE(o.amount, 0) as amount
FROM users u
FULL JOIN orders o ON u.user_id = o.user_id;
```

## CROSS JOIN

### 基本 CROSS JOIN

```sql
-- 基本 CROSS JOIN（笛卡尔积）
SELECT u.user_name, p.product_name
FROM users u
CROSS JOIN products p;

-- CROSS JOIN + WHERE（相当于 INNER JOIN）
SELECT u.user_name, p.product_name
FROM users u
CROSS JOIN products p
WHERE u.user_id = 1;
```

## SEMI JOIN

### 使用 IN

```sql
-- IN 子查询
SELECT u.user_name
FROM users u
WHERE u.user_id IN (SELECT o.user_id FROM orders o WHERE o.amount > 1000);

-- IN + 多列
SELECT u.user_name
FROM users u
WHERE (u.user_id, u.city) IN (
    SELECT o.user_id, u.city
    FROM orders o
    INNER JOIN users u ON o.user_id = u.user_id
    WHERE o.amount > 1000
);
```

### 使用 EXISTS

```sql
-- EXISTS 子查询
SELECT u.user_name
FROM users u
WHERE EXISTS (
    SELECT 1
    FROM orders o
    WHERE o.user_id = u.user_id AND o.amount > 1000
);

-- NOT EXISTS 子查询
SELECT u.user_name
FROM users u
WHERE NOT EXISTS (
    SELECT 1
    FROM orders o
    WHERE o.user_id = u.user_id
);
```

## ANTI JOIN

### 使用 NOT IN

```sql
-- NOT IN 子查询
SELECT u.user_name
FROM users u
WHERE u.user_id NOT IN (SELECT o.user_id FROM orders o);

-- NOT IN + 多列
SELECT u.user_name
FROM users u
WHERE (u.user_id, u.city) NOT IN (
    SELECT o.user_id, u.city
    FROM orders o
    INNER JOIN users u ON o.user_id = u.user_id
);
```

### 使用 NOT EXISTS

```sql
-- NOT EXISTS 子查询
SELECT u.user_name
FROM users u
WHERE NOT EXISTS (
    SELECT 1
    FROM orders o
    WHERE o.user_id = u.user_id
);
```

## JOIN 优化

### 使用索引优化 JOIN

```sql
-- 为 JOIN 列创建索引
CREATE INDEX idx_user_id ON orders (user_id) USING BITMAP;

-- 使用索引优化 JOIN
SELECT u.user_name, o.order_id, o.amount
FROM users u
INNER JOIN orders o ON u.user_id = o.user_id;
```

### 使用小表驱动大表

```sql
-- 好的写法：小表驱动大表
SELECT u.user_name, o.order_id, o.amount
FROM users u
INNER JOIN orders o ON u.user_id = o.user_id;

-- 不好的写法：大表驱动小表
SELECT u.user_name, o.order_id, o.amount
FROM orders o
INNER JOIN users u ON u.user_id = o.user_id;
```

### 使用 EXPLAIN 分析 JOIN

```sql
-- 查看 JOIN 执行计划
EXPLAIN SELECT u.user_name, o.order_id, o.amount
FROM users u
INNER JOIN orders o ON u.user_id = o.user_id;

-- 查看详细执行计划
EXPLAIN VERBOSE SELECT u.user_name, o.order_id, o.amount
FROM users u
INNER JOIN orders o ON u.user_id = o.user_id;
```

## JOIN 最佳实践

### 1. 选择合适的 JOIN 类型

| 场景 | 推荐类型 | 示例 |
|------|---------|------|
| 只需要匹配的行 | INNER JOIN | 查询有订单的用户 |
| 需要左表所有行 | LEFT JOIN | 查询所有用户的订单 |
| 需要右表所有行 | RIGHT JOIN | 查询所有订单的用户 |
| 需要所有行 | FULL JOIN | 查询所有用户和订单 |
| 检查是否存在 | SEMI JOIN | 查询有订单的用户 |
| 检查是否不存在 | ANTI JOIN | 查询没有订单的用户 |

### 2. 优化 JOIN 性能

```sql
-- 为 JOIN 列创建索引
CREATE INDEX idx_user_id ON orders (user_id) USING BITMAP;

-- 使用小表驱动大表
SELECT u.user_name, o.order_id, o.amount
FROM users u
INNER JOIN orders o ON u.user_id = o.user_id;

-- 使用分区裁剪
SELECT u.user_name, o.order_id, o.amount
FROM users u
INNER JOIN orders o ON u.user_id = o.user_id
WHERE o.order_date >= '2024-01-01' AND o.order_date < '2024-02-01';
```

### 3. 避免 CROSS JOIN

```sql
-- 不好的写法：CROSS JOIN（笛卡尔积）
SELECT u.user_name, p.product_name
FROM users u
CROSS JOIN products p;

-- 好的写法：使用 INNER JOIN
SELECT u.user_name, p.product_name
FROM users u
INNER JOIN orders o ON u.user_id = o.user_id
INNER JOIN products p ON o.product_id = p.product_id;
```

## 常见问题

### JOIN 性能慢

```sql
-- 检查执行计划
EXPLAIN SELECT u.user_name, o.order_id, o.amount
FROM users u
INNER JOIN orders o ON u.user_id = o.user_id;

-- 为 JOIN 列创建索引
CREATE INDEX idx_user_id ON orders (user_id) USING BITMAP;
```

### JOIN 结果不正确

```sql
-- 检查 JOIN 条件
SELECT u.user_name, o.order_id, o.amount
FROM users u
INNER JOIN orders o ON u.user_id = o.user_id;

-- 检查是否有重复数据
SELECT u.user_id, COUNT(*) as count
FROM users u
GROUP BY u.user_id
HAVING COUNT(*) > 1;
```

### JOIN 内存不足

```sql
-- 减少数据量
SELECT u.user_name, o.order_id, o.amount
FROM users u
INNER JOIN orders o ON u.user_id = o.user_id
WHERE o.order_date >= '2024-01-01' AND o.order_date < '2024-02-01'
LIMIT 1000;
```

## 下一步

- [聚合函数](./09-aggregation.md) - 学习聚合和分组操作
