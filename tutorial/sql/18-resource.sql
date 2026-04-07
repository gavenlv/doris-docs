-- =====================================================
-- 第18章：资源管理与隔离
-- 演示 Workload Group、Resource Group、查询队列、大查询管理
-- 所需权限：ADMIN 或 GRANT_PRIV
-- =====================================================

USE tutorial;

-- =====================================================
-- 1. Workload Group（工作负载组）
-- =====================================================

-- 创建 Workload Group
CREATE WORKLOAD GROUP IF NOT EXISTS wg_high_priority
PROPERTIES (
    "cpu_share" = "20",
    "memory_limit" = "50%",
    "max_concurrency" = "10",
    "max_queue_size" = "20",
    "queue_timeout" = "3000"
);

CREATE WORKLOAD GROUP IF NOT EXISTS wg_low_priority
PROPERTIES (
    "cpu_share" = "5",
    "memory_limit" = "30%",
    "max_concurrency" = "5",
    "max_queue_size" = "10",
    "queue_timeout" = "5000"
);

SHOW WORKLOAD GROUPS;

-- 修改 Workload Group
ALTER WORKLOAD GROUP wg_high_priority PROPERTIES (
    "cpu_share" = "30",
    "memory_limit" = "60%"
);

SHOW WORKLOAD GROUPS;

-- 删除 Workload Group
-- DROP WORKLOAD GROUP IF EXISTS wg_low_priority;

-- =====================================================
-- 2. 使用 Workload Group
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_resource_table (
    id INT NOT NULL,
    name VARCHAR(50),
    value INT
) ENGINE=OLAP
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_resource_table VALUES
(1, 'A', 100), (2, 'B', 200), (3, 'C', 300);

-- 通过 Hint 指定 Workload Group
SELECT /*+ SET_VAR(workload_group=wg_high_priority) */
    COUNT(*)
FROM demo_resource_table;

-- 通过 Session 变量设置
SET workload_group = wg_high_priority;

SELECT COUNT(*) FROM demo_resource_table;

-- =====================================================
-- 3. Workload Group 权限管理
-- =====================================================

-- 创建用户
CREATE USER IF NOT EXISTS 'wg_user'@'%' IDENTIFIED BY 'WgUser@123';

-- 授予 Workload Group 使用权限
GRANT USAGE_PRIV ON WORKLOAD GROUP wg_high_priority TO 'wg_user'@'%';

SHOW GRANTS FOR 'wg_user'@'%';

-- =====================================================
-- 4. 查询队列管理
-- =====================================================

-- 创建带队列的 Workload Group
CREATE WORKLOAD GROUP IF NOT EXISTS wg_queued
PROPERTIES (
    "cpu_share" = "10",
    "memory_limit" = "40%",
    "max_concurrency" = "3",
    "max_queue_size" = "50",
    "queue_timeout" = "60000"
);

SHOW WORKLOAD GROUPS;

-- 查看当前运行的查询
SHOW RUNNING QUERIES;

-- =====================================================
-- 5. 大查询管理
-- =====================================================

-- 设置查询超时时间
SET query_timeout = 300;

-- 设置扫描行数限制
SET scan_limit = 10000000;

-- 查看查询限制相关变量
SHOW VARIABLES LIKE '%timeout%';

SHOW VARIABLES LIKE '%limit%';

-- =====================================================
-- 6. 内存管理
-- =====================================================

-- 设置查询内存限制
SET exec_mem_limit = 2147483648;

-- 查看内存相关变量
SHOW VARIABLES LIKE '%mem%';

-- 查看内存使用情况
SHOW PROCESSLIST;

-- =====================================================
-- 7. CPU 资源隔离
-- =====================================================

-- cpu_share 说明：
-- 值越大，获得的CPU时间片越多
-- 例如：wg_high_priority (cpu_share=30) vs wg_low_priority (cpu_share=10)
-- 高优先级组获得的CPU资源是低优先级组的3倍

SELECT 
    'cpu_share' AS property,
    'CPU时间片分配权重' AS description,
    '值越大优先级越高' AS note
UNION ALL
SELECT 
    'memory_limit',
    '内存使用上限',
    '百分比形式，如50%'
UNION ALL
SELECT 
    'max_concurrency',
    '最大并发查询数',
    '超过限制进入队列'
UNION ALL
SELECT 
    'max_queue_size',
    '队列最大长度',
    '超过限制拒绝查询'
UNION ALL
SELECT 
    'queue_timeout',
    '队列等待超时(ms)',
    '超时返回错误';

-- =====================================================
-- 8. Resource Group（资源组）
-- =====================================================

-- 创建资源组
-- CREATE RESOURCE GROUP IF NOT EXISTS rg_etl
-- PROPERTIES (
--     "workload_groups" = "wg_low_priority",
--     "user_list" = "etl_user"
-- );

-- SHOW RESOURCE GROUPS;

-- =====================================================
-- 9. 查询优先级管理
-- =====================================================

-- 实时查询使用高优先级
SELECT /*+ SET_VAR(workload_group=wg_high_priority) */
    id, name, value
FROM demo_resource_table
WHERE id = 1;

-- ETL 批处理使用低优先级
SELECT /*+ SET_VAR(workload_group=wg_low_priority) */
    COUNT(*) AS total,
    SUM(value) AS sum_value
FROM demo_resource_table;

-- =====================================================
-- 10. 资源监控
-- =====================================================

-- 查看 Workload Group 状态
SHOW WORKLOAD GROUPS;

-- 查看当前会话的 Workload Group
SHOW VARIABLES LIKE 'workload_group';

-- 查看查询统计
-- SHOW QUERY STATISTICS;

-- 查看资源使用情况
-- SHOW RESOURCE USAGE;

-- =====================================================
-- 11. 并发控制
-- =====================================================

-- 设置并发限制
SET parallel_fragment_exec_instance_num = 4;

-- 查看并发设置
SHOW VARIABLES LIKE '%parallel%';

-- =====================================================
-- 12. Workload Group 最佳实践
-- =====================================================

SELECT 
    '实时查询' AS workload_type,
    'wg_high_priority' AS recommended_group,
    '高cpu_share, 高memory_limit' AS config,
    '快速响应，低延迟' AS goal
UNION ALL
SELECT 
    'ETL批处理',
    'wg_low_priority',
    '低cpu_share, 中memory_limit',
    '不影响实时查询'
UNION ALL
SELECT 
    'Ad-hoc查询',
    'wg_normal',
    '中cpu_share, 中memory_limit',
    '平衡性能和资源'
UNION ALL
SELECT 
    '大查询',
    'wg_big_query',
    '低cpu_share, 高memory_limit, 队列控制',
    '避免资源占用过多';

-- =====================================================
-- 13. 清理演示资源
-- =====================================================

DROP WORKLOAD GROUP IF EXISTS wg_high_priority;
DROP WORKLOAD GROUP IF EXISTS wg_low_priority;
DROP WORKLOAD GROUP IF EXISTS wg_queued;
DROP USER IF EXISTS 'wg_user'@'%';
DROP TABLE IF EXISTS demo_resource_table;
