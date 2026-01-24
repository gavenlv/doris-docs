#!/bin/bash
set -e

CLUSTER_NAME="${cluster_name}"
FE_SERVERS="${fe_servers}"
FE_ID="${fe_id}"

echo "Starting Doris FE instance setup (Native Deployment)..."
echo "Cluster: ${CLUSTER_NAME}"
echo "FE ID: ${FE_ID}"
echo "FE Servers: ${FE_SERVERS}"

# Update system
apt-get update && apt-get upgrade -y

# Install dependencies
apt-get install -y \
    openjdk-11-jdk \
    wget \
    curl \
    vim \
    net-tools \
    lsof

# Set Java environment
cat >> /etc/profile.d/java.sh <<EOF
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=\$JAVA_HOME/bin:\$PATH
EOF
source /etc/profile.d/java.sh

# Download Doris FE
DORIS_VERSION="4.0.2"
DORIS_MIRROR="https://archive.apache.org/dist/doris"
FE_PACKAGE="apache-doris-fe-${DORIS_VERSION}-bin-x86_64.tar.gz"

echo "Downloading Doris FE ${DORIS_VERSION}..."
wget -q ${DORIS_MIRROR}/${DORIS_VERSION}/${FE_PACKAGE} -O /tmp/${FE_PACKAGE}

# Extract and install
mkdir -p /opt/doris
tar -xzf /tmp/${FE_PACKAGE} -C /opt/doris
mv /opt/doris/apache-doris-fe-${DORIS_VERSION}-bin-x86_64 /opt/doris/fe

# Create directories
mkdir -p /opt/doris/fe/doris-meta
mkdir -p /opt/doris/fe/log
mkdir -p /opt/doris/fe/conf

# Create FE configuration
cat > /opt/doris/fe/conf/fe.conf <<EOF
PROXY_PORT = 9080
HTTP_PORT = 8030
QUERY_PORT = 9030
RPC_PORT = 9020
EDIT_LOG_PORT = 9010
priority_networks = 10.0.0.0/16

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

# Create systemd service
cat > /etc/systemd/system/doris-fe.service <<EOF
[Unit]
Description=Doris Frontend Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/doris/fe
Environment="JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64"
ExecStart=/opt/doris/fe/bin/start_fe.sh --daemon
ExecStop=/opt/doris/fe/bin/stop_fe.sh
Restart=on-failure
RestartSec=10
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# Set permissions
chmod +x /opt/doris/fe/bin/*.sh
chown -R root:root /opt/doris/fe

# Start FE based on role
if [ "${FE_ID}" = "1" ]; then
  echo "Starting FE as MASTER..."
  /opt/doris/fe/bin/start_fe.sh --daemon
else
  echo "Starting FE as FOLLOWER..."
  /opt/doris/fe/bin/start_fe.sh --helper ${FE_SERVERS} --daemon
fi

# Enable systemd service
systemctl daemon-reload
systemctl enable doris-fe

echo "Doris FE${FE_ID} setup completed!"
echo "Waiting for FE to start..."
sleep 60

echo "FE${FE_ID} is ready!"
echo "Service status:"
systemctl status doris-fe --no-pager
