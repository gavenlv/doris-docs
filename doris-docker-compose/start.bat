@echo off
REM ========================================
REM Doris Local Cluster - Windows Startup Script
REM ========================================

echo ========================================
echo Starting Doris Local Cluster
echo ========================================

REM Copy .env.example to .env if not exists
if not exist .env (
    echo Copying .env.example to .env...
    copy .env.example .env
)

echo Doris Version: 3.1.4
echo FoundationDB Version: 7.1.37
echo.

REM Start FoundationDB cluster
echo Starting FoundationDB cluster (3 nodes)...
docker-compose up -d fdb1 fdb2 fdb3

echo Waiting for FoundationDB to be ready...
timeout /t 10 /nobreak >nul

REM Start Doris FE cluster
echo Starting Doris FE cluster (3 nodes)...
docker-compose up -d fe1 fe2 fe3

echo Waiting for Doris FE to be ready...
echo This may take 30-60 seconds...
timeout /t 30 /nobreak >nul

REM Start Doris BE cluster
echo Starting Doris BE cluster (3 nodes)...
docker-compose up -d be1 be2 be3

echo.
echo ========================================
echo Doris Local Cluster Started!
echo ========================================
echo.
echo Cluster Information:
echo   - FE Master: http://localhost:8030
echo   - MySQL Connection: mysql -h 127.0.0.1 -P 9030 -u root
echo.
echo To check cluster status:
echo   docker-compose ps
echo.
echo To view FE logs:
echo   docker-compose logs -f fe1
echo.
echo To view BE logs:
echo   docker-compose logs -f be1
echo.

REM Check if monitoring is enabled
findstr /C:"ENABLE_MONITORING=true" .env >nul 2>&1
if %errorlevel% equ 0 (
    echo Starting monitoring services...
    docker-compose --profile monitoring up -d
    echo   - Prometheus: http://localhost:9090
    echo   - Grafana: http://localhost:3000 (admin/admin)
    echo.
)

echo Cluster initialization in progress...
echo Please wait 1-2 minutes for all components to be fully ready.
echo.
echo To verify cluster status, run:
echo   init-cluster.bat
echo.

pause
