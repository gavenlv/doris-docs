# Windows 使用指南

## 🚀 快速开始

### 前置要求

1. **Windows 10/11 (64位)**
2. **Docker Desktop for Windows**
   - 下载地址: https://www.docker.com/products/docker-desktop
   - 版本要求: 4.0+
   - 需要 WSL 2 后端

### 安装 Docker Desktop

#### 步骤 1: 启用 WSL 2

1. 以**管理员身份**打开 PowerShell
2. 运行以下命令：
```powershell
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
```
3. **重启电脑**

#### 步骤 2: 下载并安装 Docker Desktop

1. 访问 https://www.docker.com/products/docker-desktop
2. 下载 Windows 版本
3. 双击安装包安装
4. 安装完成后启动 Docker Desktop
5. 等待 Docker Desktop 启动完成（托盘图标显示绿色）

#### 步骤 3: 验证安装

打开 PowerShell，运行：
```powershell
docker --version
docker-compose --version
```

应该显示版本信息。

### 启动 Doris 集群

#### 方法 1: 使用批处理脚本（推荐）

1. **打开 PowerShell 或命令提示符**
```powershell
# 进入项目目录
cd doris-docker-compose
```

2. **启动集群**
```powershell
# 双击 start.bat 或在命令行执行
.\start.bat
```

3. **等待启动完成**（约 2-3 分钟）
   - 拉取 Docker 镜像（首次启动需要 5-10 分钟）
   - 启动 FoundationDB 集群
   - 启动 Doris FE 集群
   - 启动 Doris BE 集群

4. **初始化集群**（等待 FE 完全启动后）
```powershell
.\init-cluster.bat
```

5. **测试集群**
```powershell
.\test-cluster.bat
```

#### 方法 2: 使用 Docker Compose 命令

```powershell
# 启动所有服务
docker-compose up -d

# 查看状态
docker-compose ps

# 初始化集群（等待 2 分钟后）
# 需要手动执行 SQL 添加 BE 节点
```

### 连接集群

#### 使用 MySQL 客户端

```powershell
# 如果已安装 MySQL 客户端
mysql -h 127.0.0.1 -P 9030 -u root

# 如果没有 MySQL 客户端，可以使用 Docker
docker run --rm -it mysql:8.0 mysql -h host.docker.internal -P 9030 -u root
```

#### 使用 Web UI

打开浏览器访问：
- FE Master: http://localhost:8030

### Windows 批处理脚本说明

| 脚本 | 功能 | 使用场景 |
|------|------|----------|
| `start.bat` | 启动集群 | 首次启动或日常启动 |
| `stop.bat` | 停止集群 | 停止服务 |
| `init-cluster.bat` | 初始化集群 | 首次部署时初始化 BE 节点 |
| `test-cluster.bat` | 测试集群 | 验证集群功能 |
| `health-check.bat` | 健康检查 | 诊断集群状态 |
| `view-logs.bat` | 查看日志 | 查看各组件日志 |
| `cleanup.bat` | 清理环境 | 完全删除集群和数据 |
| `reset-cluster.bat` | 重置集群 | 清空数据并重新部署 |

### 常见 Windows 问题

#### 1. Docker Desktop 无法启动

**解决方案**:
- 确保 WSL 2 已启用
- 检查 Hyper-V 是否启用（Windows 10 Pro/Enterprise）
- 重启电脑
- 重新安装 Docker Desktop

**验证 WSL 2**:
```powershell
wsl --list --verbose
```

#### 2. 端口冲突

**症状**: `Error starting userland proxy: listen tcp 0.0.0.0:8030: bind: address already in use`

**解决方案**:
```powershell
# 查看端口占用
netstat -ano | findstr :8030

# 修改 .env 文件中的端口
FE_HTTP_PORT=18030
FE_QUERY_PORT=19030
```

#### 3. 内存不足

**症状**: 容器启动失败或被强制关闭

**解决方案**:
- 打开 Docker Desktop 设置
- 进入 Resources 设置
- 增加内存限制（建议 24GB+）
- 重启 Docker Desktop

#### 4. 磁盘空间不足

**解决方案**:
```powershell
# 清理 Docker 未使用的资源
docker system prune -a

# 清理 Doris 数据
.\cleanup.bat
```

#### 5. Windows 防火墙阻止

**解决方案**:
- 打开 Windows Defender 防火墙
- 允许 Docker Desktop 通过防火墙
- 或临时关闭防火墙测试

#### 6. MySQL 客户端连接失败

**解决方案**:

**选项 1**: 安装 MySQL 客户端
```powershell
# 使用 Chocolatey 安装
choco install mysql-cli

# 或下载 MySQL Installer
# https://dev.mysql.com/downloads/installer/
```

**选项 2**: 使用 Docker 运行 MySQL 客户端
```powershell
docker run --rm -it mysql:8.0 mysql -h host.docker.internal -P 9030 -u root
```

