#!/bin/bash
set -e

echo "========================================"
echo "Doris Stream Load 示例"
echo "========================================"

# 配置
FE_HOST="localhost"
FE_HTTP_PORT="8030"
DATABASE="demo"
TABLE="fact_orders"
USER="root"
PASSWORD=""

# 创建测试数据文件
echo "创建测试数据文件..."
cat > /tmp/orders_data.csv <<EOF
2001,1,201,2024-01-20,2024-01-20 10:00:00,1,99.99,0.00,99.99,completed
2002,2,202,2024-01-21,2024-01-21 11:30:00,2,199.99,20.00,179.99,completed
2003,3,203,2024-01-22,2024-01-22 14:15:00,1,299.99,30.00,269.99,completed
2004,4,201,2024-01-23,2024-01-23 16:45:00,3,99.99,10.00,89.99,completed
2005,5,202,2024-01-24,2024-01-24 09:20:00,2,199.99,0.00,199.99,completed
EOF

echo "测试数据已创建: /tmp/orders_data.csv"
echo ""

# 执行 Stream Load
echo "执行 Stream Load..."
curl --location-trusted \
    -u "${USER}:${PASSWORD}" \
    -H "column_separator:," \
    -H "columns:order_id,user_id,product_id,order_date,order_time,quantity,amount,discount,final_amount,status" \
    -H "max_filter_ratio:0.1" \
    -T /tmp/orders_data.csv \
    "http://${FE_HOST}:${FE_HTTP_PORT}/api/${DATABASE}/${TABLE}/_stream_load"

echo ""
echo ""

# 验证数据
echo "验证导入数据..."
mysql -h 127.0.0.1 -P 9030 -u root <<EOF
USE ${DATABASE};
SELECT COUNT(*) as total_rows FROM ${TABLE};
SELECT * FROM ${TABLE} WHERE order_id >= 2001 ORDER BY order_id;
EOF

echo ""
echo "========================================"
echo "Stream Load 示例完成!"
echo "========================================"

# 清理测试文件
rm -f /tmp/orders_data.csv
