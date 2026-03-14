#!/bin/bash

echo "========================================"
echo "Doris Cluster Health Check"
echo "========================================"

# Check container status
echo ""
echo "1. Container Status:"
docker-compose ps

# Check FE health
echo ""
echo "2. FE Health Check:"
for i in 1 2 3; do
    PORT=$((8030 + i - 1))
    echo "  - FE$i (port $PORT):"
    curl -s http://localhost:$PORT/api/bootstrap | python3 -m json.tool 2>/dev/null || echo "    Not ready"
done

# Check BE health
echo ""
echo "3. BE Health Check:"
for i in 1 2 3; do
    PORT=$((8040 + i - 1))
    echo "  - BE$i (port $PORT):"
    curl -s http://localhost:$PORT/api/health | python3 -m json.tool 2>/dev/null || echo "    Not ready"
done

# Check MySQL connection
echo ""
echo "4. MySQL Connection Check:"
mysql -h 127.0.0.1 -P 9030 -u root -e "SELECT 1 as test;" 2>/dev/null && echo "  ✓ MySQL connection OK" || echo "  ✗ MySQL connection failed"

# Check cluster status
echo ""
echo "5. Cluster Status:"
mysql -h 127.0.0.1 -P 9030 -u root -e "SHOW FRONTENDS\G" 2>/dev/null | grep -E "Name|Host|Port|Role|Alive" || echo "  Unable to get FE status"

echo ""
mysql -h 127.0.0.1 -P 9030 -u root -e "SHOW BACKENDS;" 2>/dev/null || echo "  Unable to get BE status"

# Check resource usage
echo ""
echo "6. Resource Usage:"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" | grep doris

echo ""
echo "========================================"
echo "Health Check Complete!"
echo "========================================"
