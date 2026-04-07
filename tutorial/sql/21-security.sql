-- =====================================================
-- 第21章：用户权限与安全
-- 演示 RBAC、角色继承、行级列级权限、LDAP、数据脱敏
-- 所需权限：ADMIN 或 GRANT_PRIV
-- =====================================================

USE tutorial;

-- =====================================================
-- 1. 用户管理
-- =====================================================

-- 创建用户
CREATE USER IF NOT EXISTS 'user_readonly'@'%' IDENTIFIED BY 'ReadOnly@123';

CREATE USER IF NOT EXISTS 'user_writer'@'%' IDENTIFIED BY 'Writer@123';

CREATE USER IF NOT EXISTS 'user_admin'@'%' IDENTIFIED BY 'Admin@123';

-- 查看用户
SHOW USERS;

-- 修改用户密码
ALTER USER 'user_readonly'@'%' IDENTIFIED BY 'NewPassword@123';

-- 删除用户
-- DROP USER IF EXISTS 'user_test'@'%';

-- =====================================================
-- 2. 角色管理（RBAC）
-- =====================================================

-- 创建角色
CREATE ROLE IF NOT EXISTS role_readonly;

CREATE ROLE IF NOT EXISTS role_writer;

CREATE ROLE IF NOT EXISTS role_admin;

-- 查看角色
SHOW ROLES;

-- 删除角色
-- DROP ROLE IF EXISTS role_test;

-- =====================================================
-- 3. 权限授予
-- =====================================================

-- 授予角色权限
GRANT SELECT_PRIV ON *.* TO ROLE role_readonly;

GRANT SELECT_PRIV, INSERT_PRIV, UPDATE_PRIV, DELETE_PRIV ON *.* TO ROLE role_writer;

GRANT ALL PRIVILEGES ON *.* TO ROLE role_admin;

-- 将角色授予用户
GRANT role_readonly TO 'user_readonly'@'%';

GRANT role_writer TO 'user_writer'@'%';

GRANT role_admin TO 'user_admin'@'%';

-- 查看用户权限
SHOW GRANTS FOR 'user_readonly'@'%';

SHOW GRANTS FOR 'user_writer'@'%';

SHOW GRANTS FOR 'user_admin'@'%';

-- =====================================================
-- 4. 数据库级权限
-- =====================================================

-- 创建测试数据库
CREATE DATABASE IF NOT EXISTS demo_security_db;

-- 授予数据库级权限
GRANT SELECT_PRIV ON demo_security_db.* TO 'user_readonly'@'%';

GRANT ALL PRIVILEGES ON demo_security_db.* TO 'user_writer'@'%';

SHOW GRANTS FOR 'user_readonly'@'%';

-- =====================================================
-- 5. 表级权限
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_security_db.sensitive_table (
    id INT,
    name VARCHAR(50),
    salary DECIMAL(10, 2),
    phone VARCHAR(20)
) ENGINE=OLAP
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);

-- 授予表级权限
GRANT SELECT_PRIV ON demo_security_db.sensitive_table TO 'user_readonly'@'%';

SHOW GRANTS FOR 'user_readonly'@'%';

-- =====================================================
-- 6. 列级权限
-- =====================================================

-- 创建只允许访问部分列的用户
CREATE USER IF NOT EXISTS 'user_limited'@'%' IDENTIFIED BY 'Limited@123';

-- 授予特定列的查询权限
GRANT SELECT_PRIV (id, name) ON demo_security_db.sensitive_table TO 'user_limited'@'%';

SHOW GRANTS FOR 'user_limited'@'%';

-- =====================================================
-- 7. 行级权限（Row Policy）
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_security_db.sales_data (
    id INT,
    region VARCHAR(50),
    amount DECIMAL(10, 2),
    sales_person VARCHAR(50)
) ENGINE=OLAP
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_security_db.sales_data VALUES
(1, '北京', 10000.00, '张三'),
(2, '上海', 15000.00, '李四'),
(3, '广州', 8000.00, '王五'),
(4, '北京', 12000.00, '赵六');

-- 创建行级权限策略
CREATE ROW POLICY demo_security_db.policy_beijing_region
ON demo_security_db.sales_data
AS RESTRICTIVE
TO 'user_readonly'@'%'
USING (region = '北京');

SHOW ROW POLICY;

-- =====================================================
-- 8. 角色继承
-- =====================================================

