# Doris GCP 集群 Terraform 原生部署指南

## 概述

本部署方案使用 Terraform 在 Google Cloud Platform (GCP) 上部署 Doris 集群，采用**原生部署方式（无 Docker）**。

### 配置方案

| 配置方案 | FE 节点 | BE 节点 | 资源配置 | 适用场景 |
|---------|---------|---------|---------|---------|
| 1FE+2BE | 1 | 2 | e2-medium, e2-standard-2 | 本地测试，性能优化 |
| 2FE+2BE | 2 | 2 | e2-medium, e2-standard-2 | 测试环境 |
| 3FE+3BE | 3 | 3 | e2-standard-2, e2-standard-4 | 生产环境 |

### 为什么选择原生部署？

| 特性 | Docker 部署 | 原生部署（推荐） |
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
ssh-keygen -t rsa -b 4096 -C "your-email@example.com"
```

## 快速开始

### 1. 选择配置方案

```bash
# 基础配置
terraform apply -var-file=terraform.tfvars.1fe2be

# 测试环境（2FE+2BE）
terraform apply -var-file=terraform.tfvars.2fe2be

# 生产环境（3FE+3BE）
terraform apply -var-file=terraform.tfvars.3fe3be
```

### 2. 配置变量

编辑对应的 `.tfvars` 文件：

```bash
# GCP 项目 ID（必须）
project_id = "your-project-id"

# SSH 公钥路径（必须）
ssh_public_key_path = "~/.ssh/id_rsa.pub"
```

### 3. 初始化并部署

```bash
cd doris-gcp-cluster
terraform init
terraform apply -var-file=terraform.tfvars.1fe2be
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
mysql -h 127.0.0.1 -P 9030 -u root -e "ALTER SYSTEM ADD BACKEND '<BE_INTERNAL_IP>:9050';"

# 2. 检查 BE 状态
mysql -h 127.0.0.1 -P 9030 -u root -e "SHOW BACKENDS;"
```

## 成本优化

### 使用抢占式实例

```bash
fe_preemptible = true
be_preemptible = true
```

抢占式实例可节省高达 80% 成本。

### 调整机器类型

| 机器类型 | vCPU | 内存 | 适用场景 |
|---------|------|------|---------|
| e2-medium | 2 | 4GB | 轻量级测试 |
| e2-standard-2 | 2 | 8GB | 标准测试 |
| e2-standard-4 | 4 | 16GB | 生产环境 |

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
ping <FE_INTERNAL_IP>

# 查看 FE 日志
tail -f /opt/doris/fe/log/fe.log

# 检查 BE 状态
mysql -h 127.0.0.1 -P 9030 -u root -e "SHOW BACKENDS;"
```

## 销毁集群

```bash
terraform destroy -var-file=terraform.tfvars.1fe2be
```

## 技术支持

- Doris 官方文档: https://doris.apache.org/docs/
- Terraform GCP 文档: https://registry.terraform.io/providers/hashicorp/google/latest
- GCP 文档: https://cloud.google.com/docs

## 许可证

Apache License 2.0
