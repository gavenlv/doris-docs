-- =====================================================
-- 第19章：备份与恢复
-- 演示 Snapshot/Backup/Restore、灾备方案、跨集群迁移
-- 所需权限：ADMIN 或 REPOSITORY 相关权限
-- =====================================================

USE tutorial;

-- =====================================================
-- 1. 准备测试数据
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_backup_table (
    id INT NOT NULL,
    name VARCHAR(50),
    value INT,
    create_time DATETIME
) ENGINE=OLAP
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_backup_table VALUES
(1, '数据1', 100, '2024-01-01 10:00:00'),
(2, '数据2', 200, '2024-01-02 11:00:00'),
(3, '数据3', 300, '2024-01-03 12:00:00');

SELECT * FROM demo_backup_table;

-- =====================================================
-- 2. 创建 Repository（备份仓库）
-- =====================================================

-- 创建本地仓库（用于测试）
CREATE REPOSITORY IF NOT EXISTS demo_backup_repo
WITH BROKER broker_name
ON LOCATION "file:///tmp/doris_backup"
PROPERTIES (
    "username" = ""
);

-- 创建 HDFS 仓库
-- CREATE REPOSITORY IF NOT EXISTS hdfs_backup_repo
-- WITH BROKER broker_name
-- ON LOCATION "hdfs://namenode:8020/doris_backup"
-- PROPERTIES (
--     "username" = "hdfs_user",
--     "password" = "hdfs_password"
-- );

-- 创建 S3 仓库
-- CREATE REPOSITORY IF NOT EXISTS s3_backup_repo
-- WITH BROKER broker_name
-- ON LOCATION "s3://bucket/doris_backup"
-- PROPERTIES (
--     "AWS_ACCESS_KEY" = "your_access_key",
--     "AWS_SECRET_KEY" = "your_secret_key",
--     "AWS_ENDPOINT" = "s3.amazonaws.com"
-- );

SHOW REPOSITORIES;

-- =====================================================
-- 3. 数据备份
-- =====================================================

-- 备份单个表
BACKUP SNAPSHOT demo_backup_snapshot_1
TO demo_backup_repo
ON (demo_backup_table)
PROPERTIES (
    "type" = "full",
    "timeout" = "3600"
);

-- 查看备份任务状态
SHOW BACKUP;

-- 备份多个表
CREATE TABLE IF NOT EXISTS demo_backup_table2 (
    id INT,
    data VARCHAR(100)
) ENGINE=OLAP
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_backup_table2 VALUES (1, 'test'), (2, 'test2');

BACKUP SNAPSHOT demo_backup_snapshot_2
TO demo_backup_repo
ON (demo_backup_table, demo_backup_table2)
PROPERTIES (
    "type" = "full"
);

SHOW BACKUP;

-- 备份整个数据库
-- BACKUP SNAPSHOT db_backup_snapshot
-- TO demo_backup_repo
-- PROPERTIES (
--     "type" = "full"
-- );

-- =====================================================
-- 4. 查看备份快照
-- =====================================================

SHOW SNAPSHOT ON demo_backup_repo;

SHOW SNAPSHOT ON demo_backup_repo WHERE SNAPSHOT = 'demo_backup_snapshot_1';

-- =====================================================
-- 5. 数据恢复
-- =====================================================

-- 模拟数据丢失
DROP TABLE IF EXISTS demo_backup_table;

SHOW TABLES LIKE 'demo_backup%';

-- 从备份恢复
RESTORE SNAPSHOT demo_backup_snapshot_1
FROM demo_backup_repo
PROPERTIES (
    "backup_timestamp" = "2024-01-01-00-00-00",
    "replication_num" = "1",
    "timeout" = "3600"
);

-- 查看恢复任务状态
SHOW RESTORE;

-- 验证恢复结果
SELECT * FROM demo_backup_table;

-- 恢复到新表名
RESTORE SNAPSHOT demo_backup_snapshot_1
FROM demo_backup_repo
ON (demo_backup_table AS demo_backup_table_restored)
PROPERTIES (
    "backup_timestamp" = "2024-01-01-00-00-00"
);

SHOW RESTORE;

SELECT * FROM demo_backup_table_restored;

-- =====================================================
-- 6. 增量备份
-- =====================================================

INSERT INTO demo_backup_table VALUES
(4, '数据4', 400, '2024-01-04 13:00:00'),
(5, '数据5', 500, '2024-01-05 14:00:00');

BACKUP SNAPSHOT demo_backup_snapshot_incr_1
TO demo_backup_repo
ON (demo_backup_table)
PROPERTIES (
    "type" = "incremental",
    "base_snapshot" = "demo_backup_snapshot_1"
);

SHOW BACKUP;

-- =====================================================
-- 7. 备份策略
-- =====================================================

-- 定期全量备份
-- CREATE ROUTINE LOAD backup_schedule
-- ... (通过外部调度工具实现)

-- 备份保留策略
-- 建议保留策略：
-- - 日备份保留7天
-- - 周备份保留4周
-- - 月备份保留12个月

-- =====================================================
-- 8. 跨集群迁移
-- =====================================================

-- 在目标集群创建相同的 Repository
-- CREATE REPOSITORY demo_backup_repo
-- WITH BROKER broker_name
-- ON LOCATION "hdfs://namenode:8020/doris_backup"
-- PROPERTIES (
--     "username" = "hdfs_user",
--     "password" = "hdfs_password"
-- );

-- 在目标集群恢复数据
-- RESTORE SNAPSHOT demo_backup_snapshot_1
-- FROM demo_backup_repo
-- PROPERTIES (
--     "backup_timestamp" = "2024-01-01-00-00-00"
-- );

-- =====================================================
-- 9. 备份恢复最佳实践
-- =====================================================

SELECT 
    '定期全量备份' AS practice,
    '每周一次全量备份' AS recommendation,
    '确保数据安全' AS purpose
UNION ALL
SELECT 
    '增量备份',
    '每日增量备份',
    '减少备份时间和存储'
UNION ALL
SELECT 
    '异地备份',
    '备份数据存储到异地',
    '防止灾难性故障'
UNION ALL
SELECT 
    '定期恢复测试',
    '每月测试恢复流程',
    '确保备份可用'
UNION ALL
SELECT 
    '备份验证',
    '备份后验证数据完整性',
    '确保备份有效';

-- =====================================================
-- 10. 备份监控
-- =====================================================

-- 查看备份历史
SHOW BACKUP;

-- 查看恢复历史
SHOW RESTORE;

-- 查看仓库信息
SHOW REPOSITORIES;

-- =====================================================
-- 11. 清理演示资源
-- =====================================================

DROP SNAPSHOT IF EXISTS demo_backup_snapshot_1 ON demo_backup_repo;
DROP SNAPSHOT IF EXISTS demo_backup_snapshot_2 ON demo_backup_repo;
DROP SNAPSHOT IF EXISTS demo_backup_snapshot_incr_1 ON demo_backup_repo;

DROP REPOSITORY IF EXISTS demo_backup_repo;

DROP TABLE IF EXISTS demo_backup_table;
DROP TABLE IF EXISTS demo_backup_table2;
DROP TABLE IF EXISTS demo_backup_table_restored;
