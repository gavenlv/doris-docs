#!/bin/bash
set -e

CLUSTER_NAME="${cluster_name}"
FDB_VERSION="${fdb_version}"
FDB_ID="${fdb_id}"
FDB_COUNT="${fdb_count}"
FDB_COORDINATORS="${fdb_coordinators}"

echo "========================================"
echo "FoundationDB Setup (Public Network)"
echo "========================================"
echo "Cluster: ${CLUSTER_NAME}"
echo "Version: ${FDB_VERSION}"
echo "FDB ID: ${FDB_ID}"
echo "FDB Count: ${FDB_COUNT}"
echo "Coordinators: ${FDB_COORDINATORS}"
echo "========================================"

# Update system
apt-get update && apt-get upgrade -y

# Install dependencies
apt-get install -y \
    wget \
    curl \
    vim \
    net-tools \
    python3 \
    python3-pip \
    libssl-dev \
    libffi-dev

# Mount FDB data disk
echo "Mounting FDB data disk..."
mkdir -p /var/lib/foundationdb/data

if lsblk | grep -q "sdb"; then
    mkfs.ext4 -F /dev/sdb || true
    mount /dev/sdb /var/lib/foundationdb/data
    echo '/dev/sdb /var/lib/foundationdb/data ext4 defaults,nofail 0 2' >> /etc/fstab
fi

# Download and install FoundationDB from internet (public network mode)
echo "Installing FoundationDB ${FDB_VERSION}..."
FDB_CLIENT_PKG="foundationdb-clients_${FDB_VERSION}-1_amd64.deb"
FDB_SERVER_PKG="foundationdb-server_${FDB_VERSION}-1_amd64.deb"
FDB_BASE_URL="https://github.com/apple/foundationdb/releases/download/${FDB_VERSION}"

if [ ! -f "/usr/sbin/fdbserver" ]; then
    wget -q ${FDB_BASE_URL}/${FDB_CLIENT_PKG} -O /tmp/${FDB_CLIENT_PKG}
    wget -q ${FDB_BASE_URL}/${FDB_SERVER_PKG} -O /tmp/${FDB_SERVER_PKG}
    
    dpkg -i /tmp/${FDB_CLIENT_PKG} || apt-get install -f -y
    dpkg -i /tmp/${FDB_SERVER_PKG} || apt-get install -f -y
fi

# Create FDB data directories
mkdir -p /var/lib/foundationdb/data
mkdir -p /var/log/foundationdb
mkdir -p /etc/foundationdb

# Configure FoundationDB
echo "Configuring FoundationDB..."

# Generate cluster file
CLUSTER_FILE="/etc/foundationdb/fdb.cluster"

if [ "${FDB_ID}" = "1" ]; then
    # First node - initialize the cluster
    echo "Initializing FoundationDB cluster..."
    
    # Create initial cluster file
    echo "${CLUSTER_NAME}:xxxxx@10.0.0.101:4500" > ${CLUSTER_FILE}
    
    # Configure fdbserver
    cat > /etc/foundationdb/foundationdb.conf <<EOF
[fdbserver]
command = /usr/sbin/fdbserver
public_address = auto:4500
listen_address = public
data_dir = /var/lib/foundationdb/data
log_dir = /var/log/foundationdb
# Set memory and storage limits
memory = 8GiB
storage_memory = 4GiB
# Performance tuning
knob_min_available_space_ratio = 0.01
EOF

    # Start FDB server
    service foundationdb start
    
    # Wait for server to start
    sleep 5
    
    # Configure the cluster
    fdbcli --exec "configure new single ssd" || true
    
    # Make the cluster file readable
    chmod 644 ${CLUSTER_FILE}
    
    echo "FoundationDB cluster initialized!"
else
    # Other nodes - join existing cluster
    echo "Joining existing FoundationDB cluster..."
    
    # Wait for first node to be ready
    sleep 30
    
    # Copy cluster file from first node (via internal network)
    # In production, use Secret Manager or shared storage
    cat > /etc/foundationdb/foundationdb.conf <<EOF
[fdbserver]
command = /usr/sbin/fdbserver
public_address = auto:4500
listen_address = public
data_dir = /var/lib/foundationdb/data
log_dir = /var/log/foundationdb
memory = 8GiB
storage_memory = 4GiB
knob_min_available_space_ratio = 0.01
EOF

    # Start FDB server
    service foundationdb start
fi

# Configure backup (optional)
if [ "${FDB_ID}" = "1" ]; then
    # Setup backup agent on first node
    cat >> /etc/foundationdb/foundationdb.conf <<EOF

[backup_agent]
command = /usr/lib/foundationdb/backup_agent/backup_agent
log_dir = /var/log/foundationdb
EOF
fi

# Setup monitoring
pip3 install foundationdb

# Create monitoring script
cat > /usr/local/bin/fdb-monitor.sh <<'EOF'
#!/bin/bash
# FoundationDB monitoring script

while true; do
    STATUS=$(fdbcli --exec "status" 2>/dev/null || echo "UNHEALTHY")
    echo "$(date): $STATUS" >> /var/log/foundationdb/monitor.log
    sleep 60
done
EOF
chmod +x /usr/local/bin/fdb-monitor.sh

# Create systemd service for monitoring
cat > /etc/systemd/system/fdb-monitor.service <<EOF
[Unit]
Description=FoundationDB Monitoring
After=foundationdb.service

[Service]
Type=simple
ExecStart=/usr/local/bin/fdb-monitor.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Enable and start services
systemctl daemon-reload
systemctl enable foundationdb
systemctl enable fdb-monitor
systemctl start fdb-monitor || true

echo "========================================"
echo "FoundationDB setup completed!"
echo "========================================"
echo "Checking cluster status..."
sleep 5

# Check status
fdbcli --exec "status" || echo "Cluster may still be initializing..."

echo ""
echo "FoundationDB ${FDB_ID} is ready!"
echo "Cluster file: ${CLUSTER_FILE}"
echo "Data directory: /var/lib/foundationdb/data"
echo "Log directory: /var/log/foundationdb"
echo "========================================"
