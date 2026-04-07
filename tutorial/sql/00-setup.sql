-- =====================================================
-- Apache Doris 教程 - 初始化脚本
-- 创建示例数据库、维度表、事实表及测试数据
-- 所需权限：ADMIN 或 CREATE PRIVILEGE ON *.*
-- =====================================================

-- 创建教程数据库
CREATE DATABASE IF NOT EXISTS tutorial;

USE tutorial;

-- =====================================================
-- 1. 维度表
-- =====================================================

-- 1.1 用户维度表 (100万用户)
CREATE TABLE IF NOT EXISTS dim_users (
    user_id BIGINT NOT NULL COMMENT '用户ID',
    username VARCHAR(50) COMMENT '用户名',
    gender TINYINT COMMENT '性别: 0-未知, 1-男, 2-女',
    age INT COMMENT '年龄',
    city VARCHAR(50) COMMENT '城市',
    province VARCHAR(50) COMMENT '省份',
    register_date DATE COMMENT '注册日期',
    user_level TINYINT COMMENT '用户等级: 1-普通, 2-银卡, 3-金卡, 4-白金, 5-钻石',
    vip_expire_date DATE COMMENT 'VIP过期日期',
    phone VARCHAR(20) COMMENT '手机号',
    email VARCHAR(100) COMMENT '邮箱'
) ENGINE=OLAP
DUPLICATE KEY(user_id)
COMMENT '用户维度表'
DISTRIBUTED BY HASH(user_id) BUCKETS 10
PROPERTIES (
    "replication_num" = "1"
);

-- 1.2 商品维度表 (10万商品)
CREATE TABLE IF NOT EXISTS dim_products (
    product_id BIGINT NOT NULL COMMENT '商品ID',
    product_name VARCHAR(200) COMMENT '商品名称',
    category_id INT COMMENT '品类ID',
    brand_id INT COMMENT '品牌ID',
    supplier_id INT COMMENT '供应商ID',
    cost_price DECIMAL(10, 2) COMMENT '成本价',
    sale_price DECIMAL(10, 2) COMMENT '销售价',
    market_price DECIMAL(10, 2) COMMENT '市场价',
    stock_qty INT COMMENT '库存数量',
    status TINYINT COMMENT '状态: 0-下架, 1-上架, 2-预售',
    create_time DATETIME COMMENT '创建时间',
    update_time DATETIME COMMENT '更新时间'
) ENGINE=OLAP
DUPLICATE KEY(product_id)
COMMENT '商品维度表'
DISTRIBUTED BY HASH(product_id) BUCKETS 10
PROPERTIES (
    "replication_num" = "1"
);

-- 1.3 门店维度表 (500门店)
CREATE TABLE IF NOT EXISTS dim_stores (
    store_id INT NOT NULL COMMENT '门店ID',
    store_name VARCHAR(100) COMMENT '门店名称',
    store_type TINYINT COMMENT '门店类型: 1-旗舰店, 2-标准店, 3-社区店',
    city VARCHAR(50) COMMENT '城市',
    province VARCHAR(50) COMMENT '省份',
    address VARCHAR(200) COMMENT '详细地址',
    open_date DATE COMMENT '开业日期',
    area_sqm DECIMAL(10, 2) COMMENT '面积(平方米)',
    manager_id BIGINT COMMENT '店长ID',
    phone VARCHAR(20) COMMENT '联系电话',
    status TINYINT COMMENT '状态: 0-关闭, 1-营业中, 2-装修'
) ENGINE=OLAP
DUPLICATE KEY(store_id)
COMMENT '门店维度表'
DISTRIBUTED BY HASH(store_id) BUCKETS 5
PROPERTIES (
    "replication_num" = "1"
);

