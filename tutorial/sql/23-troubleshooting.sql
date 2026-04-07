-- =====================================================
-- 第23章：故障排查与诊断
-- 演示 OOM/超时/数据不一致/副本异常/Compaction调优
-- 所需权限：ADMIN 或相关诊断权限
-- =====================================================

USE tutorial;

-- =====================================================
-- 1. 查询超时问题排查
-- =====================================================

-- 查看查询超时设置
SHOW VARIABLES LIKE '%timeout%';

-- 设置查询超时时间
SET query_timeout = 600;

-- 查看正在运行的查询
SHOW RUNNING QUERIES;

-- 取消长时间运行的查询
-- CANCEL QUERY WHERE QUERY_ID = 'query_id';

-- 查看慢查询日志
-- SELECT * FROM audit_log WHERE query_time > 10000 ORDER BY timestamp DESC LIMIT 10;

-- =====================================================
-- 2. 内存问题排查
-- =====================================================

-- 查看内存相关配置
SHOW VARIABLES LIKE '%mem%';

-- 设置查询内存限制
SET exec_mem_limit = 4294967296;

-- 查看 BE 内存使用
-- SHOW BACKENDS;

-- 查看内存使用详情
-- SHOW PROCESSLIST;

-- 内存问题解决方案
SELECT 
    'OOM' AS issue,
    '查询内存超限' AS cause,
    '增加exec_mem_limit或优化查询' AS solution
UNION ALL
SELECT 
    '内存泄漏',
    '长时间运行导致内存不释放',
    '重启FE/BE或检查代码'
UNION ALL
SELECT 
    '内存碎片',
    '频繁分配释放导致',
    '定期重启节点';

-- =====================================================
-- 3. 数据不一致排查
-- =====================================================

-- 检查副本一致性
SHOW REPLICA STATUS FROM tutorial.fact_orders;

-- 检查数据校验
-- CHECK TABLE tutorial.fact_orders;

-- 修复数据不一致
-- ADMIN SET REPLICA STATUS PROPERTIES("tablet_id" = "xxx", "backend_id" = "xxx", "status" = "bad");

-- 查看副本分布
SHOW REPLICA DISTRIBUTION FROM tutorial.fact_orders;

-- =====================================================
-- 4. 副本异常排查
-- =====================================================

-- 查看副本状态
SELECT 
    DATABASE_NAME,
    TABLE_NAME,
    REPLICA_COUNT,
    BACKEND_ID,
    STATUS
FROM information_schema.tablet_replicas
WHERE STATUS != 'OK'
LIMIT 20;

-- 查看副本详情
-- SHOW TABLET FROM tutorial.fact_orders;

-- 副本异常处理
SELECT 
    '副本缺失' AS issue,
    '副本数不足' AS cause,
    '添加新副本或修复节点' AS solution
UNION ALL
SELECT 
    '副本损坏',
    '磁盘故障或数据损坏',
    '从其他副本恢复'
UNION ALL
SELECT 
    '副本延迟',
    '同步速度慢',
    '检查网络和磁盘性能';

-- =====================================================
-- 5. Compaction 问题排查
-- =====================================================

-- 查看 Compaction 状态
SHOW TABLET FROM tutorial.fact_orders LIMIT 5;

-- 查看 Compaction 配置
-- SHOW BACKEND CONFIG LIKE '%compaction%';

-- 手动触发 Compaction
-- CUMULATIVE COMPACTION FOR TABLE tutorial.fact_orders;
-- BASE COMPACTION FOR TABLE tutorial.fact_orders;

-- Compaction 调优参数
SELECT 
    'compaction_task_num_per_disk' AS parameter,
    '每个磁盘的Compaction任务数' AS description,
    '默认值: 2' AS default_value,
    '增加可提高Compaction速度' AS tuning
UNION ALL
SELECT 
    'max_cumulative_compaction_num_singleton_deltas',
    '单次Cumulative Compaction的最大segment数',
    '默认值: 1000',
    '增加可减少Compaction频率'
UNION ALL
SELECT 
    'base_compaction_num_cumulative_deltas',
    '触发Base Compaction的Cumulative Compaction次数',
    '默认值: 5',
    '减少可加快Base Compaction'
UNION ALL
SELECT 
    'compaction_thread_num_per_disk',
    '每个磁盘的Compaction线程数',
    '默认值: 4',
    '增加可提高并发Compaction';

-- =====================================================
-- 6. 查询性能问题排查
-- =====================================================

-- 开启 Profile
SET enable_profile = true;

-- 执行查询
SELECT 
    city,
    COUNT(*) AS order_count,
    SUM(amount) AS total_amount
FROM tutorial.fact_orders
GROUP BY city
ORDER BY total_amount DESC;

-- 查看 Profile
SHOW QUERY PROFILE;

-- 分析执行计划
EXPLAIN SELECT 
    city,
    COUNT(*) AS order_count,
    SUM(amount) AS total_amount
FROM tutorial.fact_orders
GROUP BY city;

-- 性能问题常见原因
SELECT 
    '全表扫描' AS issue,
    '缺少索引或分区裁剪' AS cause,
    '添加索引或优化查询条件' AS solution
