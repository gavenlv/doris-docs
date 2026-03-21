# Doris GKE Cluster - Security Hardened Image Build (Version 2.1.7)

## Overview

This project builds security-hardened Apache Doris 2.1.7 images from Ubuntu base images, with integrated security scanning and vulnerability remediation.

## Important Note on Version

**Doris 4.0.4 only has source code packages, no binary packages available.**

This project uses **Doris 2.1.7** (latest stable version with binary packages):

| Version | Package | Download |
|---------|---------|----------|
| **2.1.7** | Binary (2.1GB) | ✅ Available |
| **4.0.4** | Source only | ❌ No binary |

## Version Information

- **Doris**: 2.1.7
- **Package**: `apache-doris-2.1.7-bin-x64.tar.gz`
- **Download**: https://apache-doris-releases.oss-accelerate.aliyuncs.com/apache-doris-2.1.7-bin-x64.tar.gz

## Quick Start

### Option 1: One-Click Local Setup (Recommended)

```powershell
# Windows - Run in project root
.\verify.bat
```

### Option 2: Step-by-Step

1. Download Doris 2.1.7 package:
```powershell
mkdir offline-packages
Invoke-WebRequest -Uri "https://apache-doris-releases.oss-accelerate.aliyuncs.com/apache-doris-2.1.7-bin-x64.tar.gz" -OutFile "offline-packages\apache-doris-2.1.7-bin-x64.tar.gz"
```

2. Build images:
```bash
cd docker/fe && docker build --build-arg DORIS_VERSION=2.1.7 -t doris-fe:2.1.7 .
cd docker/be && docker build --build-arg DORIS_VERSION=2.1.7 -t doris-be:2.1.7 .
```

3. Start local cluster:
```bash
docker-compose -f docker-compose-local.yaml up -d
```

## Directory Structure

```
doris-gke-cluster-v4/
├── docker/
│   ├── fe/Dockerfile           # FE Image (Ubuntu 22.04)
│   ├── be/Dockerfile           # BE Image (Ubuntu 22.04)
│   └── fdb/Dockerfile          # FoundationDB Image
├── docker-compose.yaml         # Nexus + Test Containers
├── docker-compose-local.yaml   # Local Doris Cluster (FE + BE)
├── scripts/                    # Build scripts
├── kubernetes/                 # K8s configurations
├── configs/                   # Build configs
├── docs/                       # Documentation
├── offline-packages/           # Downloaded packages
└── README.md
```

## Documentation

- [Quick Start](QUICK-START.md)
- [Download Guide](DOWNLOAD-GUIDE.md)
- [Local Verification](docs/LOCAL-VERIFY.md)
- [Security Hardening](docs/SECURITY-HARDENING.md)
- [Deployment Guide](docs/DEPLOYMENT-GUIDE.md)

## Local Development

Start a local Doris cluster for testing:

```bash
# Start FE + BE
docker-compose -f docker-compose-local.yaml up -d

# Check status
docker-compose -f docker-compose-local.yaml ps

# View logs
docker-compose -f docker-compose-local.yaml logs -f

# Connect to Doris
mysql -h127.0.0.1 -P9030 -uroot

# Stop cluster
docker-compose -f docker-compose-local.yaml down
```

## Access Points

| Service | URL | Description |
|---------|-----|-------------|
| FE Web UI | http://localhost:8030 | Frontend Admin |
| BE Web UI | http://localhost:8040 | Backend Admin |
| MySQL | mysql -h127.0.0.1 -P9030 -uroot | SQL Client |

## Security Features

1. **Multi-stage Build** - Runtime images contain no build tools
2. **Non-root User** - All containers run as non-root
3. **Minimal Dependencies** - Only runtime libraries included
4. **Trivy Scanning** - Full vulnerability scan before deployment

## References

- [Doris Official Documentation](https://doris.apache.org/docs/)
- [Doris GitHub](https://github.com/apache/doris)
- [Apache Doris Downloads](https://doris.apache.org/zh-CN/download)
