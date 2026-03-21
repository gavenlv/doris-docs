# Doris 2.1.7 GKE Deployment Guide

## Overview

This guide covers deploying Doris 2.1.7 on Google Kubernetes Engine (GKE).

## Prerequisites

1. GKE cluster (version 1.24+)
2. kubectl configured
3. Images pushed to Nexus registry
4. Sufficient quota (16+ cores, 64GB+ memory per node pool)

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     GKE Cluster                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │   FE Pod   │  │   FE Pod    │  │   FE Pod    │         │
│  │  (3 replicas)              │  └─────────────┘         │
│  └─────────────┘                                            │
│                                                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │   BE Pod   │  │   BE Pod    │  │   BE Pod    │         │
│  │  (6+ replicas)             │  └─────────────┘         │
│  └─────────────┘                                            │
└─────────────────────────────────────────────────────────────┘
```

## Step 1: Prepare Images

Images must be available in your private registry:

```bash
# Verify images exist
docker images | grep nexus.company.com:8082/doris

# Expected output:
# nexus.company.com:8082/doris/fe:4.0.4-secure
# nexus.company.com:8082/doris/be:4.0.4-secure
```

## Step 2: Create Namespace

```bash
kubectl apply -f kubernetes/namespace.yaml
```

## Step 3: Configure Storage

For production, use PersistentVolumeClaim:

```bash
kubectl apply -f kubernetes/storage/storage-class.yaml
```

## Step 4: Deploy FE

```bash
kubectl apply -f kubernetes/doris-cluster/fe.yaml
```

Verify FE deployment:

```bash
kubectl get pods -n doris -l component=fe
kubectl get svc -n doris -l component=fe
```

## Step 5: Deploy BE

```bash
kubectl apply -f kubernetes/doris-cluster/be.yaml
```

Verify BE deployment:

```bash
kubectl get pods -n doris -l component=be
kubectl get svc -n doris -l component=be
```

## Step 6: Initialize Cluster

Connect to FE and add BE nodes:

```bash
# Get FE MySQL port
kubectl port-forward -n doris svc/doris-fe 9030:9030

# Connect via MySQL client
mysql -h 127.0.0.1 -P 9030 -u root

# Add BE nodes
ALTER SYSTEM ADD BACKEND "doris-be-0.doris-be.doris.svc.cluster.local:9050";
ALTER SYSTEM ADD BACKEND "doris-be-1.doris-be.doris.svc.cluster.local:9050";
ALTER SYSTEM ADD BACKEND "doris-be-2.doris-be.doris.svc.cluster.local:9050";
# ... add more BEs as needed
```

## Step 7: Verify Deployment

```sql
-- Check cluster status
SHOW FRONTENDS;
SHOW BACKENDS;

-- Check tablet distribution
SHOW PROC '/statistic';
```

## Configuration

### Resource Limits

Adjust based on your workload:

```yaml
# FE resources
resources:
  requests:
    cpu: "4"
    memory: "16Gi"
  limits:
    cpu: "8"
    memory: "32Gi"

# BE resources
resources:
  requests:
    cpu: "8"
    memory: "32Gi"
  limits:
    cpu: "16"
    memory: "64Gi"
```

### Scaling

```bash
# Scale FE
kubectl scale deployment doris-fe -n doris --replicas=5

# Scale BE
kubectl scale deployment doris-be -n doris --replicas=10
```

## Troubleshooting

### FE Won't Start

```bash
# Check logs
kubectl logs -n doris -l component=fe

# Check events
kubectl describe pod -n doris -l component=fe
```

### BE Can't Connect to FE

```sql
-- In MySQL client
SHOW BACKENDS\G

-- Check Alive column
-- If false, check network policies
```

### Out of Memory

Increase memory limits in deployment YAML:

```yaml
resources:
  limits:
    memory: "64Gi"
```

## Backup

### Metadata Backup

```bash
# On FE pod
kubectl exec -n doris doris-fe-0 -- \
  /opt/doris/fe/bin/mysql_backup.sh
```

### Data Backup

Use EXPORT command:

```sql
EXPORT TABLE db1.table1 TO "s3://bucket/backup/";
```

## Monitoring

### View Metrics

```bash
# Port forward FE metrics
kubectl port-forward -n doris svc/doris-fe 8030:8030

# Access in browser
http://localhost:8030/metrics
```

### Prometheus Integration

Add annotations to enable Prometheus scraping:

```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8030"
  prometheus.io/path: "/metrics"
```
