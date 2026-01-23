#!/bin/bash
set -e

CLUSTER_NAME="${cluster_name}"
FE_SERVERS="${fe_servers}"
BE_ID="${be_id}"

echo "Starting Doris BE instance setup..."
echo "Cluster: ${CLUSTER_NAME}"
echo "BE ID: ${BE_ID}"
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
mkdir -p /opt/doris/be/conf
mkdir -p /opt/doris/be/storage
mkdir -p /opt/doris/be/log

# Create BE configuration
cat > /opt/doris/be/conf/be.conf <<EOF
PPROF_PORT = 8040
HEARTBEAT_SERVICE_PORT = 9050
BACKEND_PORT = 9060
BRPC_PORT = 8060
priority_networks = 172.16.0.0/16

storage_root_path = /opt/doris/be/storage

JAVA_OPTS="-Xmx4g -Xms4g -Xmn2g -XX:+UseMembar -XX:SurvivorRatio=8 -XX:MaxTenuringThreshold=7 -XX:+PrintGCDateStamps -XX:+PrintGCDetails -XX:+UseConcMarkSweepGC -XX:+UseParNewGC -XX:+CMSClassUnloadingEnabled -XX:-CMSParallelRemarkEnabled -XX:CMSInitiatingOccupancyFraction=80 -XX:SoftRefLRUPolicyMSPerMB=0 -Xloggc:\$LOG_DIR/be.gc.log.\$DATE"

http_port = 8040
heartbeat_service_port = 9050
brpc_port = 8060
default_rowset_type = beta

sys_log_dir = /opt/doris/be/log
sys_log_roll_mode = SIZE-MB-1024
sys_log_roll_num = 10

sys_log_level = INFO

be_http_port = 8040

default_cluster_name = ${CLUSTER_NAME}

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

# Start BE container
docker run -d \
  --name doris_be${BE_ID} \
  --network host \
  --restart unless-stopped \
  -v /opt/doris/be/conf:/opt/doris/be/conf \
  -v /opt/doris/be/storage:/opt/doris/be/storage \
  -v /opt/doris/be/log:/opt/doris/be/log \
  -e FE_SERVERS="${FE_SERVERS}" \
  -e BE_ADDR="172.16.0.2${BE_ID}:9050" \
  zlsmshoqvwt6q1.xuanyuan.run/apache/doris:be-4.0.2

echo "Doris BE${BE_ID} setup completed!"
echo "Waiting for BE to start..."
sleep 30

echo "BE${BE_ID} is ready!"
