# GCP Doris 集群快速开始指南

## 第一步：准备 GCP 项目

为每个环境创建独立的 GCP 项目：

1. 登录 [GCP Console](https://console.cloud.google.com/)
2. 创建 4 个项目：
   - `doris-dev-project`
   - `doris-sit-project`
   - `doris-uat-project`
   - `doris-prod-project`

3. 为每个项目启用 API：
   - Compute Engine API
   - Cloud Storage API
   - Resource Manager API

## 第二步：安装工具

```bash
# 1. 安装 Terraform
# Windows: 使用 Chocolatey
choco install terraform

# 验证
terraform version

# 2. 安装 gcloud CLI
# 下载: https://cloud.google.com/sdk/docs/install

# 3. 生成 SSH 密钥
ssh-keygen -t rsa -b 4096 -C "your-email@example.com"
```

## 第三步：配置认证

```bash
# 认证到 GCP
gcloud auth login

# 设置默认项目 (可选)
gcloud config set project doris-dev-project
```

## 第四步：部署到 DEV 环境

### Windows 用户

```cmd
REM 进入目录
cd d:\workspace\github\doris-docs\doris-gcp-cluster

REM 部署
deploy.bat dev
```

### Linux/macOS 用户

```bash
# 赋予执行权限
chmod +x *.sh

# 部署
./deploy.sh dev
```

## 第五步：查看部署结果

```cmd
# Windows
status.bat

# Linux/macOS
./status.sh
```

预期输出包括：
- FE 实例 IP 地址
- BE 实例 IP 地址
- Load Balancer 内部 IP
- GCS Bucket 名称
- 持久化磁盘名称

## 第六步：连接到集群

```bash
# 获取 Load Balancer IP (如果启用)
terraform output -json lb_internal_ip

# 连接
mysql -h <LB_IP> -P 9030 -u root
```

```sql
-- 查看集群状态
SHOW FRONTENDS;
SHOW BACKENDS;
SHOW PROC '/cluster_info';

-- 创建测试数据库
CREATE DATABASE test_db;
USE test_db;

-- 创建测试表
CREATE TABLE test_table (
    id INT,
    name VARCHAR(100),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
) DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 10;

-- 插入测试数据
INSERT INTO test_table VALUES (1, 'Test', NOW());
INSERT INTO test_table VALUES (2, 'Doris', NOW());

-- 查询数据
SELECT * FROM test_table;
```

## 测试自动扩缩容

如果启用了自动扩缩容，可以测试扩容：

```bash
# Linux/macOS
./scale.sh dev up 2

# Windows
terraform apply -var-file=terraform.tfvars.dev -var="be_count=4" -auto-approve
```

## 销毁集群

```cmd
# Windows - 销毁但保留数据
destroy.bat dev

# Linux/macOS - 销毁但保留数据
./destroy.sh dev

# 完全删除 (包括数据)
clean-all.bat dev  # Windows
./clean-all.sh dev # Linux/macOS
```

## 常见问题

### Q1: 部署失败怎么办？

```bash
# 查看详细错误
terraform plan -var-file=terraform.tfvars.dev

# 检查 GCP 配额
gcloud compute project-info describe --format="yaml(quotas)"
```

### Q2: 如何连接到实例？

```bash
# 连接到 FE
ssh -i ~/.ssh/id_rsa ubuntu@<FE_IP>

# 连接到 BE
ssh -i ~/.ssh/id_rsa ubuntu@<BE_IP>
```

### Q3: 如何查看日志？

```bash
# FE 日志
tail -f /opt/doris/fe/log/fe.log

# BE 日志
tail -f /opt/doris/be/log/be.INFO
```

### Q4: 集群销毁后数据还在吗？

是的！集群销毁时：
- ✅ 保留 FE 元数据磁盘
- ✅ 保留 BE 存储磁盘
- ✅ 保留 GCS Bucket
- ❌ 删除计算实例
- ❌ 删除 Load Balancer

### Q5: 如何恢复集群？

重新运行部署命令即可：

```bash
deploy.bat dev
```

数据会自动挂载到新实例上。

## 下一步

1. 部署到其他环境
2. 配置数据同步
3. 设置监控告警
4. 配置备份策略
5. 优化性能参数

详细文档请参考 [README.md](README.md)
