# Doris High-Performance Cluster Architecture

## Overview

This document describes the architecture for a high-performance Doris cluster on GCP, designed to handle:

- **Data Volume**: 100 billion rows
- **Import Throughput**: 50 billion rows per 2 minutes
- **Query Latency**: < 10 seconds for star schema queries
- **Concurrency**: 50 concurrent users

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Client Layer                                    │
│  (MySQL Client / JDBC / ODBC / Python / BI Tools / Stream Load)             │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Internal Load Balancer                               │
│                    (MySQL:9030, HTTP:8030)                                   │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                    ┌───────────────┼───────────────┐
                    ▼               ▼               ▼
┌──────────────────────┐ ┌──────────────────────┐ ┌──────────────────────┐
│      FE Leader       │ │     FE Follower      │ │     FE Follower      │
│   n2-standard-8      │ │   n2-standard-8      │ │   n2-standard-8      │
│   8 vCPU / 32GB      │ │   8 vCPU / 32GB      │ │   8 vCPU / 32GB      │
│   100GB PD-SSD       │ │   100GB PD-SSD       │ │   100GB PD-SSD       │
└──────────────────────┘ └──────────────────────┘ └──────────────────────┘
                    │               │               │
                    └───────────────┼───────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         BE Compute Layer                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    Core BE Pool (Non-Preemptible)                    │   │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐       │   │
│  │  │ BE-01   │ │ BE-02   │ │ BE-03   │ │ BE-04   │ │ BE-05   │       │   │
│  │  │c2-std-30│ │c2-std-30│ │c2-std-30│ │c2-std-30│ │c2-std-30│       │   │
│  │  │30vCPU   │ │30vCPU   │ │30vCPU   │ │30vCPU   │ │30vCPU   │       │   │
│  │  │120GB    │ │120GB    │ │120GB    │ │120GB    │ │120GB    │       │   │
│  │  │3TB SSD  │ │3TB SSD  │ │3TB SSD  │ │3TB SSD  │ │3TB SSD  │       │   │
│  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘       │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                  Elastic BE Pool (Preemptible)                       │   │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐       ┌─────────┐ ┌─────────┐ │   │
│  │  │ BE-06   │ │ BE-07   │ │ BE-08   │  ...  │ BE-29   │ │ BE-30   │ │   │
│  │  │c2-std-30│ │c2-std-30│ │c2-std-30│       │c2-std-30│ │c2-std-30│ │   │
│  │  │Preempt  │ │Preempt  │ │Preempt  │       │Preempt  │ │Preempt  │ │   │
│  │  └─────────┘ └─────────┘ └─────────┘       └─────────┘ └─────────┘ │   │
│  │                     Scale: 0-25 instances                           │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                            Storage Layer                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────┐  ┌─────────────────────────────┐          │
│  │     Local SSD (Hot)         │  │      GCS (Cold)             │          │
│  │  8x 375GB NVMe per BE       │  │  Standard/Nearline          │          │
│  │  Total: 3TB per node        │  │  Lifecycle: 30 days         │          │
│  │  IOPS: 400K+ per device     │  │  Cost: $0.02/GB/month       │          │
│  └─────────────────────────────┘  └─────────────────────────────┘          │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Component Specifications

### FE (Frontend) Nodes

| Parameter | Value |
|-----------|-------|
| Instance Type | n2-standard-8 |
| vCPU | 8 |
| Memory | 32 GB |
| Disk | 100 GB PD-SSD |
| Count | 3 (HA) |
| Preemptible | No |

### BE (Backend) Core Nodes

| Parameter | Value |
|-----------|-------|
| Instance Type | c2-standard-30 |
| vCPU | 30 |
| Memory | 120 GB |
| Local SSD | 8x 375GB NVMe (3TB total) |
| Count | 5 (minimum) |
| Preemptible | No |

### BE (Backend) Elastic Nodes

| Parameter | Value |
|-----------|-------|
| Instance Type | c2-standard-30 |
| vCPU | 30 |
| Memory | 120 GB |
| Local SSD | 8x 375GB NVMe (3TB total) |
| Count | 0-25 (auto-scaling) |
| Preemptible | Yes (60% cost savings) |