**选项 3**: 使用 Web UI
- 访问 http://localhost:8030
- 使用内置的 Query 界面

### 性能优化

#### Docker Desktop 设置优化

1. **打开 Docker Desktop 设置**
2. **进入 Settings > Resources**
3. **推荐配置**:
   - CPUs: 8-12
   - Memory: 24-32 GB
   - Swap: 4 GB
   - Disk image location: SSD 驱动器

4. **进入 Settings > Docker Engine**
   添加以下配置以提升性能：
```json
{
  "storage-opts": [
    "size=100GB"
  ],
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

### 监控启用（可选）

#### 1. 修改 `.env` 文件
```powershell
# 使用记事本编辑
notepad .env

# 修改以下行
ENABLE_MONITORING=true
```

#### 2. 启动监控
```powershell
.\start.bat
```

#### 3. 访问监控界面
- Prometheus: http://localhost:9090
- Grafana: http://localhost:3000
  - 用户名: admin
  - 密码: admin

### 数据持久化

Windows 上 Docker 数据存储位置：
```
\\wsl$\docker-desktop-data\data\docker\volumes\
```

#### 备份数据

```powershell
# 创建备份目录
mkdir C:\doris-backup

# 备份 FE 数据
docker run --rm -v doris-local_fe1-data:/data -v C:\doris-backup:/backup alpine tar czf /backup/fe1-backup.tar.gz -C /data .

# 备份 BE 数据
docker run --rm -v doris-local_be1-data:/data -v C:\doris-backup:/backup alpine tar czf /backup/be1-backup.tar.gz -C /data .
```

#### 恢复数据

```powershell
# 恢复 FE 数据
docker run --rm -v doris-local_fe1-data:/data -v C:\doris-backup:/backup alpine tar xzf /backup/fe1-backup.tar.gz -C /data

# 重启集群
docker-compose restart
```

### PowerShell 常用命令

```powershell
# 查看容器状态
docker-compose ps

# 查看容器日志
docker-compose logs -f fe1
docker-compose logs -f be1

# 进入容器
docker exec -it doris-fe1 bash

# 重启单个服务
docker-compose restart fe1

# 查看资源使用
docker stats --no-stream

# 清理未使用的镜像
docker image prune -a

# 查看磁盘使用
docker system df
```

### 故障排查

#### 完整诊断流程

```powershell
# 1. 检查 Docker 状态
docker info

# 2. 检查容器状态
docker-compose ps

# 3. 查看日志
.\view-logs.bat

# 4. 运行健康检查
.\health-check.bat

# 5. 检查网络
docker network inspect doris-local

# 6. 重启集群
.\stop.bat
.\start.bat
```

#### 收集诊断信息

```powershell
# 创建诊断文件
echo "=== Docker Compose PS ===" > diagnostic.txt
docker-compose ps >> diagnostic.txt

echo "=== Docker Stats ===" >> diagnostic.txt
docker stats --no-stream >> diagnostic.txt

echo "=== FE Logs ===" >> diagnostic.txt
docker-compose logs fe1 --tail=100 >> diagnostic.txt

echo "=== BE Logs ===" >> diagnostic.txt
docker-compose logs be1 --tail=100 >> diagnostic.txt
```

### 卸载

#### 完全卸载 Doris 环境

```powershell
# 1. 停止并删除容器
.\cleanup.bat

# 2. 删除镜像
docker rmi apache/doris:fe-3.1.4
docker rmi apache/doris:be-3.1.4
docker rmi foundationdb/foundationdb:7.1.37

# 3. 删除数据卷
docker volume prune

# 4. 删除网络
docker network prune
```

### 与 Linux/macOS 的差异

| 特性 | Windows | Linux/macOS |
|------|---------|-------------|
| 启动脚本 | `.bat` 文件 | `.sh` 脚本 |
| 文件路径 | `C:\path` | `/path` |
| 主机访问 | `host.docker.internal` | `localhost` |
| 数据存储 | WSL 2 文件系统 | 原生文件系统 |
| 性能 | 略低（WSL 2 开销）| 原生性能 |

### 推荐工具

- **Docker Desktop**: Docker 管理界面
- **MySQL Workbench**: MySQL GUI 客户端
- **DBeaver**: 通用数据库客户端
- **Postman**: API 测试工具
- **VS Code**: 代码编辑器 + Docker 插件

### 获取帮助

如果遇到问题：

1. 查看 [故障排查指南](docs/TROUBLESHOOTING.md)
2. 查看 [架构说明](docs/ARCHITECTURE-LOCAL.md)
3. 查看 Docker Desktop 日志
4. 重置集群: `.\reset-cluster.bat`

### 更多资源

- **Apache Doris 官方文档**: https://doris.apache.org
- **Docker Desktop 文档**: https://docs.docker.com/desktop/windows/
- **WSL 2 文档**: https://docs.microsoft.com/en-us/windows/wsl/