-- 1.4 品类维度表 (100品类)
CREATE TABLE IF NOT EXISTS dim_categories (
    category_id INT NOT NULL COMMENT '品类ID',
    category_name VARCHAR(50) COMMENT '品类名称',
    parent_category_id INT COMMENT '父品类ID',
    category_level TINYINT COMMENT '品类层级: 1-一级, 2-二级, 3-三级',
    category_path VARCHAR(200) COMMENT '品类路径',
    sort_order INT COMMENT '排序',
    status TINYINT COMMENT '状态: 0-禁用, 1-启用'
) ENGINE=OLAP
DUPLICATE KEY(category_id)
COMMENT '品类维度表'
DISTRIBUTED BY HASH(category_id) BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);

-- =====================================================
-- 2. 事实表
-- =====================================================

-- 2.1 订单事实表 (5000万订单)
CREATE TABLE IF NOT EXISTS fact_orders (
    order_id BIGINT NOT NULL COMMENT '订单ID',
    order_no VARCHAR(50) COMMENT '订单编号',
    user_id BIGINT COMMENT '用户ID',
    store_id INT COMMENT '门店ID',
    order_status TINYINT COMMENT '订单状态: 0-待支付, 1-已支付, 2-已发货, 3-已完成, 4-已取消, 5-已退款',
    payment_status TINYINT COMMENT '支付状态: 0-未支付, 1-已支付, 2-部分退款, 3-全额退款',
    shipping_status TINYINT COMMENT '发货状态: 0-未发货, 1-已发货, 2-已签收',
    total_amount DECIMAL(18, 2) COMMENT '订单总金额',
    discount_amount DECIMAL(18, 2) COMMENT '优惠金额',
    shipping_fee DECIMAL(10, 2) COMMENT '运费',
    payment_amount DECIMAL(18, 2) COMMENT '实付金额',
    payment_method TINYINT COMMENT '支付方式: 1-微信, 2-支付宝, 3-银行卡, 4-货到付款',
    order_time DATETIME COMMENT '下单时间',
    payment_time DATETIME COMMENT '支付时间',
    shipping_time DATETIME COMMENT '发货时间',
    receive_time DATETIME COMMENT '签收时间',
    province VARCHAR(50) COMMENT '收货省份',
    city VARCHAR(50) COMMENT '收货城市',
    district VARCHAR(50) COMMENT '收货区县'
) ENGINE=OLAP
DUPLICATE KEY(order_id)
COMMENT '订单事实表'
PARTITION BY RANGE(order_time) ()
DISTRIBUTED BY HASH(order_id) BUCKETS 20
PROPERTIES (
    "replication_num" = "1",
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-30",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "dynamic_partition.buckets" = "20"
);

-- 2.2 订单明细事实表 (1亿明细)
CREATE TABLE IF NOT EXISTS fact_order_items (
    item_id BIGINT NOT NULL COMMENT '明细ID',
    order_id BIGINT COMMENT '订单ID',
    order_no VARCHAR(50) COMMENT '订单编号',
    product_id BIGINT COMMENT '商品ID',
    sku_id BIGINT COMMENT 'SKU ID',
    product_name VARCHAR(200) COMMENT '商品名称',
    category_id INT COMMENT '品类ID',
    quantity INT COMMENT '数量',
    unit_price DECIMAL(10, 2) COMMENT '单价',
    discount_rate DECIMAL(5, 2) COMMENT '折扣率',
    discount_amount DECIMAL(10, 2) COMMENT '优惠金额',
    item_amount DECIMAL(18, 2) COMMENT '明细金额',
    order_time DATETIME COMMENT '下单时间'
) ENGINE=OLAP
DUPLICATE KEY(item_id)
COMMENT '订单明细事实表'
PARTITION BY RANGE(order_time) ()
DISTRIBUTED BY HASH(order_id) BUCKETS 30
PROPERTIES (
    "replication_num" = "1",
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-30",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "dynamic_partition.buckets" = "30"
);

