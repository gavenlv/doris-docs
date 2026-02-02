# Doris GCP 内网部署指南

## 概述

本配置支持在 **GCP 私有网络** 中部署 Doris 集群，VM 实例**不直接访问互联网**，所有安装包从内部 GCS Bucket 下载。

## 架构特点

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           GCP Project                                    │
│                                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                    Private VPC Network                            │  │
│  │                     (No Internet Access)                          │  │
│  │                                                                   │  │
│  │  ┌───────────────────────────────────────────────────────────┐   │  │
│  │  │              GCS Artifacts Bucket                          │   │  │
│  │  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐          │   │  │
│  │  │  │ Doris FE    │ │ Doris BE    │ │ FoundationDB│          │   │  │
│  │  │  │ Package     │ │ Package     │ │ Packages    │          │   │  │
│  │  │  └─────────────┘ └─────────────┘ └─────────────┘          │   │  │
│  │  │  ┌─────────────┐ ┌─────────────┐                          │   │  │
│  │  │  │ gcsfuse     │ │ Java JDK    │                          │   │  │
│  │  │  │ Package     │ │ (via GCS)   │                          │   │  │
│  │  │  └─────────────┘ └─────────────┘                          │   │  │
│  │  └───────────────────────────────────────────────────────────┘   │  │
│  │                              ▲                                    │  │
│  │                              │ (Private Google Access)           │  │
│  │  ┌───────────────────────────┴───────────────────────────────┐   │  │
│  │  │                   Subnet (Private)                         │   │  │
│  │  │              10.x.0.0/16 (Private Google Access)           │   │  │
│  │  │                                                           │   │  │
│  │  │   ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌────────┐  │   │  │
│  │  │   │  FE-1   │   │  FE-2   │   │  BE-1   │   │ FDB-1  │  │   │  │
│  │  │   │ (No     │   │ (No     │   │ (No     │   │ (No    │  │   │  │
│  │  │   │ Public  │   │ Public  │   │ Public  │   │ Public │  │   │  │
│  │  │   │  IP)    │   │  IP)    │   │  IP)    │   │  IP)   │  │   │  │
│  │  │   └────┬────┘   └────┬────┘   └────┬────┘   └───┬────┘  │   │  │
│  │  │        └─────────────┴─────────────┴─────────────┘       │   │  │
│  │  │                          │                                │   │  │
│  │  │                          ▼                                │   │  │
│  │  │   ┌─────────────────────────────────────────────────┐    │   │  │
│  │  │   │         Cloud NAT (Optional)                     │    │   │  │
│  │  │   │  - Only for Google API access (GCS)             │    │   │  │
│  │  │   │  - No inbound internet access                   │    │   │  │
│  │  │   └─────────────────────────────────────────────────┘    │   │  │
│  │  └──────────────────────────────────────────────────────────┘   │  │
│  └──────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

## 部署流程

### 步骤 1: 准备（在有互联网的机器上执行）

```bash
# 1. 克隆代码仓库
git clone <repository>
cd doris-gcp-cluster-separation

# 2. 配置环境变量
export ENVIRONMENT=dev  # 或 sit/uat/prod

# 3. 上传安装包到 GCS
# 此脚本会下载所有需要的安装包并上传到 GCS Bucket
./upload-artifacts.sh ${ENVIRONMENT}
```

**upload-artifacts.sh 会下载并上传以下包：**

| 组件 | 包名 | 来源 |
|------|------|------|
| Doris FE | apache-doris-fe-4.0.2-bin-x86_64.tar.gz | Apache 官网 |
| Doris BE | apache-doris-be-4.0.2-bin-x86_64.tar.gz | Apache 官网 |
| FoundationDB Client | foundationdb-clients_7.3.27-1_amd64.deb | GitHub Releases |
| FoundationDB Server | foundationdb-server_7.3.27-1_amd64.deb | GitHub Releases |
| gcsfuse | gcsfuse_latest_amd64.deb | GitHub Releases |

### 步骤 2: 创建 GCS Bucket（如果尚未创建）

```bash
# 创建存储桶
BUCKET_NAME="doris-${ENVIRONMENT}-separation-artifacts"
gsutil mb -l us-central1 "gs://${BUCKET_NAME}"

# 设置访问控制
gsutil uniformbucketlevelaccess set on "gs://${BUCKET_NAME}"
```

### 步骤 3: 部署集群（在 VPC 内执行）

```bash
# 1. 确保 VM 可以访问 GCS
# VM 需要具备以下条件：
# - 位于 VPC 子网中
# - 子网启用 Private Google Access
# - 具备访问 GCS 的 Service Account 权限

# 2. 部署集群
./deploy.sh ${ENVIRONMENT}
```

## 网络配置

### 1. VPC 网络设置

```hcl
# main.tf 中的网络配置
resource "google_compute_network" "doris_network" {
  name                    = "${local.cluster_name}-network"
  auto_create_subnetworks = false  # 手动管理子网
}

resource "google_compute_subnetwork" "doris_subnet" {
  name                     = "${local.cluster_name}-subnet"
  ip_cidr_range            = var.subnet_cidr
  network                  = google_compute_network.doris_network.id
  region                   = var.region
  private_ip_google_access = true  # 允许访问 Google API（GCS）
}
```

### 2. Cloud NAT（可选）

如果 VM 需要访问 GCS，但不希望有公网 IP：

```hcl
resource "google_compute_router" "router" {
  name    = "${local.cluster_name}-router"
  region  = var.region
  network = google_compute_network.doris_network.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "${local.cluster_name}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}
```

