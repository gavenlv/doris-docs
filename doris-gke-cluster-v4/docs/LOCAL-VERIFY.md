# Doris 2.1.7 Local Verification Guide

## Overview

This guide helps you verify the Doris 2.1.7 security-hardened image build locally.

## Prerequisites

1. Docker Desktop installed and running
2. 10GB+ free disk space
3. Network access to download packages

## Verification Steps

### 1. Start Nexus

```bash
# Start Nexus container
docker run -d --name doris-nexus \
  -p 8081:8081 -p 8082:8082 \
  sonatype/nexus3:latest

# Wait for startup (2-3 minutes)
sleep 180
```

### 2. Login to Nexus

1. Open http://localhost:8081
2. Sign in with admin/adminadmin
3. Create docker-hosted repository on port 8082

### 3. Download Package

```powershell
# Download Doris 4.0.4
mkdir offline-packages
Invoke-WebRequest -Uri "https://apache-doris-releases.oss-accelerate.aliyuncs.com/apache-doris-4.0.4-bin-x64.tar.gz" -OutFile "offline-packages\apache-doris-4.0.4-bin-x64.tar.gz"
```

### 4. Build Images

```powershell
# Build FE
cd docker\fe
docker build --build-arg DORIS_VERSION=4.0.4 --build-arg OFFLINE_PATH=..\..\offline-packages -t doris-fe:4.0.4 .

# Build BE
cd ..\be
docker build --build-arg DORIS_VERSION=2.1.7 --build-arg OFFLINE_PATH=..\..\offline-packages -t doris-be:2.1.7 .
```

### 5. Push to Nexus

```powershell
# Login
docker login localhost:8082 -u admin -p adminadmin

# Tag and push
docker tag doris-fe:4.0.4 localhost:8082/doris/fe:4.0.4-secure
docker tag doris-be:4.0.4 localhost:8082/doris/be:4.0.4-secure
docker push localhost:8082/doris/fe:4.0.4-secure
docker push localhost:8082/doris/be:4.0.4-secure
```

### 6. Verify

```powershell
# Pull from Nexus
docker pull localhost:8082/doris/fe:4.0.4-secure
docker pull localhost:8082/doris/be:4.0.4-secure

# Run test containers
docker run -d --name test-fe doris-fe:4.0.4
docker run -d --name test-be doris-be:4.0.4

# Check logs
docker logs test-fe
docker logs test-be
```

## One-Click Verification

```powershell
# Run the verification script
.\verify.bat
```

## Troubleshooting

### Nexus Login Issues

```bash
# Get initial password
docker exec doris-nexus cat /nexus-data/admin.password

# If password file doesn't exist
docker exec -it doris-nexus bash
cd /opt/sonatype/nexus/bin
./nexus reset-admin-password
```

### Build Failures

```bash
# Check Docker is running
docker version

# Enable BuildKit for better caching
export DOCKER_BUILDKIT=1

# Clean and rebuild
docker builder prune -a
```

## Expected Results

| Check | Expected | Status |
|-------|----------|--------|
| Nexus Web UI | Accessible at localhost:8081 | ☐ |
| FE Image Built | doris-fe:4.0.4 exists | ☐ |
| BE Image Built | doris-be:4.0.4 exists | ☐ |
| Nexus Push | Images in nexus registry | ☐ |
| Pull Test | Can pull images from nexus | ☐ |
| Container Run | FE/BE containers start | ☐ |