-- 2.3 页面浏览事实表 (5亿浏览记录)
CREATE TABLE IF NOT EXISTS fact_page_views (
    view_id BIGINT NOT NULL COMMENT '浏览ID',
    user_id BIGINT COMMENT '用户ID',
    session_id VARCHAR(50) COMMENT '会话ID',
    page_type TINYINT COMMENT '页面类型: 1-首页, 2-列表页, 3-详情页, 4-搜索页, 5-活动页',
    page_url VARCHAR(500) COMMENT '页面URL',
    referrer_url VARCHAR(500) COMMENT '来源URL',
    product_id BIGINT COMMENT '商品ID',
    category_id INT COMMENT '品类ID',
    view_time DATETIME COMMENT '浏览时间',
    stay_duration INT COMMENT '停留时长(秒)',
    device_type TINYINT COMMENT '设备类型: 1-iOS, 2-Android, 3-Web, 4-小程序',
    os_type VARCHAR(20) COMMENT '操作系统',
    browser VARCHAR(20) COMMENT '浏览器',
    ip_address VARCHAR(50) COMMENT 'IP地址',
    province VARCHAR(50) COMMENT '省份',
    city VARCHAR(50) COMMENT '城市'
) ENGINE=OLAP
DUPLICATE KEY(view_id)
COMMENT '页面浏览事实表'
PARTITION BY RANGE(view_time) ()
DISTRIBUTED BY HASH(user_id) BUCKETS 50
PROPERTIES (
    "replication_num" = "1",
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-7",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "dynamic_partition.buckets" = "50"
);

-- 2.4 支付记录事实表 (4000万支付记录)
CREATE TABLE IF NOT EXISTS fact_payments (
    payment_id BIGINT NOT NULL COMMENT '支付ID',
    payment_no VARCHAR(50) COMMENT '支付流水号',
    order_id BIGINT COMMENT '订单ID',
    order_no VARCHAR(50) COMMENT '订单编号',
    user_id BIGINT COMMENT '用户ID',
    payment_amount DECIMAL(18, 2) COMMENT '支付金额',
    payment_method TINYINT COMMENT '支付方式: 1-微信, 2-支付宝, 3-银行卡, 4-货到付款',
    payment_status TINYINT COMMENT '支付状态: 0-待支付, 1-支付成功, 2-支付失败, 3-已退款',
    payment_time DATETIME COMMENT '支付时间',
    channel VARCHAR(20) COMMENT '支付渠道',
    third_party_no VARCHAR(100) COMMENT '第三方流水号'
) ENGINE=OLAP
DUPLICATE KEY(payment_id)
COMMENT '支付记录事实表'
PARTITION BY RANGE(payment_time) ()
DISTRIBUTED BY HASH(order_id) BUCKETS 20
PROPERTIES (
    "replication_num" = "1",
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-30",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "dynamic_partition.buckets" = "20"
);

-- =====================================================
-- 3. 插入测试数据
-- =====================================================

-- 3.1 插入品类数据
INSERT INTO dim_categories VALUES
(1, '电子产品', NULL, 1, '电子产品', 1, 1),
(2, '手机通讯', 1, 2, '电子产品 > 手机通讯', 1, 1),
(3, '电脑办公', 1, 2, '电子产品 > 电脑办公', 2, 1),
(4, '服装鞋帽', NULL, 1, '服装鞋帽', 2, 1),
(5, '男装', 4, 2, '服装鞋帽 > 男装', 1, 1),
(6, '女装', 4, 2, '服装鞋帽 > 女装', 2, 1),
(7, '食品饮料', NULL, 1, '食品饮料', 3, 1),
(8, '休闲食品', 7, 2, '食品饮料 > 休闲食品', 1, 1),
(9, '饮料冲调', 7, 2, '食品饮料 > 饮料冲调', 2, 1),
(10, '家居家装', NULL, 1, '家居家装', 4, 1);

-- 3.2 插入门店数据
INSERT INTO dim_stores VALUES
(1, '北京旗舰店', 1, '北京', '北京', '朝阳区建国路88号', '2020-01-01', 5000.00, 1001, '010-12345678', 1),
(2, '上海旗舰店', 1, '上海', '上海', '浦东新区陆家嘴环路100号', '2020-03-15', 4500.00, 1002, '021-87654321', 1),
(3, '广州天河店', 2, '广州', '广东', '天河区天河路200号', '2020-06-01', 2000.00, 1003, '020-11112222', 1),
(4, '深圳南山店', 2, '深圳', '广东', '南山区科技园路50号', '2020-08-20', 1800.00, 1004, '0755-33334444', 1),
(5, '杭州西湖店', 3, '杭州', '浙江', '西湖区文三路100号', '2021-01-10', 1200.00, 1005, '0571-55556666', 1);

