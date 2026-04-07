#!/bin/bash
set -e

CLUSTER_NAME="${cluster_name}"
ENVIRONMENT="${environment}"
FE_SERVERS="${fe_servers}"
BE_ID="${be_id}"
GCS_BUCKET="${gcs_bucket}"
ENABLE_SEPARATION="${enable_separation}"
ENABLE_LOCAL_SSD="${enable_local_ssd}"
LOCAL_SSD_COUNT="${local_ssd_count}"
BE_MEMORY_LIMIT="${be_memory_limit}"
BE_QUERY_MEMORY_LIMIT="${be_query_memory_limit}"
BE_STORAGE_PAGE_CACHE_LIMIT="${be_storage_page_cache_limit}"
BE_SCAN_THREAD_POOL_THREAD_NUM="${be_scan_thread_pool_thread_num}"
BE_FRAGMENT_POOL_THREAD_NUM_MAX="${be_fragment_pool_thread_num_max}"
BE_COMPACTION_THREAD_NUM="${be_compaction_thread_num}"
STREAMING_LOAD_MAX_MB="${streaming_load_max_mb}"
STREAMING_LOAD_RPC_MAX_ALIVE_TIME_SEC="${streaming_load_rpc_max_alive_time_sec}"
LOG_LEVEL="${log_level}"

echo "Starting Doris BE instance setup (High-Performance Deployment)..."
echo "Cluster: ${CLUSTER_NAME}"
echo "Environment: ${ENVIRONMENT}"
echo "BE ID: ${BE_ID}"
echo "FE Servers: ${FE_SERVERS}"
echo "GCS Bucket: ${GCS_BUCKET}"
echo "Enable Compute-Storage Separation: ${ENABLE_SEPARATION}"
echo "Enable Local SSD: ${ENABLE_LOCAL_SSD}"
echo "Local SSD Count: ${LOCAL_SSD_COUNT}"

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
    nvme-cli \
    mdadm \
    sysstat \
    htop \
    iotop

# Set Java environment
cat >> /etc/profile.d/java.sh <<EOF
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=\$JAVA_HOME/bin:\$PATH
EOF
source /etc/profile.d/java.sh

# ============================================================
# System Performance Tuning
# ============================================================

echo "Applying system performance tuning..."

# Disable swap
swapoff -a
sed -i '/swap/d' /etc/fstab

# Kernel parameters
cat >> /etc/sysctl.conf <<EOF
# Doris Performance Tuning
vm.swappiness = 0
vm.max_map_count = 2000000
vm.dirty_ratio = 80
vm.dirty_background_ratio = 5
vm.overcommit_memory = 1
fs.file-max = 655360
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.ip_local_port_range = 10000 65535
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_tw_buckets = 65535
net.ipv4.tcp_max_orphans = 32768
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_wmem = 8192 131072 16777216
net.ipv4.tcp_rmem = 8192 131072 16777216
net.core.wmem_max = 16777216
net.core.rmem_max = 16777216
EOF
sysctl -p

# File descriptor limits
cat >> /etc/security/limits.conf <<EOF
* soft nofile 655350
* hard nofile 655350
* soft nproc 655350
* hard nproc 655350
* soft memlock unlimited
* hard memlock unlimited
EOF

# Disable transparent huge pages
echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo never > /sys/kernel/mm/transparent_hugepage/defrag
echo "echo never > /sys/kernel/mm/transparent_hugepage/enabled" >> /etc/rc.local
echo "echo never > /sys/kernel/mm/transparent_hugepage/defrag" >> /etc/rc.local

# ============================================================
# Local SSD Setup
# ============================================================

STORAGE_PATH="/opt/doris/be/storage"

if [ "${ENABLE_LOCAL_SSD}" = "true" ] && [ "${LOCAL_SSD_COUNT}" -gt 0 ]; then
    echo "Setting up Local SSDs..."
    
    # Discover NVMe devices
    NVME_DEVICES=$(lsblk -d -o NAME -n | grep nvme || true)
    
    if [ -n "$NVME_DEVICES" ]; then
        # Create RAID0 array for multiple NVMe SSDs
        if [ "${LOCAL_SSD_COUNT}" -gt 1 ]; then
            echo "Creating RAID0 array with ${LOCAL_SSD_COUNT} NVMe SSDs..."
            
            # Install mdadm if not present
            apt-get install -y mdadm
            
            # Create RAID0 array
            DEVICES=""
            for dev in $NVME_DEVICES; do
                DEVICES="$DEVICES /dev/$dev"
            done
            
            mdadm --create /dev/md0 --level=0 --raid-devices=${LOCAL_SSD_COUNT} $DEVICES
            
            # Create filesystem
            mkfs.xfs -f /dev/md0
            
            # Mount
            mkdir -p $STORAGE_PATH
            mount /dev/md0 $STORAGE_PATH
            
            # Add to fstab
            echo "/dev/md0 $STORAGE_PATH xfs defaults,noatime,nodiratime 0 0" >> /etc/fstab
        else
            # Single NVMe SSD
            for dev in $NVME_DEVICES; do
                mkfs.xfs -f /dev/$dev
                mkdir -p $STORAGE_PATH
                mount /dev/$dev $STORAGE_PATH
                echo "/dev/$dev $STORAGE_PATH xfs defaults,noatime,nodiratime 0 0" >> /etc/fstab
                break
            done
        fi
        
        # Set mount options for performance
        mount -o remount,noatime,nodiratime $STORAGE_PATH
        
        echo "Local SSD setup completed. Storage path: $STORAGE_PATH"
    else
        echo "No NVMe devices found, using default storage"
        mkdir -p $STORAGE_PATH
    fi
