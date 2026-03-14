#!/bin/bash
set -e

echo "========================================"
echo "Resetting Doris Cluster"
echo "========================================"

# Stop all services
echo "Stopping all services..."
docker-compose down

# Remove all data volumes
echo "Removing all data volumes..."
docker volume rm doris-local_fe1-data 2>/dev/null || true
docker volume rm doris-local_fe2-data 2>/dev/null || true
docker volume rm doris-local_fe3-data 2>/dev/null || true
docker volume rm doris-local_be1-data 2>/dev/null || true
docker volume rm doris-local_be2-data 2>/dev/null || true
docker volume rm doris-local_be3-data 2>/dev/null || true
docker volume rm doris-local_fdb1-data 2>/dev/null || true
docker volume rm doris-local_fdb2-data 2>/dev/null || true
docker volume rm doris-local_fdb3-data 2>/dev/null || true
docker volume rm doris-local_prometheus-data 2>/dev/null || true
docker volume rm doris-local_grafana-data 2>/dev/null || true

echo ""
echo "Reset complete! Starting fresh cluster..."
echo ""

# Start cluster
./scripts/start.sh

# Wait for cluster to be ready
echo ""
echo "Waiting for cluster to be ready (60 seconds)..."
sleep 60

# Initialize cluster
./scripts/init-cluster.sh
