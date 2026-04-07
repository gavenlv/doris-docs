-- =====================================================
-- 第11章：JOIN深度解析
-- 演示各JOIN类型、Colocate/Shuffle/Broadcast/Bucket Shuffle
-- 所需权限：SELECT_PRIV ON tutorial
-- =====================================================

USE tutorial;

-- =====================================================
-- 1. 准备测试数据
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_join_users (
    user_id INT NOT NULL,
    username VARCHAR(50),
    city VARCHAR(50),
    age INT
) ENGINE=OLAP
DUPLICATE KEY(user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);

CREATE TABLE IF NOT EXISTS demo_join_orders (
    order_id INT NOT NULL,
    user_id INT,
    product_name VARCHAR(100),
    amount DECIMAL(10, 2),
    order_time DATETIME
) ENGINE=OLAP
DUPLICATE KEY(order_id)
DISTRIBUTED BY HASH(order_id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);

CREATE TABLE IF NOT EXISTS demo_join_products (
    product_id INT NOT NULL,
    product_name VARCHAR(100),
    category VARCHAR(50),
    price DECIMAL(10, 2)
) ENGINE=OLAP
DUPLICATE KEY(product_id)
DISTRIBUTED BY HASH(product_id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_join_users VALUES
(1, '张三', '北京', 28),
(2, '李四', '上海', 35),
(3, '王五', '广州', 30),
(4, '赵六', '深圳', 25);

INSERT INTO demo_join_orders VALUES
(101, 1, 'iPhone', 5999.00, '2024-01-01 10:00:00'),
(102, 1, 'MacBook', 12999.00, '2024-01-02 11:00:00'),
(103, 2, 'iPad', 4999.00, '2024-01-01 12:00:00'),
(104, 3, 'iPhone', 5999.00, '2024-01-03 13:00:00'),
(105, 5, 'AirPods', 1299.00, '2024-01-04 14:00:00');

INSERT INTO demo_join_products VALUES
(1, 'iPhone', '手机', 5999.00),
(2, 'MacBook', '电脑', 12999.00),
(3, 'iPad', '平板', 4999.00),
(4, 'AirPods', '配件', 1299.00),
(5, 'Apple Watch', '配件', 2999.00);

-- =====================================================
-- 2. INNER JOIN（内连接）
-- =====================================================

SELECT 
    u.user_id,
    u.username,
    o.order_id,
    o.product_name,
    o.amount
FROM demo_join_users u
INNER JOIN demo_join_orders o ON u.user_id = o.user_id
ORDER BY u.user_id, o.order_id;

-- =====================================================
-- 3. LEFT OUTER JOIN（左外连接）
-- =====================================================

SELECT 
    u.user_id,
    u.username,
    o.order_id,
    o.product_name,
    o.amount
FROM demo_join_users u
LEFT JOIN demo_join_orders o ON u.user_id = o.user_id
ORDER BY u.user_id, o.order_id;

-- =====================================================
-- 4. RIGHT OUTER JOIN（右外连接）
-- =====================================================

SELECT 
    u.user_id,
    u.username,
    o.order_id,
    o.product_name,
    o.amount
FROM demo_join_users u
RIGHT JOIN demo_join_orders o ON u.user_id = o.user_id
ORDER BY u.user_id, o.order_id;

-- =====================================================
-- 5. FULL OUTER JOIN（全外连接）
-- =====================================================

SELECT 
    u.user_id,
    u.username,
    o.order_id,
    o.product_name,
    o.amount
FROM demo_join_users u
FULL JOIN demo_join_orders o ON u.user_id = o.user_id
ORDER BY u.user_id, o.order_id;

-- =====================================================
-- 6. CROSS JOIN（交叉连接）
-- =====================================================

SELECT 
    u.username,
    p.product_name
FROM demo_join_users u
CROSS JOIN demo_join_products p
ORDER BY u.username, p.product_name
LIMIT 10;

-- =====================================================
-- 7. LEFT SEMI JOIN（左半连接）
-- 只返回左表中在右表有匹配的行
-- =====================================================

SELECT 
    u.user_id,
    u.username,
    u.city
FROM demo_join_users u
LEFT SEMI JOIN demo_join_orders o ON u.user_id = o.user_id
ORDER BY u.user_id;

-- =====================================================
-- 8. LEFT ANTI JOIN（左反连接）
-- 只返回左表中在右表没有匹配的行
-- =====================================================

SELECT 
    u.user_id,
    u.username,
    u.city
FROM demo_join_users u
LEFT ANTI JOIN demo_join_orders o ON u.user_id = o.user_id
ORDER BY u.user_id;

-- =====================================================
-- 9. 多表 JOIN
-- =====================================================

SELECT 
    u.username,
    o.product_name,
    p.category,
    o.amount
FROM demo_join_users u
INNER JOIN demo_join_orders o ON u.user_id = o.user_id
INNER JOIN demo_join_products p ON o.product_name = p.product_name
ORDER BY u.username, o.order_id;

-- =====================================================
-- 10. 自连接（Self Join）
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_join_employees (
    emp_id INT NOT NULL,
    emp_name VARCHAR(50),
    manager_id INT
) ENGINE=OLAP
DUPLICATE KEY(emp_id)
DISTRIBUTED BY HASH(emp_id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_join_employees VALUES
(1, '张三', NULL),
(2, '李四', 1),
(3, '王五', 1),
(4, '赵六', 2);

SELECT 
    e.emp_name AS employee,
    m.emp_name AS manager
FROM demo_join_employees e
LEFT JOIN demo_join_employees m ON e.manager_id = m.emp_id
ORDER BY e.emp_id;

-- =====================================================
-- 11. Colocate Join（同分布Join）
-- 相同分布的表可以直接本地Join，无需网络传输
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_colocate_table1 (
    user_id INT NOT NULL,
    data1 VARCHAR(100)
) ENGINE=OLAP
DUPLICATE KEY(user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1",
    "colocate_with" = "group1"
);

CREATE TABLE IF NOT EXISTS demo_colocate_table2 (
    user_id INT NOT NULL,
    data2 VARCHAR(100)
) ENGINE=OLAP
DUPLICATE KEY(user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1",
    "colocate_with" = "group1"
);

INSERT INTO demo_colocate_table1 VALUES
(1, 'data1_user1'), (2, 'data1_user2'), (3, 'data1_user3');

INSERT INTO demo_colocate_table2 VALUES
(1, 'data2_user1'), (2, 'data2_user2'), (4, 'data2_user4');

SELECT 
    t1.user_id,
    t1.data1,
    t2.data2
FROM demo_colocate_table1 t1
LEFT JOIN demo_colocate_table2 t2 ON t1.user_id = t2.user_id
ORDER BY t1.user_id;

EXPLAIN SELECT 
    t1.user_id,
    t1.data1,
    t2.data2
FROM demo_colocate_table1 t1
LEFT JOIN demo_colocate_table2 t2 ON t1.user_id = t2.user_id;

-- =====================================================
-- 12. Bucket Shuffle Join
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_bucket_table1 (
    id INT NOT NULL,
    name VARCHAR(50)
) ENGINE=OLAP
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 5
PROPERTIES (
    "replication_num" = "1"
);

CREATE TABLE IF NOT EXISTS demo_bucket_table2 (
    id INT NOT NULL,
    value INT
) ENGINE=OLAP
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 5
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_bucket_table1 VALUES (1, 'a'), (2, 'b'), (3, 'c');
INSERT INTO demo_bucket_table2 VALUES (1, 100), (2, 200), (3, 300);

EXPLAIN SELECT 
    t1.id,
    t1.name,
    t2.value
FROM demo_bucket_table1 t1
INNER JOIN demo_bucket_table2 t2 ON t1.id = t2.id;

-- =====================================================
-- 13. Broadcast Join vs Shuffle Join
-- =====================================================

-- 强制使用 Broadcast Join（适合小表）
SELECT /*+ SET_VAR(enable_broadcast_join=true) */
    u.user_id,
    u.username,
    o.order_id
FROM demo_join_users u
LEFT JOIN demo_join_orders o ON u.user_id = o.user_id;

-- 强制使用 Shuffle Join（适合大表）
SELECT /*+ SET_VAR(enable_broadcast_join=false) */
    u.user_id,
    u.username,
    o.order_id
FROM demo_join_users u
LEFT JOIN demo_join_orders o ON u.user_id = o.user_id;

-- =====================================================
-- 14. JOIN 优化建议
-- =====================================================

SELECT 
    'Broadcast Join' AS join_type,
    '小表Join大表' AS best_for,
    '小表广播到所有节点' AS mechanism,
    '小表数据量<100MB' AS recommendation
UNION ALL
SELECT 
    'Shuffle Join',
    '大表Join大表',
    '按Join Key重新分布',
    '数据量都很大时'
UNION ALL
SELECT 
    'Colocate Join',
    '频繁Join的表',
    '相同分布，本地Join',
    '建表时设置colocate_with'
UNION ALL
SELECT 
    'Bucket Shuffle Join',
    '相同分桶数的表',
    '利用分桶信息',
    '分桶列与Join列相同';

-- =====================================================
-- 15. 清理演示表
-- =====================================================

DROP TABLE IF EXISTS demo_join_users;
DROP TABLE IF EXISTS demo_join_orders;
DROP TABLE IF EXISTS demo_join_products;
DROP TABLE IF EXISTS demo_join_employees;
DROP TABLE IF EXISTS demo_colocate_table1;
DROP TABLE IF EXISTS demo_colocate_table2;
DROP TABLE IF EXISTS demo_bucket_table1;
DROP TABLE IF EXISTS demo_bucket_table2;
