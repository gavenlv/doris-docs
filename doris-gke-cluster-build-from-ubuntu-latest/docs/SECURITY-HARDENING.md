# 安全加固指南

## 概述

本文档详细说明 Doris 安全加固镜像的构建流程和安全措施。

## 安全措施概览

### 1. 基础镜像选择

- **使用 Ubuntu 22.04 LTS**: 长期支持版本，安全更新及时
- **定期更新基础镜像**: 每月同步最新安全补丁
- **验证镜像签名**: 确保基础镜像未被篡改

### 2. 最小化原则

- 仅安装必要软件包
- 移除文档和示例文件
- 清理包管理器缓存
- 使用 `--no-install-recommends` 避免安装推荐包

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    package-name \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
```

### 3. 非 Root 用户运行

所有容器均以非 root 用户运行：

```dockerfile
# 创建专用用户
RUN groupadd -r doris && useradd -r -g doris -d /opt/doris -s /sbin/nologin doris

# 切换用户
USER doris
```

### 4. 文件权限加固

```dockerfile
# 设置目录权限
RUN chmod -R 750 /opt/doris

# 设置文件权限
RUN find /opt/doris -type f -exec chmod 640 {} \;

# 设置可执行文件权限
RUN find /opt/doris/bin -type f -exec chmod 750 {} \;
```

### 5. 安全上下文

Kubernetes Pod 安全上下文：

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
  
  containers:
  - securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: false
      capabilities:
        drop:
        - ALL
```

### 6. 健康检查

每个镜像都包含健康检查：

```dockerfile
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8030/api/health || exit 1
```

## 安全扫描

### 扫描工具

使用 Trivy 进行安全扫描：

```bash
# 安装 Trivy
brew install trivy  # macOS
# 或
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
echo "deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee -a /etc/apt/sources.list.d/trivy.list
sudo apt-get update
sudo apt-get install trivy
```

### 扫描流程

```bash
# 1. 构建镜像
./scripts/build-images.sh all

# 2. 扫描镜像
./scripts/scan-images.sh all

# 3. 查看报告
cat reports/security-scan-report.txt

# 4. 修复漏洞（如有）
./scripts/fix-vulnerabilities.sh
```

### 漏洞分级

| 级别 | 说明 | 处理方式 |
|------|------|---------|
| CRITICAL | 严重漏洞 | 必须修复，禁止部署 |
| HIGH | 高危漏洞 | 强烈建议修复 |
| MEDIUM | 中危漏洞 | 建议修复 |
| LOW | 低危漏洞 | 可接受风险 |

## 常见漏洞修复

### 1. OpenSSL 漏洞

```dockerfile
RUN apt-get update && apt-get install -y --only-upgrade openssl libssl3
```

### 2. Glibc 漏洞

```dockerfile
RUN apt-get update && apt-get install -y --only-upgrade libc6
```

### 3. Curl 漏洞

```dockerfile
RUN apt-get update && apt-get install -y --only-upgrade curl libcurl4
```

### 4. Java 漏洞

对于 FE 镜像中的 Java：

```dockerfile
# 使用最新版本的 OpenJDK
RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-17-jre-headless
```

## 镜像签名和验证

### 使用 Cosign 签名

```bash
# 安装 cosign
brew install cosign

# 签名镜像
cosign sign --key cosign.key nexus.company.com:8082/doris/fe:3.1.4-secure

# 验证签名
cosign verify --key cosign.pub nexus.company.com:8082/doris/fe:3.1.4-secure
```

## 网络安全

### 网络策略

建议配置 Kubernetes 网络策略限制 Pod 间通信：

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: doris-network-policy
  namespace: doris
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: doris
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: doris
```

## 定期安全审计

### 建议频率

- **每日**: 自动扫描新漏洞
- **每周**: 检查安全报告
- **每月**: 更新基础镜像，重建镜像
- **每季度**: 全面安全审计

### 审计清单

- [ ] 基础镜像版本是否最新
- [ ] 所有漏洞是否已修复
- [ ] 安全配置是否生效
- [ ] 日志审计是否正常
- [ ] 访问控制是否合理
- [ ] 网络隔离是否有效

## 安全最佳实践

1. **最小权限原则**: 只授予必要的权限
2. **防御深度**: 多层安全措施
3. **持续监控**: 实时监控安全状态
4. **及时响应**: 快速响应安全事件
5. **定期演练**: 安全事件响应演练

## 相关文档

- [构建指南](BUILD-GUIDE.md)
- [漏洞修复记录](VULNERABILITY-FIXES.md)
- [部署指南](DEPLOYMENT-GUIDE.md)
