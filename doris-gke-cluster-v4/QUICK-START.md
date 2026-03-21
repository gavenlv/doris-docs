# Doris 2.1.7 Quick Start Guide

## Prerequisites

- Docker installed and running
- 8GB+ RAM available
- 50GB+ disk space

## Step 1: Download Doris Package

```powershell
# Create offline packages directory
mkdir offline-packages

# Download Doris 2.1.7 (unified binary package)
Invoke-WebRequest -Uri "https://apache-doris-releases.oss-accelerate.aliyuncs.com/apache-doris-2.1.7-bin-x64.tar.gz" -OutFile "offline-packages\apache-doris-2.1.7-bin-x64.tar.gz"
```

**Package size**: ~2.1GB

## Step 2: Build Docker Images

```bash
# Build FE image
cd docker/fe
docker build --build-arg DORIS_VERSION=2.1.7 --build-arg OFFLINE_PATH=../../offline-packages -t doris-fe:2.1.7 .

# Build BE image
cd ../be
docker build --build-arg DORIS_VERSION=2.1.7 --build-arg OFFLINE_PATH=../../offline-packages -t doris-be:2.1.7 .
```

## Step 3: Start Local Cluster

```bash
# Start FE + BE
docker-compose -f docker-compose-local.yaml up -d

# Wait for services to be ready (about 2 minutes)
sleep 120

# Check status
docker-compose -f docker-compose-local.yaml ps
```

## Step 4: Verify Installation

### Check FE Health
```bash
curl http://localhost:8030/api/health
```

### Check BE Health
```bash
curl http://localhost:8040/api/health
```

### Connect to Doris
```bash
docker exec -it doris-local-fe mysql -h127.0.0.1 -P9030 -uroot
```

### Add BE to Cluster
```sql
-- In MySQL client
ALTER SYSTEM ADD BACKEND "doris-be:9050";
SHOW BACKENDS;
```

## Step 5: Create Test Table

```sql
CREATE DATABASE test_db;

USE test_db;

CREATE TABLE example_table (
    id BIGINT,
    name VARCHAR(100),
    score INT
) DUPLICATE KEY (id)
DISTRIBUTED BY HASH(id) BUCKETS 10
PROPERTIES (
    "replication_num" = "1"
);

INSERT INTO example_table VALUES (1, 'test', 100);
SELECT * FROM example_table;
```

## Troubleshooting

### FE Won't Start
```bash
# Check FE logs
docker-compose -f docker-compose-local.yaml logs doris-fe

# Check if port is in use
netstat -an | grep 8030
```

### BE Won't Start
```bash
# Check BE logs
docker-compose -f docker-compose-local.yaml logs doris-be

# Check if port is in use
netstat -an | grep 9050
```

### Can't Connect to MySQL
```bash
# Verify FE is running
docker ps | grep doris-fe

# Check MySQL port
netstat -an | grep 9030
```

## Next Steps

- [Local Verification](docs/LOCAL-VERIFY.md)
- [Security Hardening](docs/SECURITY-HARDENING.md)
- [Deployment Guide](docs/DEPLOYMENT-GUIDE.md)