UNION ALL
SELECT 
    '数据倾斜',
    '分桶不均匀',
    '调整分桶策略'
UNION ALL
SELECT 
    'Join性能差',
    '大表Join或Join顺序不当',
    '使用Colocate Join或调整Join顺序'
UNION ALL
SELECT 
    '聚合性能差',
    '数据量大或聚合函数复杂',
    '使用物化视图或预聚合';

-- =====================================================
-- 7. 导入问题排查
-- =====================================================

-- 查看导入任务状态
SHOW LOAD;

-- 查看导入错误详情
-- SHOW LOAD WARNINGS WHERE LABEL = 'load_label';

-- 导入问题常见原因
SELECT 
    '导入超时' AS issue,
    '数据量大或网络慢' AS cause,
    '增加超时时间或分批导入' AS solution
UNION ALL
SELECT 
    '导入失败',
    '数据格式错误或权限不足',
    '检查数据格式和权限'
UNION ALL
SELECT 
    '导入慢',
    '资源不足或配置不当',
    '调整并发数和批量大小';

-- =====================================================
-- 8. 网络问题排查
-- =====================================================

-- 查看节点间连接状态
-- SHOW BACKENDS;

-- 检查网络延迟
-- PING BE节点

-- 网络问题解决方案
SELECT 
    '连接超时' AS issue,
    '网络不稳定或防火墙' AS cause,
    '检查网络配置和防火墙规则' AS solution
UNION ALL
SELECT 
    '传输慢',
    '带宽不足或网络拥塞',
    '增加带宽或错峰导入';

-- =====================================================
-- 9. 磁盘问题排查
-- =====================================================

-- 查看磁盘使用情况
SELECT 
    BACKEND_ID,
    DISK_NAME,
    TOTAL_CAPACITY / 1024 / 1024 / 1024 AS total_gb,
    DATA_USED_CAPACITY / 1024 / 1024 / 1024 AS used_gb,
    (DATA_USED_CAPACITY / TOTAL_CAPACITY) * 100 AS used_percent
FROM information_schema.be_disks
ORDER BY used_percent DESC;

-- 磁盘问题解决方案
SELECT 
    '磁盘满' AS issue,
    '数据增长过快' AS cause,
    '扩容或清理历史数据' AS solution
UNION ALL
SELECT 
    '磁盘IO高',
    '查询或导入频繁',
    '增加磁盘或优化查询'
UNION ALL
SELECT 
    '磁盘故障',
    '硬件问题',
    '更换磁盘并恢复副本';

-- =====================================================
-- 10. 日志查看
-- =====================================================

-- FE 日志位置
-- ${DORIS_HOME}/fe/log/fe.log
-- ${DORIS_HOME}/fe/log/fe.out

-- BE 日志位置
-- ${DORIS_HOME}/be/log/be.INFO
-- ${DORIS_HOME}/be/log/be.out

-- 查看审计日志
-- SELECT * FROM audit_log ORDER BY timestamp DESC LIMIT 20;

-- =====================================================
-- 11. 常用诊断命令
-- =====================================================

-- 查看集群版本
SELECT VERSION();

-- 查看集群状态
SHOW FRONTENDS;
SHOW BACKENDS;

-- 查看正在执行的任务
SHOW RUNNING QUERIES;
SHOW LOAD;

-- 查看表统计信息
SHOW TABLE STATS tutorial.fact_orders;

-- 查看列统计信息
SHOW COLUMN STATS tutorial.fact_orders;

-- =====================================================
-- 12. 故障排查流程
-- =====================================================

SELECT 
    '1. 确认问题' AS step,
    '了解问题现象和影响范围' AS action
UNION ALL
SELECT 
    '2. 收集信息',
    '查看日志、监控、错误信息'
UNION ALL
SELECT 
    '3. 定位原因',
    '分析日志和监控数据'
UNION ALL
SELECT 
    '4. 制定方案',
    '根据原因制定解决方案'
UNION ALL
SELECT 
    '5. 实施修复',
    '执行修复操作'
UNION ALL
SELECT 
    '6. 验证结果',
    '确认问题已解决'
UNION ALL
SELECT 
    '7. 总结预防',
    '记录问题和预防措施';

-- =====================================================
-- 13. 监控指标
-- =====================================================

-- 关键监控指标
SELECT 
    'CPU使用率' AS metric,
    'BE/FE CPU使用情况' AS description,
    '<80%' AS normal_range
UNION ALL
SELECT 
    '内存使用率',
    'BE/FE内存使用情况',
    '<80%'
UNION ALL
SELECT 
    '磁盘使用率',
    '各磁盘空间使用情况',
    '<85%'
UNION ALL
SELECT 
    '查询延迟',
    '查询响应时间',
    '根据业务需求'
UNION ALL
SELECT 
    '导入延迟',
    '导入任务耗时',
    '根据业务需求'
UNION ALL
SELECT 
    '副本状态',
    '副本健康状态',
    '100% OK';

-- =====================================================
-- 14. 清理演示资源
-- =====================================================

SET enable_profile = false;
