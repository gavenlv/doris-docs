# Doris 阿里云集群 Terraform 原生部署指南

## 概述

本部署方案使用 Terraform 在阿里云上部署 Doris 集群，采用**原生部署方式（无 Docker）**。

### 配置方案

| 配置方案 | FE 节点 | BE 节点 | 资源配置 | 分层存储 | 适用场景 |
|---------|---------|---------|---------|---------|---------|
| 1FE+2BE | 1 | 2 | ecs.g6.large, ecs.g6.2xlarge | 否 | 本地测试，性能优化 |
| 1FE+2BE (分层存储) | 1 | 2 | ecs.g6.large, ecs.g6.2xlarge | 是 | 最佳实践，成本优化 |
| 2FE+2BE | 2 | 2 | ecs.g6.large, ecs.g6.2xlarge | 否 | 测试环境 |
| 3FE+3BE | 3 | 3 | ecs.g6.2xlarge, ecs.g6.4xlarge | 否 | 生产环境 |

### 为什么选择原生部署？

| 特性 | Docker 部署 | 原生部署 |
|------|------------|---------|
| 资源开销 | +200-300MB 内存/节点 | 基准 |
| 性能 | 有容器化损耗 | 无额外损耗 |
| 问题排查 | 需要进入容器 | 直接访问 |
| 云原生适配度 | 中等 | **高** |

## 前置要求

### 1. 安装 Terraform

```bash
# macOS
brew install terraform

# Linux
wget https://releases.hashicorp.com/terraform/1.5.0/terraform_1.5.0_linux_amd64.zip
unzip terraform_1.5.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/
```

### 2. 配置阿里云认证

```bash
export ALICLOUD_ACCESS_KEY="your-access-key-id"
export ALICLOUD_SECRET_KEY="your-access-key-secret"
export ALICLOUD_REGION="cn-hangzhou"
```

### 3. 准备 SSH 密钥

```bash
ssh-keygen -t rsa -b 4096 -C "your-email@example.com"
```

## 快速开始

### 1. 选择配置方案

```bash
# 基础配置
terraform apply -var-file=terraform.tfvars.1fe2be

# 最佳实践（分层存储）
terraform apply -var-file=terraform.tfvars.1fe2be.tiered

# 测试环境（2FE+2BE）
terraform apply -var-file=terraform.tfvars.2fe2be

# 生产环境（3FE+3BE）
terraform apply -var-file=terraform.tfvars.3fe3be
```

### 2. 配置变量

编辑对应的 `.tfvars` 文件：

```bash
access_key = "your-access-key-id"
secret_key = "your-secret-key"
```

### 3. 初始化并部署

```bash
cd doris-aliyun-cluster
terraform init
terraform apply -var-file=terraform.tfvars.1fe2be.native
```

### 4. 获取连接信息

```bash
terraform output
```

## 服务管理

### systemd 服务

```bash
# 查看状态
systemctl status doris-fe
systemctl status doris-be

# 启动/停止/重启
systemctl start doris-fe
systemctl stop doris-fe
systemctl restart doris-fe

# 查看日志
journalctl -u doris-fe -f
journalctl -u doris-be -f
```

### 查看集群状态

```bash
mysql -h 127.0.0.1 -P 9030 -u root -e "SHOW FRONTENDS;"
mysql -h 127.0.0.1 -P 9030 -u root -e "SHOW BACKENDS;"
```

### 配置文件位置

```bash
# FE 配置
/opt/doris/fe/conf/fe.conf

# BE 配置
/opt/doris/be/conf/be.conf
```

### 日志位置

```bash
# FE 日志
/opt/doris/fe/log/fe.log
/opt/doris/fe/log/fe.gc.log.*

# BE 日志
/opt/doris/be/log/be.INFO
/opt/doris/be/log/be.gc.log.*
```

## 添加 BE 节点

```bash
# 1. 在 FE 节点上添加 BE
mysql -h 127.0.0.1 -P 9030 -u root -e "ALTER SYSTEM ADD BACKEND '<BE_PRIVATE_IP>:9050';"

# 2. 检查 BE 状态
mysql -h 127.0.0.1 -P 9030 -u root -e "SHOW BACKENDS;"
```

## 分层存储

### 概述

| 存储层级 | 存储介质 | 性能 | 成本 | 适用场景 |
|---------|---------|------|------|---------|
| Hot | SSD | 高 | 高 | 频繁访问的热数据 |
| Warm | OSS Standard | 中 | 中 | 偶尔访问的温数据 |
| Cold | OSS Archive | 低 | 低 | 很少访问的冷数据 |

### 配置分层存储

在 `.tfvars` 文件中设置：

```bash
enable_tiered_storage = true
hot_storage_size = 100
warm_storage_size = 500
cold_storage_size = 1000
oss_bucket_prefix = "doris"
oss_access_key_id = "your-oss-access-key-id"
oss_access_key_secret = "your-oss-access-key-secret"
```

### 检查 OSS 挂载

```bash
# 检查挂载点
df -h | grep oss

# 检查 rclone 服务
systemctl status doris-oss-mount
```

## 成本优化

### 使用抢占式实例

```bash
fe_spot_strategy = "SpotWithPriceLimit"
be_spot_strategy = "SpotWithPriceLimit"
```

### 分层存储成本对比

| 存储类型 | 价格（约） | 相对成本 |
|---------|-----------|---------|
| SSD | ¥0.35/GB/月 | 100% |
| OSS Standard | ¥0.12/GB/月 | 34% |
| OSS Archive | ¥0.08/GB/月 | 23% |

使用分层存储可节省约 65% 存储成本。

## 故障排查

### FE 无法启动

```bash
systemctl status doris-fe
journalctl -u doris-fe -n 100
tail -100 /opt/doris/fe/log/fe.log
```

### BE 无法启动

```bash
systemctl status doris-be
journalctl -u doris-be -n 100
tail -100 /opt/doris/be/log/be.INFO
```

### BE 无法加入集群

```bash
# 检查网络连通性
ping <FE_PRIVATE_IP>

# 查看 FE 日志
tail -f /opt/doris/fe/log/fe.log

# 检查 BE 状态
mysql -h 127.0.0.1 -P 9030 -u root -e "SHOW BACKENDS;"
```

### 分层存储问题

```bash
df -h | grep oss
systemctl status doris-oss-mount
journalctl -u doris-oss-mount -n 100
```

## 销毁集群

```bash
terraform destroy -var-file=terraform.tfvars.1fe2be
```

## 技术支持

- Doris 官方文档: https://doris.apache.org/docs/
- Terraform 阿里云文档: https://registry.terraform.io/providers/aliyun/alicloud/latest
- 阿里云 ECS 文档: https://help.aliyun.com/product/29511.htm

## 许可证

Apache License 2.0
