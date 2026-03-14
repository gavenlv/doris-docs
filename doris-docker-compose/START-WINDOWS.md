# Windows 快速启动指南

## 🚀 5 分钟快速启动

### 前置检查

✅ 确认 Docker Desktop 已安装并运行
✅ 确认有至少 24GB 可用内存
✅ 确认有至少 50GB 磁盘空间

### 启动步骤

#### 1. 启动集群 (2 分钟)

**双击运行**:
```
start.bat
```

**或在 PowerShell 中**:
```powershell
.\start.bat
```

等待看到以下信息：
```
Doris Local Cluster Started!
```

#### 2. 初始化集群 (1 分钟)

**等待 1-2 分钟后，运行**:
```powershell
.\init-cluster.bat
```

看到以下信息表示成功：
```
Cluster Initialization Complete!
```

#### 3. 验证集群

**运行测试**:
```powershell
.\test-cluster.bat
```

看到以下信息表示成功：
```
Test Completed Successfully!
```

### 连接集群

#### 方法 1: Web UI (最简单)

打开浏览器访问:
```
http://localhost:8030
```

#### 方法 2: MySQL 客户端

```powershell
# 如果已安装 MySQL 客户端
mysql -h 127.0.0.1 -P 9030 -u root

# 或使用 Docker
docker run --rm -it mysql:8.0 mysql -h host.docker.internal -P 9030 -u root
```

### 常用命令

| 操作 | 命令 |
|------|------|
| 启动集群 | `.\start.bat` |
| 停止集群 | `.\stop.bat` |
| 查看状态 | `.\health-check.bat` |
| 查看日志 | `.\view-logs.bat` |
| 测试集群 | `.\test-cluster.bat` |
| 重置集群 | `.\reset-cluster.bat` |

### 故障排查

#### 问题 1: 端口被占用

**症状**:
```
Error: port is already allocated
```

**解决**:
```powershell
# 查看端口占用
netstat -ano | findstr :8030

# 结束占用进程（替换 PID）
taskkill /PID <PID> /F
```

#### 问题 2: 内存不足

**症状**:
```
容器启动失败或被关闭
```

**解决**:
1. 打开 Docker Desktop
2. Settings > Resources
3. 增加 Memory 到 24GB+
4. 点击 Apply & Restart

#### 问题 3: 镜像拉取慢

**症状**:
```
镜像下载超时
```

**解决**:
- 等待更长时间（首次启动需要 5-10 分钟）
- 检查网络连接
- 考虑使用国内镜像源

#### 问题 4: 容器无法启动

**解决**:
```powershell
# 完全重置
.\reset-cluster.bat

# 或手动清理
docker-compose down -v
docker system prune -a
.\start.bat
```

### 健康检查

运行健康检查脚本：
```powershell
.\health-check.bat
```

应该看到所有组件状态为 `Ready`。

### 下一步

1. **阅读完整文档**: `README.md`
2. **Windows 详细指南**: `README-WINDOWS.md`
3. **SQL 示例**: `examples\quick-start.sql`
4. **故障排查**: `docs\TROUBLESHOOTING.md`

### 监控启用（可选）

编辑 `.env` 文件：
```powershell
notepad .env
```

修改：
```
ENABLE_MONITORING=true
```

重新启动：
```powershell
.\stop.bat
.\start.bat
```

访问监控：
- Prometheus: http://localhost:9090
- Grafana: http://localhost:3000 (admin/admin)

### 停止集群

```powershell
.\stop.bat
```

**注意**: 数据会保留，下次启动时数据仍然存在。

### 完全清理

```powershell
.\cleanup.bat
```

**警告**: 这会删除所有数据！

### 需要帮助？

- 查看日志: `.\view-logs.bat`
- 健康检查: `.\health-check.bat`
- 查看文档: `docs\` 目录
- 完全重置: `.\reset-cluster.bat`

### 资源需求确认

运行以下命令确认资源充足：
```powershell
# 检查内存
systeminfo | findstr /C:"Total Physical Memory"

# 检查磁盘
wmic logicaldisk get size,freespace,caption

# 检查 Docker
docker info
```

### 成功标志

如果看到以下信息，说明集群已成功启动：

✅ `docker-compose ps` 显示所有容器状态为 `Up`
✅ `http://localhost:8030` 可以访问
✅ `mysql -h 127.0.0.1 -P 9030 -u root` 可以连接
✅ `SHOW FRONTENDS;` 显示 3 个 FE 节点
✅ `SHOW BACKENDS;` 显示 3 个 BE 节点

### 时间估算

- 首次启动（含镜像拉取）: 5-10 分钟
- 后续启动: 1-2 分钟
- 初始化: 1 分钟
- 测试: 30 秒

祝您使用愉快！🎉
