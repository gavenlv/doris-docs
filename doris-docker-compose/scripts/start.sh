#!/bin/bash
set -e

echo "========================================"
echo "Starting Doris Local Cluster"
echo "========================================"

# Copy .env.example to .env if not exists
if [ ! -f .env ]; then
    echo "Copying .env.example to .env..."
    cp .env.example .env
fi

# Load environment variables
source .env

echo "Doris Version: ${DORIS_VERSION:-3.1.4}"
echo "FoundationDB Version: ${FDB_VERSION:-7.1.37}"
echo ""

# Start services
echo "Starting FoundationDB cluster (3 nodes)..."
docker-compose up -d fdb1 fdb2 fdb3

echo "Waiting for FoundationDB to be ready..."
sleep 10

echo "Starting Doris FE cluster (3 nodes)..."
docker-compose up -d fe1 fe2 fe3

echo "Waiting for Doris FE to be ready..."
echo "This may take 30-60 seconds..."
sleep 30

echo "Starting Doris BE cluster (3 nodes)..."
docker-compose up -d be1 be2 be3

echo ""
echo "========================================"
echo "Doris Local Cluster Started!"
echo "========================================"
echo ""
echo "Cluster Information:"
echo "  - FE Master: http://localhost:${FE_HTTP_PORT:-8030}"
echo "  - MySQL Connection: mysql -h 127.0.0.1 -P ${FE_QUERY_PORT:-9030} -u root"
echo ""
echo "To check cluster status:"
echo "  docker-compose ps"
echo ""
echo "To view FE logs:"
echo "  docker-compose logs -f fe1"
echo ""
echo "To view BE logs:"
echo "  docker-compose logs -f be1"
echo ""

# Ask if user wants to start monitoring
if [ "${ENABLE_MONITORING:-false}" = "true" ]; then
    echo "Starting monitoring services..."
    docker-compose --profile monitoring up -d
    echo "  - Prometheus: http://localhost:${PROMETHEUS_PORT:-9090}"
    echo "  - Grafana: http://localhost:${GRAFANA_PORT:-3000} (admin/admin)"
    echo ""
fi

echo "Cluster initialization in progress..."
echo "Please wait 1-2 minutes for all components to be fully ready."
echo ""
echo "To verify cluster status, run:"
echo "  mysql -h 127.0.0.1 -P ${FE_QUERY_PORT:-9030} -u root -e 'SHOW FRONTENDS;'"
echo "  mysql -h 127.0.0.1 -P ${FE_QUERY_PORT:-9030} -u root -e 'SHOW BACKENDS;'"
