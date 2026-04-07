-- =====================================================
-- 第13章：窗口函数与高级分析
-- 演示 Window/CTE/子查询、漏斗/留存/路径分析
-- 所需权限：SELECT_PRIV ON tutorial
-- =====================================================

USE tutorial;

-- =====================================================
-- 1. 准备测试数据
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_window_sales (
    sale_id INT NOT NULL,
    employee_id INT,
    employee_name VARCHAR(50),
    department VARCHAR(50),
    sale_amount DECIMAL(10, 2),
    sale_date DATE
) ENGINE=OLAP
DUPLICATE KEY(sale_id)
DISTRIBUTED BY HASH(sale_id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_window_sales VALUES
(1, 101, '张三', '销售一部', 5000.00, '2024-01-01'),
(2, 102, '李四', '销售一部', 6000.00, '2024-01-01'),
(3, 103, '王五', '销售二部', 4500.00, '2024-01-01'),
(4, 101, '张三', '销售一部', 7000.00, '2024-01-02'),
(5, 102, '李四', '销售一部', 5500.00, '2024-01-02'),
(6, 104, '赵六', '销售二部', 8000.00, '2024-01-02'),
(7, 103, '王五', '销售二部', 6000.00, '2024-01-03'),
(8, 104, '赵六', '销售二部', 7500.00, '2024-01-03');

-- =====================================================
-- 2. ROW_NUMBER() - 行号
-- =====================================================

SELECT 
    employee_name,
    sale_amount,
    sale_date,
    ROW_NUMBER() OVER (ORDER BY sale_amount DESC) AS row_num,
    ROW_NUMBER() OVER (PARTITION BY department ORDER BY sale_amount DESC) AS dept_row_num
FROM demo_window_sales
ORDER BY sale_amount DESC;

-- =====================================================
-- 3. RANK() 和 DENSE_RANK() - 排名
-- =====================================================

SELECT 
    employee_name,
    department,
    sale_amount,
    RANK() OVER (ORDER BY sale_amount DESC) AS rank_num,
    DENSE_RANK() OVER (ORDER BY sale_amount DESC) AS dense_rank_num,
    ROW_NUMBER() OVER (ORDER BY sale_amount DESC) AS row_num
FROM demo_window_sales
ORDER BY sale_amount DESC;

-- =====================================================
-- 4. 聚合窗口函数
-- =====================================================

SELECT 
    employee_name,
    sale_date,
    sale_amount,
    SUM(sale_amount) OVER (PARTITION BY employee_name) AS emp_total,
    SUM(sale_amount) OVER (PARTITION BY employee_name ORDER BY sale_date) AS emp_running_total,
    AVG(sale_amount) OVER (PARTITION BY department) AS dept_avg,
    COUNT(*) OVER (PARTITION BY department) AS dept_count
FROM demo_window_sales
ORDER BY employee_name, sale_date;

-- =====================================================
-- 5. 移动窗口
-- =====================================================

SELECT 
    employee_name,
    sale_date,
    sale_amount,
    AVG(sale_amount) OVER (
        ORDER BY sale_date 
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS moving_avg_3,
    SUM(sale_amount) OVER (
        ORDER BY sale_date 
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS running_total,
    MAX(sale_amount) OVER (
        ORDER BY sale_date 
        ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING
    ) AS local_max
FROM demo_window_sales
ORDER BY sale_date, employee_name;

-- =====================================================
-- 6. LAG 和 LEAD - 前后行访问
-- =====================================================

SELECT 
    employee_name,
    sale_date,
    sale_amount,
    LAG(sale_amount, 1) OVER (PARTITION BY employee_name ORDER BY sale_date) AS prev_amount,
    LEAD(sale_amount, 1) OVER (PARTITION BY employee_name ORDER BY sale_date) AS next_amount,
    sale_amount - LAG(sale_amount, 1, 0) OVER (PARTITION BY employee_name ORDER BY sale_date) AS amount_change
FROM demo_window_sales
ORDER BY employee_name, sale_date;

-- =====================================================
-- 7. FIRST_VALUE 和 LAST_VALUE
-- =====================================================

SELECT 
    employee_name,
    sale_date,
    sale_amount,
    FIRST_VALUE(sale_amount) OVER (PARTITION BY employee_name ORDER BY sale_date) AS first_sale,
    LAST_VALUE(sale_amount) OVER (
        PARTITION BY employee_name 
        ORDER BY sale_date 
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS last_sale
FROM demo_window_sales
ORDER BY employee_name, sale_date;

-- =====================================================
-- 8. NTILE - 分桶
-- =====================================================

SELECT 
    employee_name,
    sale_amount,
    NTILE(4) OVER (ORDER BY sale_amount DESC) AS quartile
FROM demo_window_sales
ORDER BY sale_amount DESC;

-- =====================================================
-- 9. CTE (Common Table Expression)
-- =====================================================

WITH emp_stats AS (
    SELECT 
        employee_id,
        employee_name,
        department,
        SUM(sale_amount) AS total_sales,
        COUNT(*) AS sale_count
    FROM demo_window_sales
    GROUP BY employee_id, employee_name, department
),
dept_stats AS (
    SELECT 
        department,
        AVG(total_sales) AS dept_avg_sales
    FROM emp_stats
    GROUP BY department
)
SELECT 
    e.employee_name,
    e.department,
    e.total_sales,
    d.dept_avg_sales,
    e.total_sales - d.dept_avg_sales AS diff_from_avg
FROM emp_stats e
JOIN dept_stats d ON e.department = d.department
ORDER BY e.department, e.total_sales DESC;

-- =====================================================
-- 10. 子查询
-- =====================================================

SELECT 
    employee_name,
    sale_amount,
    department
FROM demo_window_sales s1
WHERE sale_amount > (
    SELECT AVG(sale_amount)
    FROM demo_window_sales s2
    WHERE s2.department = s1.department
)
ORDER BY sale_amount DESC;

-- =====================================================
-- 11. 漏斗分析
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_funnel_events (
    user_id INT,
    event_time DATETIME,
    event_type VARCHAR(20)
) ENGINE=OLAP
DUPLICATE KEY(user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_funnel_events VALUES
(1001, '2024-01-01 10:00:00', 'view_home'),
(1001, '2024-01-01 10:05:00', 'view_product'),
(1001, '2024-01-01 10:10:00', 'add_cart'),
(1001, '2024-01-01 10:15:00', 'submit_order'),
(1002, '2024-01-01 11:00:00', 'view_home'),
(1002, '2024-01-01 11:05:00', 'view_product'),
(1002, '2024-01-01 11:10:00', 'add_cart'),
(1003, '2024-01-01 12:00:00', 'view_home'),
(1003, '2024-01-01 12:05:00', 'view_product'),
(1004, '2024-01-01 13:00:00', 'view_home');

SELECT 
    window_funnel(
        3600,
        'default',
        event_time,
        event_type = 'view_home',
        event_type = 'view_product',
        event_type = 'add_cart',
        event_type = 'submit_order'
    ) AS funnel_level
FROM demo_funnel_events
GROUP BY user_id
ORDER BY user_id;

-- =====================================================
-- 12. 留存分析
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_retention_users (
    user_id INT,
    login_date DATE
) ENGINE=OLAP
DUPLICATE KEY(user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_retention_users VALUES
(1001, '2024-01-01'),
(1001, '2024-01-02'),
(1001, '2024-01-03'),
(1001, '2024-01-07'),
(1002, '2024-01-01'),
(1002, '2024-01-02'),
(1002, '2024-01-04'),
(1003, '2024-01-01'),
(1003, '2024-01-03'),
(1004, '2024-01-01'),
(1004, '2024-01-08');

WITH first_login AS (
    SELECT 
        user_id,
        MIN(login_date) AS first_date
    FROM demo_retention_users
    GROUP BY user_id
),
retention_data AS (
    SELECT 
        f.first_date,
        DATEDIFF(r.login_date, f.first_date) AS days_diff
    FROM demo_retention_users r
    JOIN first_login f ON r.user_id = f.user_id
)
SELECT 
    first_date,
    COUNT(DISTINCT CASE WHEN days_diff = 0 THEN user_id END) AS day0,
    COUNT(DISTINCT CASE WHEN days_diff = 1 THEN user_id END) AS day1,
    COUNT(DISTINCT CASE WHEN days_diff = 3 THEN user_id END) AS day3,
    COUNT(DISTINCT CASE WHEN days_diff = 7 THEN user_id END) AS day7
FROM (
    SELECT 
        f.first_date,
        r.user_id,
        DATEDIFF(r.login_date, f.first_date) AS days_diff
    FROM demo_retention_users r
    JOIN first_login f ON r.user_id = f.user_id
) t
GROUP BY first_date
ORDER BY first_date;

-- =====================================================
-- 13. 路径分析
-- =====================================================

SELECT 
    user_id,
    GROUP_CONCAT(event_type ORDER BY event_time SEPARATOR ' -> ') AS event_path
FROM demo_funnel_events
GROUP BY user_id
ORDER BY user_id;

-- =====================================================
-- 14. 同比环比分析
-- =====================================================

WITH daily_sales AS (
    SELECT 
        sale_date,
        SUM(sale_amount) AS daily_total
    FROM demo_window_sales
    GROUP BY sale_date
)
SELECT 
    sale_date,
    daily_total,
    LAG(daily_total, 1) OVER (ORDER BY sale_date) AS prev_day,
    LAG(daily_total, 7) OVER (ORDER BY sale_date) AS prev_week,
    ROUND((daily_total - LAG(daily_total, 1) OVER (ORDER BY sale_date)) / 
          LAG(daily_total, 1) OVER (ORDER BY sale_date) * 100, 2) AS day_over_day,
    ROUND((daily_total - LAG(daily_total, 7) OVER (ORDER BY sale_date)) / 
          LAG(daily_total, 7) OVER (ORDER BY sale_date) * 100, 2) AS week_over_week
FROM daily_sales
ORDER BY sale_date;

-- =====================================================
-- 15. 清理演示表
-- =====================================================

DROP TABLE IF EXISTS demo_window_sales;
DROP TABLE IF EXISTS demo_funnel_events;
DROP TABLE IF EXISTS demo_retention_users;
