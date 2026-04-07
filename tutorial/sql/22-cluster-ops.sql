-- =====================================================
-- 第22章：集群管理与运维
-- 演示扩缩容、升级、Rebalance、存算分离、多集群
-- 所需权限：ADMIN 或 NODE_PRIV
-- =====================================================

USE tutorial;

-- =====================================================
-- 1. 查看集群状态
-- =====================================================

-- 查看 FE 节点
SHOW FRONTENDS;

-- 查看 BE 节点
SHOW BACKENDS;

-- 查看 Broker 节点
SHOW BROKER;

-- 查看集群概览
SHOW TABLET FROM tutorial.fact_orders LIMIT 10;

-- =====================================================
-- 2. BE 节点管理
-- =====================================================

-- 添加 BE 节点
-- ALTER SYSTEM ADD BACKEND "be_host1:9050";

-- 添加多个 BE 节点
-- ALTER SYSTEM ADD BACKEND "be_host1:9050", "be_host2:9050", "be_host3:9050";

-- 下线 BE 节点（软删除，数据会迁移）
-- ALTER SYSTEM DECOMMISSION BACKEND "be_host:9050";

-- 删除 BE 节点（硬删除，不迁移数据）
-- ALTER SYSTEM DROP BACKEND "be_host:9050";

-- 查看节点状态
-- SHOW BACKENDS;

-- =====================================================
-- 3. FE 节点管理
-- =====================================================

-- 添加 FE Follower 节点
-- ALTER SYSTEM ADD FOLLOWER "fe_host1:9010";

-- 添加 FE Observer 节点
-- ALTER SYSTEM ADD OBSERVER "fe_host2:9010";

-- 删除 FE 节点
-- ALTER SYSTEM DROP FOLLOWER "fe_host1:9010";

-- 查看节点状态
-- SHOW FRONTENDS;

-- =====================================================
-- 4. 数据均衡（Rebalance）
-- =====================================================

-- 查看副本状态
SHOW REPLICA STATUS FROM tutorial.fact_orders;

-- 查看副本分布
SHOW REPLICA DISTRIBUTION FROM tutorial.fact_orders;

-- 手动触发副本均衡
-- BALANCE TABLET FROM tutorial.fact_orders;

-- 查看均衡任务
-- SHOW BALANCER;

-- 取消均衡任务
-- CANCEL BALANCE;

-- =====================================================
-- 5. 副本修复
-- =====================================================

-- 查看副本状态
SHOW REPLICA STATUS FROM tutorial.fact_orders WHERE STATUS != "OK";

-- 手动修复副本
-- ADMIN SET REPLICA STATUS PROPERTIES("tablet_id" = "10001", "backend_id" = "10002", "status" = "bad");

-- 查看修复进度
-- SHOW REPLICA STATUS;

-- =====================================================
-- 6. 存算分离
-- =====================================================

-- 创建存算分离集群
-- CREATE COMPUTE GROUP IF NOT EXISTS compute_group_1
-- PROPERTIES (
--     "be_node_list" = "be_host1:9050,be_host2:9050"
-- );

-- 查看计算组
-- SHOW COMPUTE GROUPS;

-- 使用计算组
-- USE COMPUTE GROUP compute_group_1;

-- 删除计算组
-- DROP COMPUTE GROUP IF EXISTS compute_group_1;

-- =====================================================
-- 7. 多集群管理
-- =====================================================

-- 创建多集群表（跨集群复制）
-- CREATE TABLE tutorial.multi_cluster_table (
--     id INT,
--     name VARCHAR(50)
-- ) ENGINE=OLAP
-- DUPLICATE KEY(id)
-- DISTRIBUTED BY HASH(id) BUCKETS 3
-- PROPERTIES (
--     "replication_num" = "3",
--     "replica_allocation" = "tag.location.default:2,tag.location.remote:1"
-- );

-- =====================================================
-- 8. 节点标签管理
-- =====================================================

-- 为 BE 节点添加标签
-- ALTER SYSTEM MODIFY BACKEND "be_host:9050" ADD TAGS ("location" = "group_a");