else
    mkdir -p $STORAGE_PATH
fi

# ============================================================
# Download and Install Doris BE
# ============================================================

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
mkdir -p /opt/doris/be/log
mkdir -p /opt/doris/be/conf

# ============================================================
# BE Configuration (High-Performance)
# ============================================================

cat > /opt/doris/be/conf/be.conf <<EOF
# ============================================================
# Network Configuration
# ============================================================
PPROF_PORT = 8040
HEARTBEAT_SERVICE_PORT = 9050
BACKEND_PORT = 9060
BRPC_PORT = 8060
priority_networks = 10.0.0.0/8

# ============================================================
# Memory Configuration
# ============================================================
mem_limit = ${BE_MEMORY_LIMIT}
memory_limitation_per_thread_for_schema_change = 4294967296
query_memory_limit = ${BE_QUERY_MEMORY_LIMIT}
storage_page_cache_limit = ${BE_STORAGE_PAGE_CACHE_LIMIT}
enable_storage_page_cache = true

# ============================================================
# Thread Pool Configuration
# ============================================================
scan_thread_pool_thread_num = ${BE_SCAN_THREAD_POOL_THREAD_NUM}
scan_thread_pool_queue_size = 102400
fragment_pool_thread_num_min = 64
fragment_pool_thread_num_max = ${BE_FRAGMENT_POOL_THREAD_NUM_MAX}
fragment_pool_queue_size = 2048

# ============================================================
# Compaction Configuration
# ============================================================
base_compaction_num_threads_per_disk = ${BE_COMPACTION_THREAD_NUM}
cumulative_compaction_num_threads_per_disk = ${BE_COMPACTION_THREAD_NUM}
compaction_task_num_per_disk = 4
compaction_task_num_per_fast_disk = 8
max_cumulative_compaction_num_singleton_deltas = 1000
compaction_trace_threshold = 60

# ============================================================
# Storage Configuration
# ============================================================
storage_root_path = ${STORAGE_PATH}
default_rowset_type = beta
enable_segcompaction = true
segcompaction_segment_max_rows = 1000000
enable_write_page_cache = true

# ============================================================
# Import Configuration
# ============================================================
streaming_load_max_mb = ${STREAMING_LOAD_MAX_MB}
streaming_load_rpc_max_alive_time_sec = ${STREAMING_LOAD_RPC_MAX_ALIVE_TIME_SEC}
max_send_batch_parallelism_per_job = 20
load_thread_pool_size = 64
doris_scan_range_row_count = 500000
doris_scanner_row_num = 500000
doris_scanner_thread_pool_thread_num = 64

# ============================================================
# Query Configuration
# ============================================================
enable_query_memory_overcommit = true
enable_token_check = false
enable_prefetch = true
enable_scan_block_cache = true
scanner_thread_pool_thread_num = 64
scanner_thread_pool_queue_size = 2048

# ============================================================
# Logging Configuration
# ============================================================
sys_log_dir = /opt/doris/be/log
sys_log_roll_mode = SIZE-MB-1024
sys_log_roll_num = 10
sys_log_level = ${LOG_LEVEL}
sys_log_enable_trace_log = false
sys_log_verbose_modules = 
sys_log_verbose_level = 10

# ============================================================
# Performance Tuning
# ============================================================
enable_bitmap_union_disk_format_with_set = true
enable_low_cardinality_optimize = true
enable_storage_vectorization = true
enable_batch_delete = true
enable_parallel_scan = true
num_scanner_threads = 64
num_threads_per_core = 4

# ============================================================
# Cluster Configuration
# ============================================================
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

# Configure storage paths for compute-storage separation
if [ "${ENABLE_SEPARATION}" = "true" ] && [ -n "${GCS_BUCKET}" ]; then
  cat >> /opt/doris/be/conf/be.conf <<EOF

# ============================================================
# Compute-Storage Separation Configuration
# ============================================================
enable_storage_cold_separation = true
cold_storage_default_policy = "cold"
storage_cooldown_time = "7 DAY"
EOF
fi

# ============================================================
# Create Systemd Service
# ============================================================

cat > /etc/systemd/system/doris-be.service <<EOF
[Unit]
Description=Doris Backend Service (High-Performance)
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
LimitNOFILE=655350
LimitNPROC=655350
LimitMEMLOCK=infinity

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

# Print storage info
echo ""
echo "=== Storage Information ==="
df -h $STORAGE_PATH
echo ""
echo "=== Memory Information ==="
free -h
echo ""
echo "=== CPU Information ==="
nproc
lscpu | grep "Model name"
