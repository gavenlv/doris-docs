# Doris 下载指南

## 问题背景

Apache Doris 3.x 版本的发布格式发生了变化：

### Doris 2.x 及之前版本
- FE 和 BE 分开下载
- `apache-doris-fe-{VERSION}-bin.tar.gz`
- `apache-doris-be-{VERSION}-bin-x86_64.tar.gz`

### Doris 3.x 版本（当前）
- **统一二进制包**：`apache-doris-{VERSION}-bin-x64.tar.gz`
- 包含 `fe/` 和 `be/` 两个子目录
- 官方二进制包托管在阿里云 OSS

### 版本可用性

| 版本 | Apache 归档 | 阿里云 OSS | 说明 |
|------|------------|-----------|------|
| 3.1.4 | 只有源码包 | ❓ | 可能没有发布二进制包 |
| 3.0.5 | ❌ | ✅ | **推荐使用** |
| 2.1.7 | ✅ | ✅ | 稳定版 |

## 下载命令

### Windows (PowerShell)

```powershell
# 创建目录
mkdir offline-packages

# 下载 Doris 3.0.5 统一二进制包 (推荐)
Invoke-WebRequest -Uri "https://apache-doris-releases.oss-accelerate.aliyuncs.com/apache-doris-3.0.5-bin-x64.tar.gz" -OutFile "offline-packages\apache-doris-3.0.5-bin-x64.tar.gz"

# 或者使用 curl
curl -L -o offline-packages\apache-doris-3.0.5-bin-x64.tar.gz "https://apache-doris-releases.oss-accelerate.aliyuncs.com/apache-doris-3.0.5-bin-x64.tar.gz"
```

### Linux/macOS

```bash
# 创建目录
mkdir -p offline-packages

# 下载 Doris 3.0.5 统一二进制包 (推荐)
wget -P offline-packages/ https://apache-doris-releases.oss-accelerate.aliyuncs.com/apache-doris-3.0.5-bin-x64.tar.gz

# 或者使用 curl
curl -L -o offline-packages/apache-doris-3.0.5-bin-x64.tar.gz https://apache-doris-releases.oss-accelerate.aliyuncs.com/apache-doris-3.0.5-bin-x64.tar.gz
```

## 验证下载

```bash
# 查看文件大小 (约 400MB+)
ls -lh offline-packages/apache-doris-3.0.5-bin-x64.tar.gz

# 验证内容
tar -tzf offline-packages/apache-doris-3.0.5-bin-x64.tar.gz | head -20

# 预期输出包含:
# apache-doris-3.0.5-bin-x64/fe/
# apache-doris-3.0.5-bin-x64/be/
```

## 镜像构建

下载完成后，Dockerfile 会自动从统一包中提取 FE 或 BE：

```dockerfile
# FE Dockerfile - 提取 fe/ 目录
COPY --from=downloader /doris-package/fe /opt/doris/fe

# BE Dockerfile - 提取 be/ 目录
COPY --from=downloader /doris-package/be /opt/doris/be
```

## 常见问题

### Q: 为什么 3.1.4 下载失败？

A: Doris 3.1.4 在 Apache 归档中只有源码包，没有发布二进制包。请使用 3.0.5 版本。

### Q: 阿里云 OSS 链接安全吗？

A: 这是 Apache Doris 官方发布的镜像地址，由阿里云提供加速下载。

### Q: 可以下载其他版本吗？

A: 可以，替换 URL 中的版本号即可。但请确保该版本有二进制包发布。

```bash
# 尝试其他版本
wget https://apache-doris-releases.oss-accelerate.aliyuncs.com/apache-doris-2.1.7-bin-x64.tar.gz
```

## 下一步

下载完成后，运行验证脚本：

```powershell
# Windows
.\verify.bat

# Linux/macOS
./scripts/local-verify.sh all
```
