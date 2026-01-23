# Doris GCP 集群 Terraform 部署指南

## 概述

本部署方案使用 Terraform 在 Google Cloud Platform (GCP) 上部署 Doris 集群，提供多种配置方案：

| 配置方案 | FE 节点 | BE 节点 | 资源配置 | 适用场景 |
|---------|---------|---------|---------|---------|
| 1FE+2BE | 1 | 2 | e2-medium, e2-standard-2 | 本地测试，灵活扩展 |
| 2FE+2BE | 2 | 2 | e2-medium, e2-standard-2 | 测试环境，资源适中 |
| 3FE+3BE | 3 | 3 | e2-standard-2, e2-standard-4 | 生产环境，高可用 |

## 前置要求

### 1. 安装 Terraform

```bash
# macOS
brew install terraform

# Linux
wget https://releases.hashicorp.com/terraform/1.5.0/terraform_1.5.0_linux_amd64.zip
unzip terraform_1.5.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# Windows
# 下载并安装 Terraform
# https://developer.hashicorp.com/terraform/downloads
```

### 2. 配置 GCP 认证

```bash
# 安装 gcloud CLI
curl https://sdk.cloud.google.com | bash

# 认证
gcloud auth login

# 设置项目
gcloud config set project YOUR_PROJECT_ID

# 或者使用服务账号
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account-key.json"
```

### 3. 准备 SSH 密钥

```bash
# 生成 SSH 密钥对
ssh-keygen -t rsa -b 4096 -C "your-email@example.com"

# 公钥路径
~/.ssh/id_rsa.pub

# 私钥路径
~/.ssh/id_rsa
```

## 快速开始

### 1. 选择部署方案

#### 方案 1: 1FE+2BE (本地测试，可扩展)
- **配置**: 1 个 FE + 2 个 BE
- **资源**: e2-medium (FE), e2-standard-2 (BE)
- **磁盘**: 50GB (FE), 100GB (BE)
- **抢占式实例**: 是（成本优化）
- **启动**: `terraform apply -var-file=terraform.tfvars.1fe2be`

#### 方案 2: 2FE+2BE (测试环境)
- **配置**: 2 个 FE + 2 个 BE
- **资源**: e2-medium (FE), e2-standard-2 (BE)
- **磁盘**: 50GB (FE), 100GB (BE)
- **抢占式实例**: 是（成本优化）
- **启动**: `terraform apply -var-file=terraform.tfvars.2fe2be`

#### 方案 3: 3FE+3BE (生产环境)
- **配置**: 3 个 FE + 3 个 BE
- **资源**: e2-standard-2 (FE), e2-standard-4 (BE)
- **磁盘**: 100GB (FE), 200GB (BE)
- **抢占式实例**: 否（高可用）
- **启动**: `terraform apply -var-file=terraform.tfvars.3fe3be`

### 2. 配置变量

编辑对应的 `.tfvars` 文件，修改以下参数：

```bash
# GCP 项目 ID（必须）
project_id = "your-project-id"

# SSH 公钥路径（必须）
ssh_public_key_path = "~/.ssh/id_rsa.pub"

# 可选配置
region = "us-central1"
zone = "us-central1-a"
cluster_name = "doris"
environment = "dev"
```

### 3. 初始化 Terraform

```bash
cd doris-gcp-cluster
terraform init
```

### 4. 部署集群

```bash
# 方案 1: 1FE+2BE
terraform apply -var-file=terraform.tfvars.1fe2be

# 方案 2: 2FE+2BE
terraform apply -var-file=terraform.tfvars.2fe2be

# 方案 3: 3FE+3BE
terraform apply -var-file=terraform.tfvars.3fe3be
```

### 5. 获取连接信息

部署完成后，Terraform 会输出连接信息：

```bash
terraform output connection_info
```

示例输出：
```json
{
  "be_count": 2,
  "be_ips": ["34.123.45.67", "34.123.45.68"],
  "be_port": "9050",
  "fe_count": 1,
  "fe_ips": ["34.123.45.66"],
  "fe_port": "9030",
  "ssh_user": "ubuntu"
}
```

### 6. 连接到集群

#### 通过 MySQL 客户端连接

