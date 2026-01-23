#!/bin/bash
set -e

CLUSTER_NAME="${cluster_name}"
FE_SERVERS="${fe_servers}"
FE_ID="${fe_id}"

echo "Starting Doris FE instance setup..."
echo "Cluster: ${CLUSTER_NAME}"
echo "FE ID: ${FE_ID}"
echo "FE Servers: ${FE_SERVERS}"

# Update system
apt-get update && apt-get upgrade -y

# Install Docker
apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io

# Install Docker Compose
curl -SL https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Create directories
mkdir -p /opt/doris/fe/conf
mkdir -p /opt/doris/fe/doris-meta
mkdir -p /opt/doris/fe/log

# Create FE configuration
cat > /opt/doris/fe/conf/fe.conf <<EOF
PROXY_PORT = 9080
HTTP_PORT = 8030
QUERY_PORT = 9030
RPC_PORT = 9020
EDIT_LOG_PORT = 9010
priority_networks = 172.16.0.0/16

meta_dir = /opt/doris/fe/doris-meta
LOG_DIR = /opt/doris/fe/log

JAVA_OPTS="-Xmx2g -Xms2g -Xmn1g -XX:+UseMembar -XX:SurvivorRatio=8 -XX:MaxTenuringThreshold=7 -XX:+PrintGCDateStamps -XX:+PrintGCDetails -XX:+UseConcMarkSweepGC -XX:+UseParNewGC -XX:+CMSClassUnloadingEnabled -XX:-CMSParallelRemarkEnabled -XX:CMSInitiatingOccupancyFraction=80 -XX:SoftRefLRUPolicyMSPerMB=0 -Xloggc:\$LOG_DIR/fe.gc.log.\$DATE"

http_port = 8030
rpc_port = 9020
query_port = 9030
edit_log_port = 9010
mysql_service_nio_enabled = true

enable_fqdn_check = false

frontend_health_check_interval_seconds = 10

max_connection = 1000

cluster_name = ${CLUSTER_NAME}

storage_root_path = /opt/doris/fe/doris-meta

heartbeat_interval_second = 10
heartbeat_timeout_second = 30

check_java_version = false

enable_https = false

enable_auth = true

default_password_cluster = ""

enable_bdbje_debug_mode = false

meta_delay_toleration_second = 10

enable_token_check = true

enable_deploy_manager = true
EOF

# Start FE container
docker run -d \
  --name doris_fe${FE_ID} \
  --network host \
  --restart unless-stopped \
  -v /opt/doris/fe/conf:/opt/doris/fe/conf \
  -v /opt/doris/fe/doris-meta:/opt/doris/fe/doris-meta \
  -v /opt/doris/fe/log:/opt/doris/fe/log \
  -e FE_SERVERS="${FE_SERVERS}" \
  -e FE_ID="${FE_ID}" \
  zlsmshoqvwt6q1.xuanyuan.run/apache/doris:fe-4.0.2

echo "Doris FE${FE_ID} setup completed!"
echo "Waiting for FE to start..."
sleep 60

echo "FE${FE_ID} is ready!"
