# Doris 安全镜像 - 本地验证脚本 (简化版)
# 请复制到 PowerShell 中执行

$ErrorActionPreference = "Continue"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Doris 安全镜像本地验证" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 检查 Docker
Write-Host "[检查] Docker..." -ForegroundColor Yellow
$dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
if (-not $dockerCmd) {
    Write-Host "[错误] Docker 未安装或不在 PATH 中" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Docker 已找到" -ForegroundColor Green

# 1. 启动 Nexus
Write-Host ""
Write-Host "[步骤1] 启动 Nexus..." -ForegroundColor Yellow
$nexusRunning = docker ps --filter "name=doris-nexus" --format "{{.Names}}"
if ($nexusRunning -eq "doris-nexus") {
    Write-Host "[OK] Nexus 已在运行" -ForegroundColor Green
} else {
    Write-Host "    运行: docker run -d --name doris-nexus -p 8081:8081 -p 8082:8082 sonatype/nexus3:latest"
    docker run -d --name doris-nexus -p 8081:8081 -p 8082:8082 sonatype/nexus3:latest
    Write-Host "    等待 Nexus 启动 (约 2 分钟)..." -ForegroundColor Cyan
    Start-Sleep -Seconds 120
}

# 2. 下载离线包
Write-Host ""
Write-Host "[步骤2] 下载离线包..." -ForegroundColor Yellow
$offlineDir = "d:\workspace\github\doris-docs\doris-gke-cluster-build-from-ubuntu-latest\offline-packages"
if (-not (Test-Path "$offlineDir\doris-fe")) { New-Item -ItemType Directory -Path "$offlineDir\doris-fe" -Force | Out-Null }
if (-not (Test-Path "$offlineDir\doris-be")) { New-Item -ItemType Directory -Path "$offlineDir\doris-be" -Force | Out-Null }
if (-not (Test-Path "$offlineDir\foundationdb")) { New-Item -ItemType Directory -Path "$offlineDir\foundationdb" -Force | Out-Null }

$DORIS_VERSION = "3.1.4"
$FDB_VERSION = "7.1.37"

Write-Host "    下载 Doris FE..."
if (-not (Test-Path "$offlineDir\doris-fe\apache-doris-fe-${DORIS_VERSION}-bin.tar.gz")) {
    Invoke-WebRequest -Uri "https://archive.apache.org/dist/doris/${DORIS_VERSION}/apache-doris-fe-${DORIS_VERSION}-bin.tar.gz" -OutFile "$offlineDir\doris-fe\apache-doris-fe-${DORIS_VERSION}-bin.tar.gz"
}
Write-Host "    下载 Doris BE..."
if (-not (Test-Path "$offlineDir\doris-be\apache-doris-be-${DORIS_VERSION}-bin-x86_64.tar.gz")) {
    Invoke-WebRequest -Uri "https://archive.apache.org/dist/doris/${DORIS_VERSION}/apache-doris-be-${DORIS_VERSION}-bin-x86_64.tar.gz" -OutFile "$offlineDir\doris-be\apache-doris-be-${DORIS_VERSION}-bin-x86_64.tar.gz"
}
Write-Host "    下载 FoundationDB..."
if (-not (Test-Path "$offlineDir\foundationdb\foundationdb-clients_${FDB_VERSION}-1_amd64.deb")) {
    Invoke-WebRequest -Uri "https://github.com/apple/foundationdb/releases/download/${FDB_VERSION}/foundationdb-clients_${FDB_VERSION}-1_amd64.deb" -OutFile "$offlineDir\foundationdb\foundationdb-clients_${FDB_VERSION}-1_amd64.deb"
    Invoke-WebRequest -Uri "https://github.com/apple/foundationdb/releases/download/${FDB_VERSION}/foundationdb-server_${FDB_VERSION}-1_amd64.deb" -OutFile "$offlineDir\foundationdb\foundationdb-server_${FDB_VERSION}-1_amd64.deb"
}
Write-Host "[OK] 离线包下载完成" -ForegroundColor Green

# 3. 构建镜像
Write-Host ""
Write-Host "[步骤3] 构建镜像..." -ForegroundColor Yellow
$projectDir = "d:\workspace\github\doris-docs\doris-gke-cluster-build-from-ubuntu-latest"

Write-Host "    构建 FE..."
Set-Location "$projectDir\docker\fe"
docker build --build-arg DORIS_VERSION=$DORIS_VERSION --build-arg OFFLINE_PATH=C:/workspace/github/doris-docs/doris-gke-cluster-build-from-ubuntu-latest/offline-packages -t "doris-fe:$DORIS_VERSION" .

Write-Host "    构建 BE..."
Set-Location "$projectDir\docker\be"
docker build --build-arg DORIS_VERSION=$DORIS_VERSION --build-arg OFFLINE_PATH=C:/workspace/github/doris-docs/doris-gke-cluster-build-from-ubuntu-latest/offline-packages -t "doris-be:$DORIS_VERSION" .

Set-Location $projectDir
Write-Host "[OK] 镜像构建完成" -ForegroundColor Green
docker images | Select-String "doris-"

# 4. 推送到 Nexus
Write-Host ""
Write-Host "[步骤4] 推送到 Nexus..." -ForegroundColor Yellow
docker login localhost:8082 -u admin -p admin123
docker tag "doris-fe:$DORIS_VERSION" "localhost:8082/doris/fe:$DORIS_VERSION-secure"
docker tag "doris-be:$DORIS_VERSION" "localhost:8082/doris/be:$DORIS_VERSION-secure"
docker push "localhost:8082/doris/fe:$DORIS_VERSION-secure"
docker push "localhost:8082/doris/be:$DORIS_VERSION-secure"
Write-Host "[OK] 推送完成" -ForegroundColor Green

# 5. 验证
Write-Host ""
Write-Host "[步骤5] 验证..." -ForegroundColor Yellow
docker pull "localhost:8082/doris/fe:$DORIS_VERSION-secure"
docker pull "localhost:8082/doris/be:$DORIS_VERSION-secure"
docker images | Select-String "localhost:8082/doris-"

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " 验证完成!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