-- 创建父角色
CREATE ROLE IF NOT EXISTS role_base;

GRANT SELECT_PRIV ON demo_security_db.* TO ROLE role_base;

-- 创建子角色继承父角色
CREATE ROLE IF NOT EXISTS role_extended;

GRANT role_base TO ROLE role_extended;

GRANT INSERT_PRIV ON demo_security_db.* TO ROLE role_extended;

-- 查看角色继承关系
SHOW ROLES;

-- =====================================================
-- 9. 权限撤销
-- =====================================================

-- 撤销用户角色
REVOKE role_readonly FROM 'user_readonly'@'%';

SHOW GRANTS FOR 'user_readonly'@'%';

-- 重新授予
GRANT role_readonly TO 'user_readonly'@'%';

-- 撤销权限
REVOKE SELECT_PRIV ON demo_security_db.* FROM 'user_readonly'@'%';

SHOW GRANTS FOR 'user_readonly'@'%';

-- =====================================================
-- 10. 密码策略
-- =====================================================

-- 设置密码过期时间
SET PASSWORD FOR 'user_readonly'@'%' = PASSWORD('NewPassword@456');

-- 设置密码策略属性
-- ALTER USER 'user_readonly'@'%' 
-- PROPERTIES (
--     "password_expire_interval" = "90",
--     "max_login_attempts" = "5",
--     "lock_time" = "3600"
-- );

-- =====================================================
-- 11. IP 白名单
-- =====================================================

-- 创建限制IP的用户
CREATE USER IF NOT EXISTS 'user_internal'@'192.168.%' IDENTIFIED BY 'Internal@123';

SHOW USERS;

-- =====================================================
-- 12. 数据脱敏
-- =====================================================

CREATE TABLE IF NOT EXISTS demo_security_db.user_info (
    user_id INT,
    username VARCHAR(50),
    phone VARCHAR(20),
    email VARCHAR(100),
    id_card VARCHAR(20)
) ENGINE=OLAP
DUPLICATE KEY(user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO demo_security_db.user_info VALUES
(1, '张三', '13800138000', 'zhangsan@example.com', '110101199001011234'),
(2, '李四', '13900139000', 'lisi@example.com', '110101199002021234');

-- 创建脱敏视图
CREATE VIEW demo_security_db.user_info_masked AS
SELECT 
    user_id,
    username,
    CONCAT(LEFT(phone, 3), '****', RIGHT(phone, 4)) AS phone,
    CONCAT(LEFT(email, 2), '****', SUBSTRING(email, INSTR(email, '@'))) AS email,
    CONCAT(LEFT(id_card, 6), '********', RIGHT(id_card, 4)) AS id_card
FROM demo_security_db.user_info;

SELECT * FROM demo_security_db.user_info_masked;

-- =====================================================
-- 13. 审计日志
-- =====================================================

-- 查看审计日志配置
SHOW VARIABLES LIKE '%audit%';

-- 启用审计日志
-- SET GLOBAL audit_enabled = true;

-- 查看审计日志
-- SHOW AUDIT LOG;

-- =====================================================
-- 14. 权限管理最佳实践
-- =====================================================

SELECT 
    '最小权限原则' AS practice,
    '只授予必要的权限' AS description,
    '降低安全风险' AS benefit
UNION ALL
SELECT 
    '角色管理',
    '通过角色管理权限',
    '简化权限管理'
UNION ALL
SELECT 
    '定期审计',
    '定期检查用户权限',
    '及时发现异常'
UNION ALL
SELECT 
    '密码策略',
    '设置强密码和过期策略',
    '防止密码泄露'
UNION ALL
SELECT 
    'IP限制',
    '限制访问IP范围',
    '减少攻击面';

-- =====================================================
-- 15. 清理演示资源
-- =====================================================

DROP USER IF EXISTS 'user_readonly'@'%';
DROP USER IF EXISTS 'user_writer'@'%';
DROP USER IF EXISTS 'user_admin'@'%';
DROP USER IF EXISTS 'user_limited'@'%';
DROP USER IF EXISTS 'user_internal'@'192.168.%';

DROP ROLE IF EXISTS role_readonly;
DROP ROLE IF EXISTS role_writer;
DROP ROLE IF EXISTS role_admin;
DROP ROLE IF EXISTS role_base;
DROP ROLE IF EXISTS role_extended;

DROP DATABASE IF EXISTS demo_security_db;
