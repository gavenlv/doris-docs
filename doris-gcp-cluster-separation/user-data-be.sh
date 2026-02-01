#!/bin/bash
set -e

CLUSTER_NAME="${cluster_name}"
ENVIRONMENT="${environment}"
FE_SERVERS="${fe_servers}"
BE_ID="${be_id}"
GCS_BUCKET="${gcs_bucket}"
HOT_STORAGE_PATH="${hot_storage_path}"
COLD_STORAGE_PATH="${cold_storage_path}"

echo "========================================"
echo "Doris BE Setup - Compute Storage Separation"
echo "========================================"
echo "Cluster: ${CLUSTER_NAME}"
echo "Environment: ${ENVIRONMENT}"
echo "BE ID: ${BE_ID}"
echo "FE Servers: ${FE_SERVERS}"
echo "GCS Bucket: ${GCS_BUCKET}"
echo "Hot Storage: ${HOT_STORAGE_PATH}"
echo "Cold Storage: ${COLD_STORAGE_PATH}"
echo "========================================"

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
    google-cloud-cli \
    gcsfuse

# Set Java environment
cat >> /etc/profile.d/java.sh <<EOF
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=\$JAVA_HOME/bin:\$PATH
EOF
source /etc/profile.d/java.sh

# Mount BE storage disk
echo "Mounting BE storage disk..."
mkdir -p ${HOT_STORAGE_PATH}

# Check if disk is attached
if lsblk | grep -q "sdb"; then
    mkfs.ext4 -F /dev/sdb || true
    mount /dev/sdb ${HOT_STORAGE_PATH}
    echo '/dev/sdb ${HOT_STORAGE_PATH} ext4 defaults,nofail 0 2' >> /etc/fstab
fi

# Mount GCS bucket for cold storage
echo "Mounting GCS bucket for cold storage..."
mkdir -p /mnt/gcs-cold-storage
gcsfuse ${GCS_BUCKET} /mnt/gcs-cold-storage || echo "GCS mount will be configured later"

# Download Doris BE
DORIS_VERSION="4.0.2"
DORIS_MIRROR="https://archive.apache.org/dist/doris"
BE_PACKAGE="apache-doris-be-${DORIS_VERSION}-bin-x86_64.tar.gz"

echo "Downloading Doris BE ${DORIS_VERSION}..."
if [ ! -d "/opt/doris/be/bin" ]; then
    wget -q ${DORIS_MIRROR}/${DORIS_VERSION}/${BE_PACKAGE} -O /tmp/${BE_PACKAGE}
    
    # Extract and install
    mkdir -p /opt/doris
    tar -xzf /tmp/${BE_PACKAGE} -C /opt/doris
    mv /opt/doris/apache-doris-be-${DORIS_VERSION}-bin-x86_64 /opt/doris/be
fi

# Create directories
mkdir -p ${HOT_STORAGE_PATH}
mkdir -p /opt/doris/be/log
mkdir -p /opt/doris/be/conf
mkdir -p /mnt/gcs-cold-storage/doris-data

# Create BE configuration
cat > /opt/doris/be/conf/be.conf <<EOF
# Network Configuration
PPROF_PORT = 8040
HEARTBEAT_SERVICE_PORT = 9050
BACKEND_PORT = 9060
BRPC_PORT = 8060
priority_networks = 10.0.0.0/16

# JVM Configuration
JAVA_OPTS="-Xmx4g -Xms4g -Xmn2g -XX:+UseMembar -XX:SurvivorRatio=8 -XX:MaxTenuringThreshold=7 -XX:+PrintGCDateStamps -XX:+PrintGCDetails -XX:+UseConcMarkSweepGC -XX:+UseParNewGC -XX:+CMSClassUnloadingEnabled -XX:-CMSParallelRemarkEnabled -XX:CMSInitiatingOccupancyFraction=80 -XX:SoftRefLRUPolicyMSPerMB=0 -Xloggc:\$LOG_DIR/be.gc.log.\$DATE"

# Service Configuration
http_port = 8040
heartbeat_service_port = 9050
brpc_port = 8060
default_rowset_type = beta

# Logging Configuration
sys_log_dir = /opt/doris/be/log
sys_log_roll_mode = SIZE-MB-1024
sys_log_roll_num = 10
sys_log_level = INFO

# Cluster Configuration
default_cluster_name = ${CLUSTER_NAME}
heartbeat_interval_second = 10
heartbeat_timeout_second = 30

# Compute Storage Separation Configuration
# Format: path1,path2[medium:ssd],path3[medium:hdd]
storage_root_path = ${HOT_STORAGE_PATH}[medium:ssd],/mnt/gcs-cold-storage/doris-data[medium:hdd]

# Enable cold data separation
enable_storage_cold_separation = true

# Cold data migration threshold (days)
# Data not accessed for this many days will be moved to cold storage
cold_data_threshold = 7

# Storage policy for new tables
default_storage_policy = "hot_to_cold"

# Security
enable_https = false
enable_auth = true

# Other Settings
check_java_version = false
be_http_port = 8040
EOF

# Create storage policy configuration
cat > /opt/doris/be/conf/storage_policy.conf <<EOF
# Storage Policy for Compute Storage Separation
[storage_policy.hot_to_cold]
name = "hot_to_cold"
hot_storage = "ssd"
cold_storage = "hdd"
migration_threshold = 7

[storage.hot]
medium = "ssd"
path = "${HOT_STORAGE_PATH}"

[storage.cold]
medium = "hdd"
path = "/mnt/gcs-cold-storage/doris-data"
EOF

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
ExecStartPre=/bin/mountpoint -q /mnt/gcs-cold-storage || gcsfuse ${GCS_BUCKET} /mnt/gcs-cold-storage
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

echo "========================================"
echo "Doris BE setup completed!"
echo "========================================"
echo "Waiting for BE to start..."
sleep 30

echo "BE is ready!"
systemctl status doris-be --no-pager

echo ""
echo "========================================"
echo "Storage Configuration:"
echo "  Hot Storage (SSD): ${HOT_STORAGE_PATH}"
echo "  Cold Storage (GCS): /mnt/gcs-cold-storage/doris-data"
echo "========================================"