```bash
mysql -h <FE_PUBLIC_IP> -P 9030 -u root
```

#### 通过 SSH 连接

```bash
# 连接到 FE
ssh -i ~/.ssh/id_rsa ubuntu@<FE_PUBLIC_IP>

# 连接到 BE
ssh -i ~/.ssh/id_rsa ubuntu@<BE_PUBLIC_IP>
```

#### 通过 Web UI 访问

```
http://<FE_PUBLIC_IP>:8030
```

## 扩展 BE 节点

### 对于 1FE+2BE 可扩展集群

使用提供的 `add-be.sh` 脚本动态添加 BE 节点：

```bash
# 添加第3个 BE 节点
./add-be.sh 3 10.0.0.23 terraform.tfvars.1fe2be

# 添加第4个 BE 节点
./add-be.sh 4 10.0.0.24 terraform.tfvars.1fe2be
```

脚本会自动：
1. 在 `terraform.tfvars.1fe2be` 中更新 `be_count`
2. 提示如何在 `main.tf` 中添加新的 BE 实例
3. 提示如何将新 BE 添加到 Doris 集群

**步骤**：
1. 运行 `./add-be.sh <be_number> <be_ip> [terraform_vars_file]`
2. 根据提示编辑 `main.tf` 和 `terraform.tfvars.1fe2be`
3. 运行 `terraform apply -var-file=terraform.tfvars.1fe2be`
4. SSH 到 FE 节点，执行提示中的 SQL 命令

### 对于 2FE+2BE 和 3FE+3BE 集群

手动扩展需要：
1. 编辑对应的 `.tfvars` 文件，增加 `be_count`
2. 在 `main.tf` 中添加新的 BE 实例定义
3. 运行 `terraform apply`
4. 在 Doris 中添加新 BE

```bash
# SSH 到 FE 节点
ssh -i ~/.ssh/id_rsa ubuntu@<FE_PUBLIC_IP>

# 添加新 BE 到 Doris
docker exec doris_fe1 mysql -h 127.0.0.1 -P 9030 -u root -e "ALTER SYSTEM ADD BACKEND '<NEW_BE_IP>:9050';"
```

## 管理操作

### 查看集群状态

```bash
# SSH 到 FE 节点
ssh -i ~/.ssh/id_rsa ubuntu@<FE_PUBLIC_IP>

# 查看 FE 状态
docker exec doris_fe1 mysql -h 127.0.0.1 -P 9030 -u root -e "SHOW FRONTENDS;"

# 查看 BE 状态
docker exec doris_fe1 mysql -h 127.0.0.1 -P 9030 -u root -e "SHOW BACKENDS;"
```

### 查看日志

```bash
# SSH 到节点
ssh -i ~/.ssh/id_rsa ubuntu@<INSTANCE_PUBLIC_IP>

# FE 日志
docker logs doris_fe1

# BE 日志
docker logs doris_be1

# 进入容器查看详细日志
docker exec -it doris_fe1 tail -f /opt/doris/fe/log/fe.log
```

### 重启集群

```bash
# 重启所有容器（SSH 到节点）
docker restart $(docker ps -q -f name=doris_fe)
docker restart $(docker ps -q -f name=doris_be)
```

### 销毁集群

```bash
# 销毁所有资源
terraform destroy -var-file=terraform.tfvars.1fe2be

# 或者
terraform destroy -var-file=terraform.tfvars.2fe2be

# 或者
terraform destroy -var-file=terraform.tfvars.3fe3be
```

## 成本优化

### 使用抢占式实例

在 `.tfvars` 文件中设置：
```bash
fe_preemptible = true
be_preemptible = true
```

抢占式实例可以节省高达 80% 的成本，但可能会被 GCP 回收。

### 调整机器类型

根据实际负载选择合适的机器类型：

| 机器类型 | vCPU | 内存 | 适用场景 |
|---------|------|------|---------|
| e2-medium | 2 | 4GB | 轻量级测试 |
| e2-standard-2 | 2 | 8GB | 标准测试 |
| e2-standard-4 | 4 | 16GB | 生产环境 |
| e2-highmem-2 | 2 | 16GB | 内存密集型 |
| e2-highcpu-2 | 2 | 2GB | CPU 密集型 |