-- 查看节点标签
-- SHOW BACKENDS;

-- 创建带标签的表
-- CREATE TABLE tutorial.tagged_table (
--     id INT,
--     data VARCHAR(100)
-- ) ENGINE=OLAP
-- DUPLICATE KEY(id)
-- DISTRIBUTED BY HASH(id) BUCKETS 3
-- PROPERTIES (
--     "replication_num" = "3",
--     "replica_allocation" = "tag.location.group_a:2,tag.location.group_b:1"
-- );

-- =====================================================
-- 9. 集群配置管理
-- =====================================================

-- 查看 FE 配置
SHOW FRONTEND CONFIG LIKE '%mem%';

-- 查看 BE 配置
-- SHOW BACKEND CONFIG LIKE '%mem%';

-- 修改配置（需要重启生效）
-- ADMIN SET FRONTEND CONFIG ("query_mem_limit" = "2147483648");

-- =====================================================
-- 10. 集群监控
-- =====================================================

-- 查看磁盘使用情况
SHOW BACKENDS;

-- 查看表的数据大小
SHOW DATA FROM tutorial;

-- 查看数据库的数据大小
SHOW DATA;

-- 查看正在进行的任务
SHOW RUNNING QUERIES;

-- 查看正在进行的导入任务
SHOW LOAD;

-- =====================================================
-- 11. 集群升级
-- =====================================================

-- 升级步骤说明：
-- 1. 查看当前版本
SELECT VERSION();

-- 2. 备份元数据
-- BACKUP SNAPSHOT upgrade_backup TO upgrade_repo;

-- 3. 滚动升级 FE（先升级 Observer，再升级 Follower，最后升级 Master）
-- 4. 滚动升级 BE
-- 5. 验证功能

-- =====================================================
-- 12. 扩缩容最佳实践
-- =====================================================

SELECT 
    '扩容' AS operation,
    '添加新节点后触发Rebalance' AS step,
    '确保数据均匀分布' AS purpose
UNION ALL
SELECT 
    '缩容',
    '使用DECOMMISSION下线节点',
    '安全迁移数据'
UNION ALL
SELECT 
    '升级',
    '滚动升级，逐个节点升级',
    '最小化停机时间'
UNION ALL
SELECT 
    '监控',
    '持续监控集群状态',
    '及时发现异常'
UNION ALL
SELECT 
    '备份',
    '升级前备份元数据',
    '防止升级失败';

-- =====================================================
-- 13. 集群健康检查
-- =====================================================

-- 检查 FE 状态
SHOW FRONTENDS\G

-- 检查 BE 状态
SHOW BACKENDS\G

-- 检查副本状态
SELECT 
    DATABASE_NAME,
    TABLE_NAME,
    COUNT(*) AS total_replicas,
    SUM(CASE WHEN STATUS = 'OK' THEN 1 ELSE 0 END) AS ok_replicas,
    SUM(CASE WHEN STATUS != 'OK' THEN 1 ELSE 0 END) AS bad_replicas
FROM information_schema.tablet_replicas
GROUP BY DATABASE_NAME, TABLE_NAME
HAVING bad_replicas > 0;

-- 检查磁盘使用率
SELECT 
    BACKEND_ID,
    DISK_NAME,
    TOTAL_CAPACITY / 1024 / 1024 / 1024 AS total_gb,
    DATA_USED_CAPACITY / 1024 / 1024 / 1024 AS used_gb,
    (DATA_USED_CAPACITY / TOTAL_CAPACITY) * 100 AS used_percent
FROM information_schema.be_disks
ORDER BY used_percent DESC;

-- =====================================================
-- 14. 故障恢复
-- =====================================================

-- FE 故障恢复
-- 1. 停止故障 FE
-- 2. 从其他 FE 复制元数据
-- 3. 启动 FE

-- BE 故障恢复
-- 1. 停止故障 BE
-- 2. 修复或替换硬件
-- 3. 启动 BE
-- 4. 等待副本同步

-- =====================================================
-- 15. 清理演示资源
-- =====================================================

-- 本章节主要是管理操作，无需清理
