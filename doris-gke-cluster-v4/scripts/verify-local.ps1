# Doris 2.1.7 Security Image - Local Verification Script
# Run in PowerShell

$ErrorActionPreference = "Continue"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Doris 2.1.7 Security Image Verification" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check Docker
Write-Host "[Check] Docker..." -ForegroundColor Yellow
$dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
if (-not $dockerCmd) {
    Write-Host "[Error] Docker not installed or not in PATH" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Docker found" -ForegroundColor Green

# 1. Start Nexus
Write-Host ""
Write-Host "[Step 1] Starting Nexus..." -ForegroundColor Yellow
$nexusRunning = docker ps --filter "name=doris-nexus" --format "{{.Names}}"
if ($nexusRunning -eq "doris-nexus") {
    Write-Host "[OK] Nexus is running" -ForegroundColor Green
} else {
    Write-Host "    Running: docker run -d --name doris-nexus -p 8081:8081 -p 8082:8082 sonatype/nexus3:latest"
    docker run -d --name doris-nexus -p 8081:8081 -p 8082:8082 sonatype/nexus3:latest
    Write-Host "    Waiting for Nexus to start (about 2 minutes)..." -ForegroundColor Cyan
    Start-Sleep -Seconds 120
}

# 2. Download offline packages
Write-Host ""
Write-Host "[Step 2] Downloading offline packages..." -ForegroundColor Yellow

$DORIS_VERSION = "2.1.7"
$FDB_VERSION = "7.1.37"

$projectDir = "d:\workspace\github\doris-docs\doris-gke-cluster-v4"
$offlineDir = "$projectDir\offline-packages"

# Create directories
if (-not (Test-Path "$offlineDir")) { New-Item -ItemType Directory -Path "$offlineDir" -Force | Out-Null }

# Download Doris unified binary package (2.1.7)
$downloadUrl = "https://apache-doris-releases.oss-accelerate.aliyuncs.com/apache-doris-2.1.7-bin-x64.tar.gz"
$downloadFile = "$offlineDir\apache-doris-2.1.7-bin-x64.tar.gz"

if (-not (Test-Path $downloadFile)) {
    Write-Host "    Downloading Doris 2.1.7 unified package..."
    Write-Host "    Source: $downloadUrl" -ForegroundColor Cyan
    Invoke-WebRequest -Uri $downloadUrl -OutFile $downloadFile
    Write-Host "    Downloaded: $downloadFile" -ForegroundColor Green
} else {
    Write-Host "    Package already exists, skipping download" -ForegroundColor Green
}

Write-Host "[OK] Offline package ready" -ForegroundColor Green

# 3. Build images
Write-Host ""
Write-Host "[Step 3] Building images..." -ForegroundColor Yellow

Write-Host "    Building FE..."
Set-Location "$projectDir\docker\fe"
docker build --build-arg DORIS_VERSION=$DORIS_VERSION --build-arg OFFLINE_PATH="$projectDir/offline-packages" -t "doris-fe:$DORIS_VERSION" .

Write-Host "    Building BE..."
Set-Location "$projectDir\docker\be"
docker build --build-arg DORIS_VERSION=$DORIS_VERSION --build-arg OFFLINE_PATH="$projectDir/offline-packages" -t "doris-be:$DORIS_VERSION" .

Set-Location $projectDir
Write-Host "[OK] Images built" -ForegroundColor Green
docker images | Select-String "doris-"

# 4. Push to Nexus
Write-Host ""
Write-Host "[Step 4] Pushing to Nexus..." -ForegroundColor Yellow
docker login localhost:8082 -u admin -p adminadmin
docker tag "doris-fe:$DORIS_VERSION" "localhost:8082/doris/fe:$DORIS_VERSION-secure"
docker tag "doris-be:$DORIS_VERSION" "localhost:8082/doris/be:$DORIS_VERSION-secure"
docker push "localhost:8082/doris/fe:$DORIS_VERSION-secure"
docker push "localhost:8082/doris/be:$DORIS_VERSION-secure"
Write-Host "[OK] Push complete" -ForegroundColor Green

# 5. Verify
Write-Host ""
Write-Host "[Step 5] Verifying..." -ForegroundColor Yellow
docker pull "localhost:8082/doris/fe:$DORIS_VERSION-secure"
docker pull "localhost:8082/doris/be:$DORIS_VERSION-secure"
docker images | Select-String "localhost:8082/doris-"

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " Verification Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Run security scan: .\scripts\scan-images.ps1"
Write-Host "  2. Deploy to GKE: .\scripts\deploy.ps1"
Write-Host "  3. View docs: .\docs\README.md"
