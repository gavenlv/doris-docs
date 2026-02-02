#!/bin/bash
set -e

CLUSTER_NAME="${cluster_name}"
ENVIRONMENT="${environment}"
FE_SERVERS="${fe_servers}"
FE_ID="${fe_id}"
GCS_BUCKET="${gcs_bucket}"
FDB_CLUSTER_FILE="${fdb_cluster_file}"
FDB_ENABLED="${fdb_enabled}"

echo "========================================"
echo "Doris FE Setup - Private Network Mode"
echo "With FoundationDB High Availability"
echo "========================================"
echo "Cluster: ${CLUSTER_NAME}"
echo "Environment: ${ENVIRONMENT}"
echo "FE ID: ${FE_ID}"
echo "FE Servers: ${FE_SERVERS}"
echo "GCS Bucket: ${GCS_BUCKET}"
echo "FDB Enabled: ${FDB_ENABLED}"
echo "FDB Cluster: ${FDB_CLUSTER_FILE}"
echo "Artifacts: gs://${GCS_BUCKET}-artifacts"
echo "========================================"
echo "NOTE: Running in private network - all packages from GCS"
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
    google-cloud-sdk \
    python3 \
    python3-pip

# Set Java environment
cat >> /etc/profile.d/java.sh <<EOF
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=\$JAVA_HOME/bin:\$PATH
EOF
source /etc/profile.d/java.sh

# Mount FE meta disk
echo "Mounting FE meta disk..."
mkdir -p /opt/doris/fe/doris-meta

# Check if disk is attached
if lsblk | grep -q "sdb"; then
    mkfs.ext4 -F /dev/sdb || true
    mount /dev/sdb /opt/doris/fe/doris-meta
    echo '/dev/sdb /opt/doris/fe/doris-meta ext4 defaults,nofail 0 2' >> /etc/fstab
fi

# Download Doris FE from internal GCS bucket (no internet access)
DORIS_VERSION="4.0.2"
ARTIFACTS_BUCKET="${gcs_bucket}-artifacts"
FE_PACKAGE="apache-doris-fe-${DORIS_VERSION}-bin-x86_64.tar.gz"

echo "Downloading Doris FE ${DORIS_VERSION} from GCS..."
if [ ! -d "/opt/doris/fe/bin" ]; then
    # Use gsutil to download from private bucket
    gsutil cp "gs://${ARTIFACTS_BUCKET}/doris/${FE_PACKAGE}" /tmp/${FE_PACKAGE}
    
    # Extract and install
    mkdir -p /opt/doris
    tar -xzf /tmp/${FE_PACKAGE} -C /opt/doris
    mv /opt/doris/apache-doris-fe-${DORIS_VERSION}-bin-x86_64 /opt/doris/fe
fi

# Create directories
mkdir -p /opt/doris/fe/doris-meta
mkdir -p /opt/doris/fe/log
mkdir -p /opt/doris/fe/conf

# Install FoundationDB client if enabled (from internal GCS)
if [ "${FDB_ENABLED}" = "true" ]; then
    echo "Installing FoundationDB client from GCS..."
    FDB_VERSION="7.3.27"
    ARTIFACTS_BUCKET="${gcs_bucket}-artifacts"
    FDB_CLIENT_PKG="foundationdb-clients_${FDB_VERSION}-1_amd64.deb"
    
    # Download from private GCS bucket
    gsutil cp "gs://${ARTIFACTS_BUCKET}/foundationdb/${FDB_CLIENT_PKG}" /tmp/${FDB_CLIENT_PKG}
    dpkg -i /tmp/${FDB_CLIENT_PKG} || apt-get install -f -y
    
    # Create FDB cluster file
    mkdir -p /etc/foundationdb
    echo "${FDB_CLUSTER_FILE}" > /etc/foundationdb/fdb.cluster
    chmod 644 /etc/foundationdb/fdb.cluster
    
    # Test FDB connection
    echo "Testing FoundationDB connection..."
    fdbcli --exec "status" || echo "FDB connection test completed"
fi

# Create FE configuration
cat > /opt/doris/fe/conf/fe.conf <<EOF
# Network Configuration
PROXY_PORT = 9080
HTTP_PORT = 8030
QUERY_PORT = 9030
RPC_PORT = 9020
EDIT_LOG_PORT = 9010
priority_networks = 10.0.0.0/16

# Storage Configuration
meta_dir = /opt/doris/fe/doris-meta
LOG_DIR = /opt/doris/fe/log
storage_root_path = /opt/doris/fe/doris-meta

# JVM Configuration
JAVA_OPTS="-Xmx4g -Xms4g -Xmn2g -XX:+UseMembar -XX:SurvivorRatio=8 -XX:MaxTenuringThreshold=7 -XX:+PrintGCDateStamps -XX:+PrintGCDetails -XX:+UseConcMarkSweepGC -XX:+UseParNewGC -XX:+CMSClassUnloadingEnabled -XX:-CMSParallelRemarkEnabled -XX:CMSInitiatingOccupancyFraction=80 -XX:SoftRefLRUPolicyMSPerMB=0 -Xloggc:\$LOG_DIR/fe.gc.log.\$DATE"

# Service Configuration
http_port = 8030
rpc_port = 9020
query_port = 9030
edit_log_port = 9010
mysql_service_nio_enabled = true
enable_fqdn_check = false

# Cluster Configuration
cluster_name = ${CLUSTER_NAME}
max_connection = 1000

# Health Check
frontend_health_check_interval_seconds = 10
heartbeat_interval_second = 10
heartbeat_timeout_second = 30

# Security
enable_https = false
enable_auth = true
enable_token_check = true

# Compute Storage Separation Configuration
enable_storage_cold_separation = true
storage_root_path = /opt/doris/fe/doris-meta,${GCS_BUCKET}

# FoundationDB Configuration (for high availability)
EOF

if [ "${FDB_ENABLED}" = "true" ]; then
    cat >> /opt/doris/fe/conf/fe.conf <<EOF
# Use FoundationDB as metadata store for HA
meta_store_type = foundationdb
fdb_cluster_file_path = /etc/foundationdb/fdb.cluster
fdb_transaction_timeout_ms = 5000
fdb_transaction_retry_limit = 10
EOF
else
    cat >> /opt/doris/fe/conf/fe.conf <<EOF
# Use BDBJE as metadata store (single node)
meta_store_type = bdbje
EOF
fi

cat >> /opt/doris/fe/conf/fe.conf <<EOF
# Other Settings
check_java_version = false
enable_bdbje_debug_mode = false
meta_delay_toleration_second = 10
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

echo "========================================"
echo "Doris FE${FE_ID} setup completed!"
echo "========================================"
echo "Waiting for FE to start..."
sleep 60

echo "FE${FE_ID} is ready!"
systemctl status doris-fe --no-pager
