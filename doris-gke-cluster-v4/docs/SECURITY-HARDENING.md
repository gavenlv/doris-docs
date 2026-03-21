# Doris 2.1.7 Security Hardening Guide

## Overview

This document describes security hardening measures applied to Doris 2.1.7 images.

## Security Measures

### 1. Multi-Stage Build

```dockerfile
# Stage 1: Download and extract (with build tools)
FROM ubuntu:22.04 AS downloader
RUN apt-get install -y wget tar gzip

# Stage 2: Runtime (no build tools)
FROM ubuntu:22.04
# Only runtime dependencies
RUN apt-get install -y openjdk-17-jre-headless tzdata curl
```

**Benefit**: Runtime image contains no build tools (wget, tar, etc.)

### 2. Non-Root User

```dockerfile
# Create non-root user
RUN groupadd -r doris && useradd -r -g doris -d /opt/doris -s /sbin/nologin doris

# Switch to non-root user
USER doris
```

**Benefit**: Containers run as non-root, limiting privilege escalation

### 3. Minimal Dependencies

```dockerfile
# FE runtime dependencies
RUN apt-get install -y --no-install-recommends \
    openjdk-17-jre-headless \
    tzdata \
    curl

# BE runtime dependencies
RUN apt-get install -y --no-install-recommends \
    libstdc++6 \
    tzdata \
    curl
```

**Benefit**: Minimal attack surface, fewer vulnerabilities

### 4. File Permissions

```dockerfile
# Restrict file access
RUN chmod -R 750 /opt/doris/fe && \
    find /opt/doris/fe -type f -exec chmod 640 {} \; && \
    find /opt/doris/fe/bin -type f -exec chmod 750 {} \;
```

**Benefit**: Files only accessible to owner and group

### 5. Remove Unnecessary Files

```dockerfile
# Remove documentation and licenses
RUN rm -rf /opt/doris/fe/*.md \
           /opt/doris/fe/NOTICE \
           /opt/doris/fe/LICENSE
```

**Benefit**: Smaller image, fewer files to audit

### 6. Health Checks

```dockerfile
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8030/api/health || exit 1
```

**Benefit**: Kubernetes can detect unhealthy containers

## Security Scanning

### Trivy Scan

```bash
# Scan FE image
trivy image --severity HIGH,CRITICAL doris-fe:4.0.4

# Scan BE image
trivy image --severity HIGH,CRITICAL doris-be:4.0.4

# Generate report
trivy image --format json --output reports/trivy-report.json doris-fe:4.0.4
```

### Scan Before Push

The build script automatically scans images before pushing to Nexus.

```bash
# Interactive scan
./scripts/scan-images.sh all

# View report
cat reports/security-scan-report.txt
```

## Vulnerability Remediation

### High/Critical Vulnerabilities

If Trivy reports HIGH or CRITICAL vulnerabilities:

1. Update base image
2. Rebuild with fixed packages
3. Re-scan
4. Only push when clean

### Package Updates

```dockerfile
# Update packages during build
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
```

## Compliance

### CIS Benchmarks

The hardened images follow CIS Docker Benchmark recommendations:
- No running as root
- Minimal image size
- No shell access
- Health checks configured

### Vulnerability Threshold

| Severity | Max Allowed |
|----------|-------------|
| CRITICAL | 0 |
| HIGH | 0 |
| MEDIUM | 10 |
| LOW | 50 |

## Verification

```bash
# Verify non-root user
docker run --rm doris-fe:4.0.4 id
# Expected: uid=1000(doris)

# Verify no build tools
docker run --rm doris-fe:4.0.4 which wget
# Expected: no output (wget not found)

# Verify file permissions
docker run --rm doris-fe:4.0.4 ls -la /opt/doris/fe
# Expected: drwxr-x--- (750) for directories

# Run security scan
trivy image doris-fe:4.0.4
```

## Best Practices

1. **Always scan** before production deployment
2. **Keep images updated** with latest security patches
3. **Use private registry** (Nexus) for image storage
4. **Sign images** with Docker Content Trust
5. **Regular audits** of running containers