-- 3.3 插入用户数据
INSERT INTO dim_users VALUES
(10001, 'user_001', 1, 28, '北京', '北京', '2020-01-15', 3, '2025-12-31', '13800138001', 'user001@example.com'),
(10002, 'user_002', 2, 35, '上海', '上海', '2020-02-20', 4, '2025-06-30', '13800138002', 'user002@example.com'),
(10003, 'user_003', 1, 22, '广州', '广东', '2020-03-10', 2, '2024-03-10', '13800138003', 'user003@example.com'),
(10004, 'user_004', 2, 42, '深圳', '广东', '2020-04-05', 5, '2026-01-01', '13800138004', 'user004@example.com'),
(10005, 'user_005', 1, 31, '杭州', '浙江', '2020-05-12', 3, '2025-09-30', '13800138005', 'user005@example.com');

-- 3.4 插入商品数据
INSERT INTO dim_products VALUES
(100001, 'iPhone 15 Pro Max 256GB', 2, 100, 1001, 7999.00, 9999.00, 10999.00, 500, 1, '2023-09-15 10:00:00', '2024-01-01 12:00:00'),
(100002, 'MacBook Pro 14英寸 M3 Pro', 3, 100, 1002, 12999.00, 16999.00, 18999.00, 200, 1, '2023-11-01 10:00:00', '2024-01-01 12:00:00'),
(100003, '男士商务休闲外套', 5, 200, 1003, 299.00, 599.00, 799.00, 1000, 1, '2023-08-01 10:00:00', '2024-01-01 12:00:00'),
(100004, '女士连衣裙春季新款', 6, 201, 1004, 199.00, 399.00, 599.00, 2000, 1, '2024-02-01 10:00:00', '2024-02-01 12:00:00'),
(100005, '三只松鼠坚果大礼包', 8, 300, 1005, 99.00, 168.00, 199.00, 5000, 1, '2023-06-01 10:00:00', '2024-01-01 12:00:00');

-- 3.5 插入订单数据
INSERT INTO fact_orders VALUES
(1000001, 'ORD202401010001', 10001, 1, 3, 1, 2, 9999.00, 500.00, 0.00, 9499.00, 1, '2024-01-01 10:00:00', '2024-01-01 10:05:00', '2024-01-02 09:00:00', '2024-01-03 14:00:00', '北京', '北京', '朝阳区'),
(1000002, 'ORD202401010002', 10002, 2, 3, 1, 2, 16999.00, 1000.00, 0.00, 15999.00, 2, '2024-01-01 11:00:00', '2024-01-01 11:10:00', '2024-01-02 10:00:00', '2024-01-04 15:00:00', '上海', '上海', '浦东新区'),
(1000003, 'ORD202401010003', 10003, 3, 3, 1, 2, 599.00, 50.00, 10.00, 559.00, 1, '2024-01-01 14:00:00', '2024-01-01 14:05:00', '2024-01-02 14:00:00', '2024-01-03 16:00:00', '广州', '广东', '天河区'),
(1000004, 'ORD202401020001', 10004, 4, 3, 1, 2, 399.00, 40.00, 0.00, 359.00, 1, '2024-01-02 09:00:00', '2024-01-02 09:10:00', '2024-01-03 09:00:00', '2024-01-04 11:00:00', '深圳', '广东', '南山区'),
(1000005, 'ORD202401020002', 10005, 5, 3, 1, 2, 168.00, 18.00, 0.00, 150.00, 2, '2024-01-02 15:00:00', '2024-01-02 15:05:00', '2024-01-03 10:00:00', '2024-01-04 12:00:00', '杭州', '浙江', '西湖区');

