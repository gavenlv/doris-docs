#!/bin/bash
set -e

CLUSTER_NAME="${cluster_name}"
FE_SERVERS="${fe_servers}"
BE_ID="${be_id}"
ENABLE_TIERED_STORAGE="${enable_tiered_storage:-false}"
OSS_HOT_BUCKET="${oss_hot_bucket:-}"
OSS_WARM_BUCKET="${oss_warm_bucket:-}"
OSS_COLD_BUCKET="${oss_cold_bucket:-}"
HOT_STORAGE_SIZE="${hot_storage_size:-100}"
WARM_STORAGE_SIZE="${warm_storage_size:-500}"
COLD_STORAGE_SIZE="${cold_storage_size:-1000}"
OSS_ACCESS_KEY_ID="${oss_access_key_id:-}"
OSS_ACCESS_KEY_SECRET="${oss_access_key_secret:-}"
OSS_ENDPOINT="${oss_endpoint:-}"

echo "Starting Doris BE instance setup (Native Deployment)..."
echo "Cluster: ${CLUSTER_NAME}"
echo "BE ID: ${BE_ID}"
echo "FE Servers: ${FE_SERVERS}"
echo "Tiered Storage Enabled: ${ENABLE_TIERED_STORAGE}"

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
    libaio1

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

# Configure tiered storage
if [ "$ENABLE_TIERED_STORAGE" = "true" ]; then
  echo "Configuring tiered storage..."
  
  # Install rclone for OSS mounting
  apt-get install -y rclone
  
  # Create mount points
  mkdir -p /mnt/oss-hot
  mkdir -p /mnt/oss-warm
  mkdir -p /mnt/oss-cold
  
  # Configure rclone for OSS
  cat > /root/.config/rclone/rclone.conf <<EOF
[doris-hot]
type = aliyun
access_key_id = ${OSS_ACCESS_KEY_ID}
secret_access_key = ${OSS_ACCESS_KEY_SECRET}
endpoint = ${OSS_ENDPOINT}
acl = private

[doris-warm]
type = aliyun
access_key_id = ${OSS_ACCESS_KEY_ID}
secret_access_key = ${OSS_ACCESS_KEY_SECRET}
endpoint = ${OSS_ENDPOINT}
acl = private

[doris-cold]
type = aliyun
access_key_id = ${OSS_ACCESS_KEY_ID}
secret_access_key = ${OSS_ACCESS_KEY_SECRET}
endpoint = ${OSS_ENDPOINT}
acl = private
EOF
  
  # Mount OSS buckets using rclone mount
  cat > /etc/systemd/system/doris-oss-mount.service <<EOF
[Unit]
Description=Doris OSS Mount Service
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash -c 'rclone mount doris-hot:${OSS_HOT_BUCKET} /mnt/oss-hot --allow-other --allow-non-empty --vfs-cache-mode full --daemon-timeout 10m & rclone mount doris-warm:${OSS_WARM_BUCKET} /mnt/oss-warm --allow-other --allow-non-empty --vfs-cache-mode full --daemon-timeout 10m & rclone mount doris-cold:${OSS_COLD_BUCKET} /mnt/oss-cold --allow-other --allow-non-empty --vfs-cache-mode full --daemon-timeout 10m & wait'
ExecStop=/bin/bash -c 'umount /mnt/oss-hot /mnt/oss-warm /mnt/oss-cold 2>/dev/null || true'
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
  
  systemctl daemon-reload
  systemctl enable doris-oss-mount
  systemctl start doris-oss-mount
  
  echo "Waiting for OSS mounts to be ready..."
  sleep 10
  
  STORAGE_PATHS="/opt/doris/be/storage,/mnt/oss-hot,/mnt/oss-warm,/mnt/oss-cold"
else
  STORAGE_PATHS="/opt/doris/be/storage"
fi

# Create BE configuration
cat > /opt/doris/be/conf/be.conf <<EOF
PPROF_PORT = 8040
HEARTBEAT_SERVICE_PORT = 9050
BACKEND_PORT = 9060
BRPC_PORT = 8060
priority_networks = 172.16.0.0/16

storage_root_path = ${STORAGE_PATHS}

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

# Configure tiered storage policies
if [ "$ENABLE_TIERED_STORAGE" = "true" ]; then
  cat >> /opt/doris/be/conf/be.conf <<EOF

# Tiered Storage Configuration
storage_flood_stage_usage_percent = 90
storage_flood_stage_left_capacity_bytes = 10737418240
EOF
fi

# Create systemd service
cat > /etc/systemd/system/doris-be.service <<EOF
[Unit]
Description=Doris Backend Service
After=network.target doris-oss-mount.service

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

if [ "$ENABLE_TIERED_STORAGE" = "true" ]; then
  echo ""
  echo "Tiered Storage Configuration:"
  echo "  Hot Storage (SSD):  $OSS_HOT_BUCKET (${HOT_STORAGE_SIZE}GB)"
  echo "  Warm Storage (OSS): $OSS_WARM_BUCKET (${WARM_STORAGE_SIZE}GB)"
  echo "  Cold Storage (OSS): $OSS_COLD_BUCKET (${COLD_STORAGE_SIZE}GB)"
  echo ""
  echo "Storage Lifecycle Policies:"
  echo "  Hot -> Warm: 7 days"
  echo "  Warm -> Cold: 60 days"
  echo "  Cold Expiration: 365 days"
fi
