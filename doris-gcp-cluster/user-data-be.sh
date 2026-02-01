#!/bin/bash
set -e

CLUSTER_NAME="${cluster_name}"
ENVIRONMENT="${environment}"
FE_SERVERS="${fe_servers}"
BE_ID="${be_id}"
GCS_BUCKET="${gcs_bucket}"
ENABLE_SEPARATION="${enable_separation}"

echo "Starting Doris BE instance setup (Native Deployment)..."
echo "Cluster: ${CLUSTER_NAME}"
echo "Environment: ${ENVIRONMENT}"
echo "BE ID: ${BE_ID}"
echo "FE Servers: ${FE_SERVERS}"
echo "GCS Bucket: ${GCS_BUCKET}"
echo "Enable Compute-Storage Separation: ${ENABLE_SEPARATION}"

# Update system
apt-get update && apt-get upgrade -y

# Install dependencies
apt-get install -y \
    openjdk-11-jdk \
    wget \
    curl \
    vim \
    net-tools \
    lsof \
    uuid-runtime \
    libaio1 \
    google-cloud-cli

# Set Java environment
cat >> /etc/profile.d/java.sh <<EOF
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=\$JAVA_HOME/bin:\$PATH
EOF
source /etc/profile.d/java.sh

# Download Doris BE
DORIS_VERSION="4.0.2"
DORIS_MIRROR="https://archive.apache.org/dist/doris"
BE_PACKAGE="apache-doris-be-${DORIS_VERSION}-bin-x86_64.tar.gz"

echo "Downloading Doris BE ${DORIS_VERSION}..."
wget -q ${DORIS_MIRROR}/${DORIS_VERSION}/${BE_PACKAGE} -O /tmp/${BE_PACKAGE}

# Extract and install
mkdir -p /opt/doris
tar -xzf /tmp/${BE_PACKAGE} -C /opt/doris
mv /opt/doris/apache-doris-be-${DORIS_VERSION}-bin-x86_64 /opt/doris/be

# Create directories
mkdir -p /opt/doris/be/storage
mkdir -p /opt/doris/be/log
mkdir -p /opt/doris/be/conf

# Create BE configuration
cat > /opt/doris/be/conf/be.conf <<EOF
PPROF_PORT = 8040
HEARTBEAT_SERVICE_PORT = 9050
BACKEND_PORT = 9060
BRPC_PORT = 8060
priority_networks = 10.0.0.0/16

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

# Configure storage paths
if [ "${ENABLE_SEPARATION}" = "true" ] && [ -n "${GCS_BUCKET}" ]; then
  cat >> /opt/doris/be/conf/be.conf <<EOF
# Compute-Storage Separation Configuration
storage_root_path = /opt/doris/be/storage,${GCS_BUCKET}/doris-storage

# Cold storage settings
enable_storage_cold_separation = true
EOF
else
  cat >> /opt/doris/be/conf/be.conf <<EOF
storage_root_path = /opt/doris/be/storage
EOF
fi

# Create systemd service
cat > /etc/systemd/system/doris-be.service <<EOF
[Unit]
Description=Doris Backend Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/doris/be
Environment="JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64"
ExecStart=/opt/doris/be/bin/start_be.sh --daemon
ExecStop=/opt/doris/be/bin/stop_be.sh
Restart=on-failure
RestartSec=10
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# Set permissions
chmod +x /opt/doris/be/bin/*.sh
chown -R root:root /opt/doris/be

# Start BE
echo "Starting BE..."
/opt/doris/be/bin/start_be.sh --daemon

# Enable systemd service
systemctl daemon-reload
systemctl enable doris-be

echo "Doris BE${BE_ID} setup completed!"
echo "Waiting for BE to start..."
sleep 30

echo "BE${BE_ID} is ready!"
echo "Service status:"
systemctl status doris-be --no-pager