-- 3.6 插入订单明细数据
INSERT INTO fact_order_items VALUES
(1, 1000001, 'ORD202401010001', 100001, 100001001, 'iPhone 15 Pro Max 256GB', 2, 1, 9999.00, 5.00, 500.00, 9499.00, '2024-01-01 10:00:00'),
(2, 1000002, 'ORD202401010002', 100002, 100002001, 'MacBook Pro 14英寸 M3 Pro', 3, 1, 16999.00, 5.88, 1000.00, 15999.00, '2024-01-01 11:00:00'),
(3, 1000003, 'ORD202401010003', 100003, 100003001, '男士商务休闲外套', 5, 1, 599.00, 8.35, 50.00, 549.00, '2024-01-01 14:00:00'),
(4, 1000004, 'ORD202401020001', 100004, 100004001, '女士连衣裙春季新款', 6, 1, 399.00, 10.00, 40.00, 359.00, '2024-01-02 09:00:00'),
(5, 1000005, 'ORD202401020002', 100005, 100005001, '三只松鼠坚果大礼包', 8, 1, 168.00, 10.71, 18.00, 150.00, '2024-01-02 15:00:00');

-- 3.7 插入支付记录数据
INSERT INTO fact_payments VALUES
(1, 'PAY202401010001', 1000001, 'ORD202401010001', 10001, 9499.00, 1, 1, '2024-01-01 10:05:00', 'WECHAT', 'WX202401011005001'),
(2, 'PAY202401010002', 1000002, 'ORD202401010002', 10002, 15999.00, 2, 1, '2024-01-01 11:10:00', 'ALIPAY', 'ALI202401011110002'),
(3, 'PAY202401010003', 1000003, 'ORD202401010003', 10003, 559.00, 1, 1, '2024-01-01 14:05:00', 'WECHAT', 'WX202401011405003'),
(4, 'PAY202401020001', 1000004, 'ORD202401020001', 10004, 359.00, 1, 1, '2024-01-02 09:10:00', 'WECHAT', 'WX202401020910001'),
(5, 'PAY202401020002', 1000005, 'ORD202401020002', 10005, 150.00, 2, 1, '2024-01-02 15:05:00', 'ALIPAY', 'ALI202401021505002');

-- 3.8 插入页面浏览数据
INSERT INTO fact_page_views VALUES
(1, 10001, 'SESSION001', 1, '/index', NULL, NULL, NULL, '2024-01-01 09:00:00', 30, 3, 'iOS', 'Safari', '192.168.1.100', '北京', '北京'),
(2, 10001, 'SESSION001', 3, '/product/100001', '/index', 100001, 2, '2024-01-01 09:05:00', 120, 3, 'iOS', 'Safari', '192.168.1.100', '北京', '北京'),
(3, 10002, 'SESSION002', 1, '/index', NULL, NULL, NULL, '2024-01-01 10:00:00', 25, 4, 'Android', 'Chrome', '192.168.1.101', '上海', '上海'),
(4, 10002, 'SESSION002', 3, '/product/100002', '/index', 100002, 3, '2024-01-01 10:05:00', 180, 4, 'Android', 'Chrome', '192.168.1.101', '上海', '上海'),
(5, 10003, 'SESSION003', 2, '/category/5', '/index', NULL, 5, '2024-01-01 13:00:00', 60, 3, 'Web', 'Chrome', '192.168.1.102', '广州', '广东');

-- =====================================================
-- 4. 验证数据
-- =====================================================

SELECT 'dim_categories' AS table_name, COUNT(*) AS row_count FROM dim_categories
UNION ALL
SELECT 'dim_stores', COUNT(*) FROM dim_stores
UNION ALL
SELECT 'dim_users', COUNT(*) FROM dim_users
UNION ALL
SELECT 'dim_products', COUNT(*) FROM dim_products
UNION ALL
SELECT 'fact_orders', COUNT(*) FROM fact_orders
UNION ALL
SELECT 'fact_order_items', COUNT(*) FROM fact_order_items
UNION ALL
SELECT 'fact_payments', COUNT(*) FROM fact_payments
UNION ALL
SELECT 'fact_page_views', COUNT(*) FROM fact_page_views;
