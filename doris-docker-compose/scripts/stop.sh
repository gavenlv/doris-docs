#!/bin/bash
set -e

echo "========================================"
echo "Stopping Doris Local Cluster"
echo "========================================"

# Stop all services
docker-compose down

echo ""
echo "Cluster stopped successfully!"
echo ""
echo "To remove all data volumes, run:"
echo "  docker-compose down -v"