**注意：**
- Cloud NAT 仅用于出站连接（访问 GCS）
- 不允许入站互联网连接
- VM 没有公网 IP

### 3. Service Account 权限

VM 使用的 Service Account 需要以下权限：

```hcl
# 访问 GCS Bucket
roles/storage.objectViewer  # 读取安装包

# 访问 Secret Manager（如果存储 FDB 配置）
roles/secretmanager.secretAccessor
```

## 安装包下载流程

### 传统部署（有互联网）

```
VM ──► Internet ──► Apache/GitHub ──► 下载安装包
```

### 内网部署（无互联网）

```
VM ──► VPC ──► Private Google Access ──► GCS Bucket ──► 下载安装包
         │
         └──► Cloud NAT (仅出站，可选)
```

## user-data 脚本修改

### 修改前（有互联网）

```bash
# 从互联网下载
wget https://archive.apache.org/dist/doris/4.0.2/apache-doris-fe-4.0.2-bin-x86_64.tar.gz
```

### 修改后（内网）

```bash
# 从 GCS 下载
ARTIFACTS_BUCKET="${gcs_bucket}-artifacts"
gsutil cp "gs://${ARTIFACTS_BUCKET}/doris/apache-doris-fe-4.0.2-bin-x86_64.tar.gz" /tmp/
```

## 安全优势

1. **无公网暴露**: VM 没有公网 IP，无法从互联网直接访问
2. **受控访问**: 只有通过 VPC 和 IAM 授权的服务才能访问 VM
3. **审计日志**: 所有 GCS 访问都有日志记录
4. **包完整性**: 安装包存储在受控的 GCS Bucket 中，可验证校验和

## 故障排查

### 无法访问 GCS

```bash
# 在 VM 上执行

# 1. 检查网络连接
ping storage.googleapis.com

# 2. 检查 Private Google Access
# 确保子网启用了 private_ip_google_access

gcloud compute networks subnets describe ${SUBNET_NAME} \
  --region=${REGION} \
  --format="value(privateIpGoogleAccess)"

# 3. 检查 Service Account 权限
gcloud auth list
gcloud projects get-iam-policy ${PROJECT_ID} \
  --flatten="bindings[].members" \
  --format="table(bindings.role)" \
  --filter="bindings.members:${SERVICE_ACCOUNT}"

# 4. 测试 GCS 访问
gsutil ls gs://${BUCKET_NAME}/
```

### 安装包下载失败

```bash
# 检查包是否存在
gsutil ls gs://${BUCKET_NAME}/doris/
gsutil ls gs://${BUCKET_NAME}/foundationdb/

# 检查权限
gsutil iam get gs://${BUCKET_NAME}/

# 手动下载测试
gsutil cp gs://${BUCKET_NAME}/doris/apache-doris-fe-4.0.2-bin-x86_64.tar.gz /tmp/test.tar.gz
```

### Cloud NAT 问题

```bash
# 检查 NAT 配置
gcloud compute routers nats describe ${NAT_NAME} \
  --router=${ROUTER_NAME} \
  --region=${REGION}

# 检查 NAT 日志
gcloud logging read "resource.type=nat_gateway" \
  --limit=50
```

## 最佳实践

### 1. 安装包版本管理

```bash
# 在 GCS 中使用版本目录结构
gs://${BUCKET_NAME}/
  doris/
    4.0.2/
      apache-doris-fe-4.0.2-bin-x86_64.tar.gz
      apache-doris-be-4.0.2-bin-x86_64.tar.gz
    4.0.3/
      ...
  foundationdb/
    7.3.27/
      ...
```

### 2. 包完整性验证

```bash
# 上传时计算校验和
md5sum apache-doris-fe-4.0.2-bin-x86_64.tar.gz > checksum.txt
gsutil cp checksum.txt gs://${BUCKET_NAME}/doris/

# 下载时验证
md5sum -c checksum.txt
```

### 3. 定期更新安装包

```bash
# 创建更新脚本
#!/bin/bash
# update-artifacts.sh

# 下载最新版本
NEW_VERSION="4.0.3"
./upload-artifacts.sh ${ENVIRONMENT} ${NEW_VERSION}

# 更新 Terraform 变量
sed -i "s/doris_version = .*/doris_version = \"${NEW_VERSION}\"/" terraform.tfvars.${ENVIRONMENT}
```

### 4. 多环境共享

```bash
# 不同环境可以使用同一个 Artifact Bucket
# 通过目录隔离

gs://${SHARED_BUCKET}/
  dev/
    doris/...
  sit/
    doris/...
  prod/
    doris/...
```

## 成本优化

### 1. GCS 存储类

```bash
# 安装包不经常访问，使用 Nearline 或 Coldline
gsutil rewrite -s nearline gs://${BUCKET_NAME}/**/*.tar.gz
```

### 2. 网络费用

- **同区域访问 GCS**: 免费
- **跨区域访问 GCS**: 收费
- **Cloud NAT**: 按出站流量收费

**建议**: Artifact Bucket 与集群部署在同一区域

## 总结

内网部署提供了更高的安全性：

✅ **无公网暴露**: VM 没有公网 IP
✅ **受控访问**: 通过 VPC 和 IAM 控制访问
✅ **包安全**: 安装包存储在受控 GCS Bucket
✅ **审计**: 完整的访问日志
✅ **合规**: 满足企业安全合规要求

适用于生产环境和对安全性要求高的场景。
