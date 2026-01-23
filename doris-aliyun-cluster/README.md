# Doris 阿里云集群 Terraform 部署指南

## 概述

本部署方案使用 Terraform 在阿里云上部署 Doris 集群，提供多种配置方案：

| 配置方案 | FE 节点 | BE 节点 | 资源配置 | 适用场景 |
|---------|---------|---------|---------|---------|
| 1FE+2BE | 1 | 2 | ecs.g6.large, ecs.g6.2xlarge | 本地测试，灵活扩展 |
| 2FE+2BE | 2 | 2 | ecs.g6.large, ecs.g6.2xlarge | 测试环境，资源适中 |
| 3FE+3BE | 3 | 3 | ecs.g6.2xlarge, ecs.g6.4xlarge | 生产环境，高可用 |

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

### 2. 配置阿里云认证

```bash
# 安装阿里云 CLI
wget https://aliyuncli.alicdn.com/aliyun-cli-linux-latest-amd64.tgz
tar -xzf aliyun-cli-linux-latest-amd64.tgz
sudo mv aliyun /usr/local/bin/

# 配置 AccessKey
aliyun configure
```

或者使用环境变量：

```bash
export ALICLOUD_ACCESS_KEY="your-access-key-id"
export ALICLOUD_SECRET_KEY="your-access-key-secret"
export ALICLOUD_REGION="cn-hangzhou"
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
- **资源**: ecs.g6.large (2 vCPU, 8GB), ecs.g6.2xlarge (4 vCPU, 16GB)
- **磁盘**: 50GB (FE), 100GB (BE)
- **抢占式实例**: 是（成本优化）
- **启动**: `terraform apply -var-file=terraform.tfvars.1fe2be`

#### 方案 2: 2FE+2BE (测试环境)
- **配置**: 2 个 FE + 2 个 BE
- **资源**: ecs.g6.large (2 vCPU, 8GB), ecs.g6.2xlarge (4 vCPU, 16GB)
- **磁盘**: 50GB (FE), 100GB (BE)
- **抢占式实例**: 是（成本优化）
- **启动**: `terraform apply -var-file=terraform.tfvars.2fe2be`

#### 方案 3: 3FE+3BE (生产环境)
- **配置**: 3 个 FE + 3 个 BE
- **资源**: ecs.g6.2xlarge (4 vCPU, 16GB), ecs.g6.4xlarge (8 vCPU, 32GB)
- **磁盘**: 100GB (FE), 200GB (BE)
- **抢占式实例**: 否（高可用）
- **启动**: `terraform apply -var-file=terraform.tfvars.3fe3be`

### 2. 配置变量

编辑对应的 `.tfvars` 文件，修改以下参数：

```bash
# 阿里云 AccessKey（必须）
access_key = "your-access-key-id"
secret_key = "your-access-key-secret"

# 可选配置
region = "cn-hangzhou"
zone = "cn-hangzhou-i"
cluster_name = "doris"
environment = "dev"
```

### 3. 初始化 Terraform

```bash
cd doris-aliyun-cluster
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
  "be_port": "9050",
  "be_private_ips": ["172.16.0.21", "172.16.0.22"],
  "be_public_ips": ["47.97.123.45", "47.97.123.46"],
  "fe_count": 1,
  "fe_port": "9030",
  "fe_private_ips": ["172.16.0.11"],
  "fe_public_ips": ["47.97.123.44"],
  "key_pair_name": "doris-dev-key",
  "region": "cn-hangzhou",
  "zone": "cn-hangzhou-i"
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
ssh -i ~/.ssh/id_rsa root@<FE_PUBLIC_IP>

# 连接到 BE
ssh -i ~/.ssh/id_rsa root@<BE_PUBLIC_IP>
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
./add-be.sh 3 172.16.0.23 terraform.tfvars.1fe2be

# 添加第4个 BE 节点
./add-be.sh 4 172.16.0.24 terraform.tfvars.1fe2be
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
ssh -i ~/.ssh/id_rsa root@<FE_PUBLIC_IP>

# 添加新 BE 到 Doris
docker exec doris_fe1 mysql -h 127.0.0.1 -P 9030 -u root -e "ALTER SYSTEM ADD BACKEND '<NEW_BE_IP>:9050';"
```

## 管理操作

### 查看集群状态

```bash
# SSH 到 FE 节点
ssh -i ~/.ssh/id_rsa root@<FE_PUBLIC_IP>

# 查看 FE 状态
docker exec doris_fe1 mysql -h 127.0.0.1 -P 9030 -u root -e "SHOW FRONTENDS;"

# 查看 BE 状态
docker exec doris_fe1 mysql -h 127.0.0.1 -P 9030 -u root -e "SHOW BACKENDS;"
```

### 查看日志

```bash
# SSH 到节点
ssh -i ~/.ssh/id_rsa root@<INSTANCE_PUBLIC_IP>

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
fe_spot_strategy = "SpotWithPriceLimit"
be_spot_strategy = "SpotWithPriceLimit"
```

抢占式实例可以节省高达 80% 的成本，但可能会被阿里云回收。

### 调整实例类型

根据实际负载选择合适的实例类型：

| 实例类型 | vCPU | 内存 | 适用场景 |
|---------|------|------|---------|
| ecs.g6.large | 2 | 8GB | 轻量级测试 |
| ecs.g6.2xlarge | 4 | 16GB | 标准测试 |
| ecs.g6.4xlarge | 8 | 32GB | 生产环境 |
| ecs.g6.3xlarge | 8 | 48GB | 内存密集型 |
| ecs.c6.2xlarge | 8 | 16GB | CPU 密集型 |

### 调整磁盘大小

```bash
# FE 磁盘
fe_disk_size = 50  # GB