## Performance Optimization

### 1. Local SSD Configuration

```bash
# Create RAID0 array for maximum performance
mdadm --create /dev/md0 --level=0 --raid-devices=8 \
    /dev/nvme0n1 /dev/nvme0n2 /dev/nvme0n3 /dev/nvme0n4 \
    /dev/nvme0n5 /dev/nvme0n6 /dev/nvme0n7 /dev/nvme0n8

# Format with XFS
mkfs.xfs -f /dev/md0

# Mount with optimized options
mount -o noatime,nodiratime /dev/md0 /opt/doris/be/storage
```

### 2. System Tuning

```bash
# Kernel parameters
sysctl -w vm.swappiness=0
sysctl -w vm.max_map_count=2000000
sysctl -w vm.dirty_ratio=80
sysctl -w vm.dirty_background_ratio=5
sysctl -w fs.file-max=655360

# Disable transparent huge pages
echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo never > /sys/kernel/mm/transparent_hugepage/defrag

# File descriptor limits
ulimit -n 655350
```

### 3. BE Configuration

```properties
# Memory
mem_limit = 100GB
query_memory_limit = 80GB
storage_page_cache_limit = 40GB

# Thread pools
scan_thread_pool_thread_num = 64
fragment_pool_thread_num_max = 256

# Compaction
base_compaction_num_threads_per_disk = 32
cumulative_compaction_num_threads_per_disk = 32

# Import
streaming_load_max_mb = 10240
streaming_load_rpc_max_alive_time_sec = 1200
max_send_batch_parallelism_per_job = 20
```

### 4. FE Configuration

```properties
# Query
query_timeout = 600
max_running_query_num = 200
query_cache_capacity = 20GB

# Load
max_load_timeout_second = 3600
default_load_parallelism = 16

# Performance
enable_pipeline_engine = true
runtime_filter_mode = GLOBAL
parallel_fragment_exec_instance_num = 8
```

## Data Model Design

### Fact Table (90 columns)

```sql
CREATE TABLE fact_events (
    event_id BIGINT,
    event_time DATETIME,
    dt DATE,
    user_id BIGINT,
    
    -- Dimension keys
    dim_key1 INT,
    dim_key2 INT,
    -- ... 86 more columns
    
    -- Metrics
    metric1 DOUBLE,
    metric2 DOUBLE
)
PARTITION BY RANGE(dt) (
    FROM ("2024-01-01") TO ("2025-01-01") INTERVAL 1 MONTH
)
DISTRIBUTED BY HASH(user_id) BUCKETS 128
PROPERTIES (
    "replication_num" = "2",
    "enable_unique_key_merge_on_write" = "true",
    "light_schema_change" = "true",
    "compression" = "LZ4"
);
```

### Dimension Table (Colocate Group)

```sql
CREATE TABLE dim_user (
    user_id BIGINT,
    user_name VARCHAR(100),
    -- ... other attributes
)
DISTRIBUTED BY HASH(user_id) BUCKETS 128
PROPERTIES (
    "replication_num" = "3",
    "colocate_with" = "fact_events_group"
);
```

## Import Strategy

### Stream Load (Real-time)

```bash
# Parallel import with 20 concurrent tasks
for i in {1..20}; do
    curl --location-trusted -u root: \
        -H "label:batch_${i}_$(date +%s)" \
        -H "column_separator:," \
        -H "max_filter_ratio:0.1" \
        -T data_batch_${i}.csv \
        http://lb-ip:8030/api/db/table/_stream_load &
done
wait
```

### Broker Load (Batch)

```sql
LOAD LABEL batch_load_$(date +%Y%m%d)
(
    DATA INFILE("gs://bucket/data/*.parquet")
    INTO TABLE fact_events
    FORMAT AS "parquet"
)
WITH BROKER gcs_broker
(
    "gcs_endpoint" = "storage.googleapis.com"
)
PROPERTIES (
    "timeout" = "3600",
    "max_filter_ratio" = "0.1"
);
```

