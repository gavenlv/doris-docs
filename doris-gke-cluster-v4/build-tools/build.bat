@echo off
chcp 65001 >nul
echo ==========================================
echo   Doris 镜像构建脚本
echo ==========================================
echo.

cd /d "%~dp0"

echo [INFO] 检查 Docker...
docker version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Docker 未运行，请先启动 Docker Desktop
    pause
    exit /b 1
)

echo [INFO] 检查 buildx...
docker buildx version >nul 2>&1
if errorlevel 1 (
    echo [INFO] 配置 buildx...
    docker buildx create --name mybuilder --driver docker-container --use
)

echo [INFO] 启动 buildx...
docker buildx use mybuilder
docker buildx inspect --bootstrap

echo.
echo ==========================================
echo   开始构建镜像
echo ==========================================
echo.

bash build-all.sh

echo.
echo [完成] 按任意键退出...
pause >nul