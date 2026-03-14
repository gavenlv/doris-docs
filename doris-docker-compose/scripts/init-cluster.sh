#!/bin/bash
set -e

echo "========================================"
echo "Initializing Doris Cluster"
echo "========================================"

# Wait for FE to be ready
echo "Waiting for FE to be ready..."
until curl -s http://localhost:8030/api/bootstrap > /dev/null 2>&1; do
    echo "FE not ready yet, waiting..."
    sleep 5
done

echo "FE is ready!"
echo ""

# Connect to FE and add BE nodes
echo "Adding BE nodes to cluster..."

# Add be1
mysql -h 127.0.0.1 -P 9030 -u root -e "ALTER SYSTEM ADD BACKEND 'be1:9050';" 2>/dev/null || echo "be1 may already exist"

# Add be2
mysql -h 127.0.0.1 -P 9030 -u root -e "ALTER SYSTEM ADD BACKEND 'be2:9050';" 2>/dev/null || echo "be2 may already exist"

# Add be3
mysql -h 127.0.0.1 -P 9030 -u root -e "ALTER SYSTEM ADD BACKEND 'be3:9050';" 2>/dev/null || echo "be3 may already exist"

echo ""
echo "Waiting for BE nodes to join cluster..."
sleep 10

# Check cluster status
echo ""
echo "========================================"
echo "Cluster Status:"
echo "========================================"
echo ""
echo "Frontends:"
mysql -h 127.0.0.1 -P 9030 -u root -e "SHOW FRONTENDS\G"

echo ""
echo "Backends:"
mysql -h 127.0.0.1 -P 9030 -u root -e "SHOW BACKENDS;"

echo ""
echo "========================================"
echo "Cluster Initialization Complete!"
echo "========================================"
echo ""
echo "You can now:"
echo "  1. Connect to MySQL: mysql -h 127.0.0.1 -P 9030 -u root"
echo "  2. Access FE Web UI: http://localhost:8030"
echo "  3. Create databases and tables"
echo ""
