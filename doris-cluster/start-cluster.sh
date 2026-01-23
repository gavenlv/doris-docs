#!/bin/bash

Doris集群启动脚本

echo "Starting Doris cluster..."

docker-compose up -d

echo "Waiting for FE nodes to be ready..."
sleep 30

echo "Checking FE status..."
docker exec doris_fe1 mysql -h 127.0.0.1 -P 9030 -u root -e "SHOW FRONTENDS;"

echo "Adding BE nodes to cluster..."
docker exec doris_fe1 mysql -h 127.0.0.1 -P 9030 -u root -e "ALTER SYSTEM ADD BACKEND '172.20.0.21:9050';"
docker exec doris_fe1 mysql -h 127.0.0.1 -P 9030 -u root -e "ALTER SYSTEM ADD BACKEND '172.20.0.22:9050';"
docker exec doris_fe1 mysql -h 127.0.0.1 -P 9030 -u root -e "ALTER SYSTEM ADD BACKEND '172.20.0.23:9050';"

echo "Checking cluster status..."
docker exec doris_fe1 mysql -h 127.0.0.1 -P 9030 -u root -e "SHOW BACKENDS;"

echo "Doris cluster started successfully!"
echo "FE1: http://localhost:8030"
echo "FE2: http://localhost:8031"
echo "FE3: http://localhost:8032"
echo "MySQL Port: 9030"
