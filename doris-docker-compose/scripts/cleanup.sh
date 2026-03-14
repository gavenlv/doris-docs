#!/bin/bash
set -e

echo "========================================"
echo "Cleaning Up Doris Local Environment"
echo "========================================"

# Stop all containers
echo "Stopping all containers..."
docker-compose down

# Remove volumes
echo "Removing data volumes..."
docker-compose down -v

# Remove images (optional)
read -p "Do you want to remove Doris Docker images? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Removing Doris images..."
    docker rmi apache/doris:fe-${DORIS_VERSION:-3.1.4} 2>/dev/null || true
    docker rmi apache/doris:be-${DORIS_VERSION:-3.1.4} 2>/dev/null || true
    docker rmi foundationdb/foundationdb:${FDB_VERSION:-7.1.37} 2>/dev/null || true
    docker rmi prom/prometheus:v2.45.0 2>/dev/null || true
    docker rmi grafana/grafana:10.2.0 2>/dev/null || true
    echo "Images removed."
fi

# Remove network
echo "Removing network..."
docker network rm doris-local 2>/dev/null || true

echo ""
echo "========================================"
echo "Cleanup Complete!"
echo "========================================"
echo ""
echo "To start fresh, run:"
echo "  ./scripts/start.sh"
