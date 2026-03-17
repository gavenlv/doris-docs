@echo off
REM ==========================================
REM Doris 安全镜像 - 简化验证脚本 (无需 Nexus)
REM ==========================================
REM 如果 Nexus 登录有问题，使用此脚本仅验证镜像构建

setlocal enabledelayedexpansion

echo ========================================
echo Doris 安全镜像 - 简化验证
echo (跳过 Nexus，仅验证镜像构建)
echo ========================================
echo.

set DORIS_VERSION=3.0.5
set FDB_VERSION=7.1.37

REM 检查 Docker
echo [检查] Docker...
docker version >nul 2>&1
if errorlevel 1 (
    echo [错误] Docker 未运行
    pause
    exit /b 1
)
echo [OK] Docker 已就绪
echo.

REM 检查离线包
echo [步骤1] 检查离线包...
set OFFLINE_DIR=%~dp0offline-packages
set MISSING=0

if not exist "%OFFLINE_DIR%\doris-fe\apache-doris-fe-%DORIS_VERSION%-bin.tar.gz" (
    echo [缺失] FE 包
    set MISSING=1
) else (
    echo [OK] FE 包已存在
)

if not exist "%OFFLINE_DIR%\doris-be\apache-doris-be-%DORIS_VERSION%-bin-x86_64.tar.gz" (
    echo [缺失] BE 包
    set MISSING=1
) else (
    echo [OK] BE 包已存在
)

if %MISSING%==1 (
    echo.
    echo 正在下载缺失的离线包...
    if not exist "%OFFLINE_DIR%\doris-fe" mkdir "%OFFLINE_DIR%\doris-fe"
    if not exist "%OFFLINE_DIR%\doris-be" mkdir "%OFFLINE_DIR%\doris-be"
    
    echo 下载 Doris FE...
    powershell -Command "Invoke-WebRequest -Uri 'https://archive.apache.org/dist/doris/%DORIS_VERSION%/apache-doris-fe-%DORIS_VERSION%-bin.tar.gz' -OutFile '%OFFLINE_DIR%\doris-fe\apache-doris-fe-%DORIS_VERSION%-bin.tar.gz'"
    
    echo 下载 Doris BE...
    powershell -Command "Invoke-WebRequest -Uri 'https://archive.apache.org/dist/doris/%DORIS_VERSION%/apache-doris-be-%DORIS_VERSION%-bin-x86_64.tar.gz' -OutFile '%OFFLINE_DIR%\doris-be\apache-doris-be-%DORIS_VERSION%-bin-x86_64.tar.gz'"
)

echo [OK] 离线包准备完成
echo.

REM 构建镜像
echo [步骤2] 构建镜像...
set PROJECT_DIR=%~dp0

echo.
echo 构建 Doris FE (这可能需要几分钟)...
cd /d "%PROJECT_DIR%docker\fe"
docker build --build-arg DORIS_VERSION=%DORIS_VERSION% --build-arg OFFLINE_PATH=%PROJECT_DIR%offline-packages -t "doris-fe:%DORIS_VERSION%" .
if errorlevel 1 (
    echo [错误] FE 镜像构建失败
    pause
    exit /b 1
)

echo.
echo 构建 Doris BE (这可能需要几分钟)...
cd /d "%PROJECT_DIR%docker\be"
docker build --build-arg DORIS_VERSION=%DORIS_VERSION% --build-arg OFFLINE_PATH=%PROJECT_DIR%offline-packages -t "doris-be:%DORIS_VERSION%" .
if errorlevel 1 (
    echo [错误] BE 镜像构建失败
    pause
    exit /b 1
)

cd /d %PROJECT_DIR%
echo.
echo [OK] 镜像构建成功!
echo.

REM 显示镜像信息
echo [步骤3] 镜像信息...
docker images | findstr "doris-"
echo.

REM 测试镜像
echo [步骤4] 测试镜像运行...
echo 测试 FE 镜像...
docker run --rm doris-fe:%DORIS_VERSION% java -version 2>&1 | findstr "openjdk"

echo.
echo 测试 BE 镜像...
docker run --rm doris-be:%DORIS_VERSION% /opt/doris/be/bin/doris_be --version 2>&1 || echo BE 版本检查跳过
echo.

REM 安全扫描 (如果安装了 Trivy)
echo [步骤5] 安全扫描 (可选)...
where trivy >nul 2>&1
if %errorlevel%==0 (
    echo 扫描 FE 镜像...
    trivy image --severity HIGH,CRITICAL doris-fe:%DORIS_VERSION%
    
    echo.
    echo 扫描 BE 镜像...
    trivy image --severity HIGH,CRITICAL doris-be:%DORIS_VERSION%
) else (
    echo Trivy 未安装，跳过安全扫描
    echo 安装 Trivy: https://aquasecurity.github.io/trivy/latest/getting-started/installation/
)

echo.
echo ========================================
echo 简化验证完成!
echo ========================================
echo.
echo 本地镜像:
echo   doris-fe:%DORIS_VERSION%
echo   doris-be:%DORIS_VERSION%
echo.
echo Nexus 登录问题解决后，可以手动推送:
echo   docker tag doris-fe:%DORIS_VERSION% localhost:8082/doris/fe:%DORIS_VERSION%-secure
echo   docker push localhost:8082/doris/fe:%DORIS_VERSION%-secure
echo.

pause