# BE 磁盘
be_disk_size = 100  # GB
```

### 调整带宽

```bash
# 互联网带宽（Mbps）
internet_bandwidth = 5
```

## 网络配置

### 安全组规则

Terraform 会自动创建以下安全组规则：

1. **内部通信**: 允许所有内部 IP 之间的通信
2. **外部访问**: 允许访问 Doris 端口（9030, 8030, 9010 等）
3. **SSH 访问**: 允许 SSH 端口（22）

### 自定义访问范围

修改 `.tfvars` 文件中的安全组规则，在 `main.tf` 中调整 `cidr_ip`：

```bash
# 允许所有 IP
cidr_ip = "0.0.0.0/0"

# 仅允许特定 IP
cidr_ip = "203.0.113.0/24"

# 仅允许特定 IP
cidr_ip = "203.0.113.42/32"
```

## 故障排查

### 1. 实例无法启动

检查 Terraform 日志：
```bash
terraform plan -var-file=terraform.tfvars.1fe2be
```

检查阿里云控制台中的实例状态。

### 2. 无法连接到集群

检查安全组规则：
```bash
# 使用阿里云 CLI
aliyun ecs DescribeSecurityGroups
```

检查实例状态：
```bash
aliyun ecs DescribeInstances
```

### 3. BE 无法加入集群

检查 FE 配置：
```bash
# SSH 到 FE
ssh -i ~/.ssh/id_rsa root@<FE_PUBLIC_IP>

# 查看 FE 日志
docker logs doris_fe1

# 检查网络连通性
docker exec doris_be1 ping <FE_INTERNAL_IP>
```

### 4. 性能问题

- 检查实例资源使用情况
- 调整实例类型
- 增加磁盘大小
- 检查网络带宽

## 监控与告警

### 集成阿里云监控

```bash
# 安装 Cloud Monitor Agent
# https://help.aliyun.com/document_detail/120484.htm
```

### 配置自定义指标

在 Doris 中配置 Prometheus 导出器：
```bash
# SSH 到 FE
ssh -i ~/.ssh/id_rsa root@<FE_PUBLIC_IP>

# 配置 Prometheus
docker exec doris_fe1 mysql -h 127.0.0.1 -P 9030 -u root -e "ADMIN SET FRONTEND CONFIG ('prometheus_port', '9180');"
```

## 安全建议

1. **修改默认密码**
   ```sql
   SET PASSWORD FOR 'root' = PASSWORD('your-strong-password');
   ```

2. **限制访问范围**
   - 使用安全组规则限制访问 IP
   - 使用 VPN 或堡垒机

3. **启用 SSL/TLS**
   - 配置证书
   - 启用 HTTPS

4. **定期更新**
   - 更新 Doris 版本
   - 更新操作系统补丁

5. **使用密钥对认证**
   - 不要使用密码登录
   - 定期轮换 SSH 密钥

## 备份与恢复

### 备份元数据

```bash
# SSH 到 FE
ssh -i ~/.ssh/id_rsa root@<FE_PUBLIC_IP>

# 备份元数据
docker exec doris_fe1 tar -czf /tmp/doris-meta-backup.tar.gz /opt/doris/fe/doris-meta

# 复制到本地
scp -i ~/.ssh/id_rsa root@<FE_PUBLIC_IP>:/tmp/doris-meta-backup.tar.gz ./
```

### 恢复元数据

```bash
# SSH 到 FE
ssh -i ~/.ssh/id_rsa root@<FE_PUBLIC_IP>

# 停止 FE
docker stop doris_fe1

# 恢复元数据
docker cp doris-meta-backup.tar.gz doris_fe1:/tmp/
docker exec doris_fe1 tar -xzf /tmp/doris-meta-backup.tar.gz -C /opt/doris/fe/

# 启动 FE
docker start doris_fe1
```

## 阿里云与 GCP 对比

| 特性 | 阿里云 | GCP |
|------|---------|------|
| 区域选择 | 国内多区域 | 全球多区域 |
| 实例类型 | 丰富 | 丰富 |
| 磁盘类型 | ESSD, SSD | pd-ssd, pd-balanced |
| 网络性能 | 优秀 | 优秀 |
| 价格 | 相对较低 | 相对较高 |
| 抢占式实例 | 支持 | 支持 |
| 文档 | 中文支持 | 英文为主 |

## 技术支持

- Doris 官方文档: https://doris.apache.org/docs/
- Terraform 文档: https://developer.hashicorp.com/terraform
- 阿里云文档: https://help.aliyun.com/
- 阿里云 ECS 文档: https://help.aliyun.com/product/29511.htm
- Doris GitHub: https://github.com/apache/doris

## 许可证

Apache License 2.0
