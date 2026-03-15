@echo off
REM ==========================================
REM Doris 安全镜像 - 本地验证脚本
REM ==========================================
REM 使用方法: 在项目根目录双击运行

setlocal enabledelayedexpansion

echo ========================================
echo Doris 安全镜像本地验证
echo ========================================
echo.

set DORIS_VERSION=3.1.4
set FDB_VERSION=7.1.37
set NEXUS_URL=localhost:8082

REM 检查 Docker
echo [检查] Docker...
docker version >nul 2>&1
if errorlevel 1 (
    echo [错误] Docker 未运行，请先启动 Docker Desktop
    pause
    exit /b 1
)
echo [OK] Docker 已就绪
echo.

REM 1. 启动 Nexus
echo [步骤1] 启动 Nexus...
docker ps --filter "name=doris-nexus" --format "{{.Names}}" | findstr "doris-nexus" >nul
if errorlevel 1 (
    echo     启动 Nexus 容器...
    docker run -d --name doris-nexus -p 8081:8081 -p 8082:8082 sonatype/nexus3:latest
    echo     等待 Nexus 启动 (约 2 分钟)...
    timeout /t 120 /nobreak >nul
)
echo [OK] Nexus 已运行
echo.

REM 2. 下载离线包
echo [步骤2] 准备离线包...
set OFFLINE_DIR=%~dp0offline-packages
if not exist "%OFFLINE_DIR%\doris-fe" mkdir "%OFFLINE_DIR%\doris-fe"
if not exist "%OFFLINE_DIR%\doris-be" mkdir "%OFFLINE_DIR%\doris-be"
if not exist "%OFFLINE_DIR%\foundationdb" mkdir "%OFFLINE_DIR%\foundationdb"

echo     检查 Doris FE 包...
if not exist "%OFFLINE_DIR%\doris-fe\apache-doris-fe-%DORIS_VERSION%-bin.tar.gz" (
    echo     下载 Doris FE...
    powershell -Command "Invoke-WebRequest -Uri 'https://archive.apache.org/dist/doris/%DORIS_VERSION%/apache-doris-fe-%DORIS_VERSION%-bin.tar.gz' -OutFile '%OFFLINE_DIR%\doris-fe\apache-doris-fe-%DORIS_VERSION%-bin.tar.gz'"
) else (
    echo     FE 包已存在
)

echo     检查 Doris BE 包...
if not exist "%OFFLINE_DIR%\doris-be\apache-doris-be-%DORIS_VERSION%-bin-x86_64.tar.gz" (
    echo     下载 Doris BE...
    powershell -Command "Invoke-WebRequest -Uri 'https://archive.apache.org/dist/doris/%DORIS_VERSION%/apache-doris-be-%DORIS_VERSION%-bin-x86_64.tar.gz' -OutFile '%OFFLINE_DIR%\doris-be\apache-doris-be-%DORIS_VERSION%-bin-x86_64.tar.gz'"
) else (
    echo     BE 包已存在
)

echo     检查 FoundationDB 包...
if not exist "%OFFLINE_DIR%\foundationdb\foundationdb-clients_%FDB_VERSION%-1_amd64.deb" (
    echo     下载 FoundationDB...
    powershell -Command "Invoke-WebRequest -Uri 'https://github.com/apple/foundationdb/releases/download/%FDB_VERSION%/foundationdb-clients_%FDB_VERSION%-1_amd64.deb' -OutFile '%OFFLINE_DIR%\foundationdb\foundationdb-clients_%FDB_VERSION%-1_amd64.deb'"
    powershell -Command "Invoke-WebRequest -Uri 'https://github.com/apple/foundationdb/releases/download/%FDB_VERSION%/foundationdb-server_%FDB_VERSION%-1_amd64.deb' -OutFile '%OFFLINE_DIR%\foundationdb\foundationdb-server_%FDB_VERSION%-1_amd64.deb'"
) else (
    echo     FDB 包已存在
)

echo [OK] 离线包准备完成
echo.

REM 3. 构建镜像
echo [步骤3] 构建镜像...
set PROJECT_DIR=%~dp0

echo     构建 Doris FE...
cd /d "%PROJECT_DIR%docker\fe"
docker build --build-arg DORIS_VERSION=%DORIS_VERSION% --build-arg OFFLINE_PATH=%PROJECT_DIR%offline-packages -t "doris-fe:%DORIS_VERSION%" .

echo     构建 Doris BE...
cd /d "%PROJECT_DIR%docker\be"
docker build --build-arg DORIS_VERSION=%DORIS_VERSION% --build-arg OFFLINE_PATH=%PROJECT_DIR%offline-packages -t "doris-be:%DORIS_VERSION%" .

cd /d %PROJECT_DIR%
echo [OK] 镜像构建完成
docker images | findstr "doris-"
echo.

REM 4. 推送到 Nexus
echo [步骤4] 推送到 Nexus...
echo     登录 Nexus (默认 admin/admin123)...
echo admin123 | docker login %NEXUS_URL% -u admin --password-stdin

echo     Tag 镜像...
docker tag doris-fe:%DORIS_VERSION% %NEXUS_URL%/doris/fe:%DORIS_VERSION%-secure
docker tag doris-be:%DORIS_VERSION% %NEXUS_URL%/doris/be:%DORIS_VERSION%-secure

echo     推送 FE...
docker push %NEXUS_URL%/doris/fe:%DORIS_VERSION%-secure

echo     推送 BE...
docker push %NEXUS_URL%/doris/be:%DORIS_VERSION%-secure

echo [OK] 推送完成
echo.

REM 5. 验证
echo [步骤5] 验证...
echo     拉取验证...
docker rmi %NEXUS_URL%/doris/fe:%DORIS_VERSION%-secure 2>nul
docker rmi %NEXUS_URL%/doris/be:%DORIS_VERSION%-secure 2>nul
docker pull %NEXUS_URL%/doris/fe:%DORIS_VERSION%-secure
docker pull %NEXUS_URL%/doris/be:%DORIS_VERSION%-secure

echo.
echo ========================================
echo 验证完成!
echo ========================================
echo.
echo Nexus 地址: http://localhost:8081
echo Docker:     %NEXUS_URL%
echo 镜像:
echo   %NEXUS_URL%/doris/fe:%DORIS_VERSION%-secure
echo   %NEXUS_URL%/doris/be:%DORIS_VERSION%-secure
echo.

pause