### 调整磁盘大小

```bash
# FE 磁盘
fe_disk_size = 50  # GB

# BE 磁盘
be_disk_size = 100  # GB
```

## 网络配置

### 防火墙规则

Terraform 会自动创建以下防火墙规则：

1. **内部通信**: 允许所有内部 IP 之间的通信
2. **外部访问**: 允许访问 Doris 端口（9030, 8030, 9010 等）
3. **SSH 访问**: 允许 SSH 端口（22）

### 自定义访问范围

修改 `.tfvars` 文件中的 `allowed_source_ranges`：

```bash
# 允许所有 IP
allowed_source_ranges = ["0.0.0.0/0"]

# 仅允许特定 IP
allowed_source_ranges = ["203.0.113.0/24", "198.51.100.0/24"]

# 仅允许特定 IP
allowed_source_ranges = ["203.0.113.42/32"]
```

## 故障排查

### 1. 实例无法启动

检查 Terraform 日志：
```bash
terraform plan -var-file=terraform.tfvars.1fe2be
```

检查 GCP 控制台中的实例状态。

### 2. 无法连接到集群

检查防火墙规则：
```bash
gcloud compute firewall-rules list --filter="name:${cluster_name}*"
```

检查实例状态：
```bash
gcloud compute instances list --filter="name:${cluster_name}*"
```

### 3. BE 无法加入集群

检查 FE 配置：
```bash
# SSH 到 FE
ssh -i ~/.ssh/id_rsa ubuntu@<FE_PUBLIC_IP>

# 查看 FE 日志
docker logs doris_fe1

# 检查网络连通性
docker exec doris_be1 ping <FE_INTERNAL_IP>
```

### 4. 性能问题

- 检查实例资源使用情况
- 调整机器类型
- 增加磁盘大小
- 检查网络带宽

## 监控与告警

### 集成 GCP 监控

```bash
# 安装 Cloud Monitoring Agent
# https://cloud.google.com/monitoring/agent/installation
```

### 配置自定义指标

在 Doris 中配置 Prometheus 导出器：
```bash
# SSH 到 FE
ssh -i ~/.ssh/id_rsa ubuntu@<FE_PUBLIC_IP>

# 配置 Prometheus
docker exec doris_fe1 mysql -h 127.0.0.1 -P 9030 -u root -e "ADMIN SET FRONTEND CONFIG ('prometheus_port', '9180');"
```

## 安全建议

1. **修改默认密码**
   ```sql
   SET PASSWORD FOR 'root' = PASSWORD('your-strong-password');
   ```

2. **限制访问范围**
   - 使用 `allowed_source_ranges` 限制访问 IP
   - 使用 VPN 或堡垒机

3. **启用 SSL/TLS**
   - 配置证书
   - 启用 HTTPS

4. **定期更新**
   - 更新 Doris 版本
   - 更新操作系统补丁

## 备份与恢复

### 备份元数据

```bash
# SSH 到 FE
ssh -i ~/.ssh/id_rsa ubuntu@<FE_PUBLIC_IP>

# 备份元数据
docker exec doris_fe1 tar -czf /tmp/doris-meta-backup.tar.gz /opt/doris/fe/doris-meta

# 复制到本地
scp -i ~/.ssh/id_rsa ubuntu@<FE_PUBLIC_IP>:/tmp/doris-meta-backup.tar.gz ./
```

### 恢复元数据

```bash
# SSH 到 FE
ssh -i ~/.ssh/id_rsa ubuntu@<FE_PUBLIC_IP>

# 停止 FE
docker stop doris_fe1

# 恢复元数据
docker cp doris-meta-backup.tar.gz doris_fe1:/tmp/
docker exec doris_fe1 tar -xzf /tmp/doris-meta-backup.tar.gz -C /opt/doris/fe/

# 启动 FE
docker start doris_fe1
```

## 技术支持

- Doris 官方文档: https://doris.apache.org/docs/
- Terraform 文档: https://developer.hashicorp.com/terraform
- GCP 文档: https://cloud.google.com/docs
- Doris GitHub: https://github.com/apache/doris

## 许可证

Apache License 2.0