## Auto-Scaling Strategy

### Time-Based Scaling

| Time Window | BE Count | Trigger |
|-------------|----------|---------|
| 08:00 - 22:00 (Busy) | 25 | Scheduled |
| 22:00 - 08:00 (Off) | 8 | Scheduled |
| Import Window | 30 | On-demand |

### CPU-Based Scaling

| Metric | Scale Up | Scale Down |
|--------|----------|------------|
| CPU > 50% | +2 nodes | - |
| CPU < 30% | - | -1 node |
| Cooldown | 3 min | 10 min |

## Cost Estimation

### Monthly Cost Breakdown

| Component | Configuration | Monthly Cost |
|-----------|---------------|--------------|
| FE (3x n2-standard-8) | Non-preemptible | $600 |
| BE Core (5x c2-standard-30) | Non-preemptible | $2,500 |
| BE Elastic (15x avg) | Preemptible | $1,500 |
| Local SSD (8x375GB x 20) | NVMe | $800 |
| GCS Storage (10TB) | Standard | $200 |
| Network (1TB egress) | Premium | $100 |
| **Total** | | **~$5,700/month** |

### Cost Savings

| Strategy | Savings |
|----------|---------|
| Preemptible BE | 60% off BE elastic |
| Committed Use (1 year) | 37% off |
| Sustained Use | 20-30% off |
| **Total Potential Savings** | **~40%** |

## Monitoring

### Key Metrics

| Metric | Alert Threshold |
|--------|-----------------|
| BE CPU | > 80% for 5 min |
| BE Memory | > 90% for 5 min |
| Query Latency P99 | > 30s for 5 min |
| Import Latency | > 5 min for 5 min |
| Disk Usage | > 85% |
| Unhealthy Tablets | > 10 |

### Grafana Dashboard

- Query Performance: QPS, Latency, Error Rate
- Import Performance: Rows/s, Bytes/s, Success Rate
- Resource Usage: CPU, Memory, Disk, Network
- Cluster Health: FE/BE Status, Tablet Balance

## Deployment

### Quick Start

```bash
# 1. Copy configuration
cp terraform.tfvars.high-performance terraform.tfvars

# 2. Edit variables
vim terraform.tfvars
# Update: project_id, ssh_public_key_path, gcs_bucket_name

# 3. Deploy
./deploy.sh

# 4. Verify
mysql -h <lb-ip> -P 9030 -u root -e "SHOW BACKENDS;"
```

### Scale Operations

```bash
# Scale up BE
terraform apply -var="be_count=10"

# Scale down BE (with data migration)
terraform apply -var="be_count=3"
```

## Best Practices

### 1. Data Modeling

- Use Duplicate Key for fact tables with high cardinality
- Use Unique Key with MoW for dimension tables requiring updates
- Partition by date for time-series data
- Use 96-128 buckets for large tables

### 2. Query Optimization

- Always include partition key in WHERE clause
- Use Colocate Group for dimension tables
- Create materialized views for frequent aggregations
- Use Bloom Filter for high-cardinality columns

### 3. Import Optimization

- Use parallel Stream Load for real-time data
- Use Broker Load for batch data
- Set appropriate `max_filter_ratio`
- Use compression (LZ4) for network transfer

### 4. Cost Optimization

- Use Preemptible instances for elastic BE
- Implement time-based scaling
- Use GCS for cold data
- Monitor and right-size instances

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Import timeout | Data too large | Increase `streaming_load_rpc_max_alive_time_sec` |
| Query OOM | Memory limit | Reduce `parallel_fragment_exec_instance_num` |
| Slow compaction | Too many segments | Increase compaction threads |
| BE offline | Preemptible termination | Auto-healing with IGM |

## References

- [Doris Official Documentation](https://doris.apache.org/docs/)
- [GCP Compute Optimized Instances](https://cloud.google.com/compute/docs/machine-types#c2_machine_types)
- [GCP Local SSD](https://cloud.google.com/compute/docs/disks/local-ssd)
- [GCP Preemptible VMs](https://cloud.google.com/compute/docs/instances/preemptible)
