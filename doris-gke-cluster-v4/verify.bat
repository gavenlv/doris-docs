@echo off
chcp 65001 > nul

echo ========================================
echo Doris 4.0.4 Local Development Setup
echo ========================================
echo.

set DORIS_VERSION=4.0.4
set PROJECT_DIR=%~dp0
set FE_DIR=%PROJECT_DIR%docker\fe
set BE_DIR=%PROJECT_DIR%docker\be

echo [Check] Docker...
docker version >nul 2>&1
if errorlevel 1 (
    echo [Error] Docker is not running or not installed
    pause
    exit /b 1
)
echo [OK] Docker is ready
echo.

echo ========================================
echo Step 1: Check Local Package
echo ========================================
echo.

if not exist "%FE_DIR%\apache-doris-4.0.4-bin-x64.tar.gz" (
    echo [Error] Package not found in %FE_DIR%
    echo Please ensure apache-doris-4.0.4-bin-x64.tar.gz exists
    pause
    exit /b 1
)
echo [OK] Package found, skipping download
echo.

echo ========================================
echo Step 2: Build Docker Images
echo ========================================
echo.

echo Building FE image...
cd /d "%FE_DIR%"
docker build --build-arg DORIS_VERSION=%DORIS_VERSION% -t "doris-fe:%DORIS_VERSION%" .
if errorlevel 1 (
    echo [Error] FE build failed!
    pause
    exit /b 1
)
echo [OK] FE image built
echo.

echo Building BE image...
cd /d "%BE_DIR%"
docker build --build-arg DORIS_VERSION=%DORIS_VERSION% -t "doris-be:%DORIS_VERSION%" .
if errorlevel 1 (
    echo [Error] BE build failed!
    pause
    exit /b 1
)
echo [OK] BE image built
echo.

cd /d "%PROJECT_DIR%"
echo.
echo Built images:
docker images | findstr "doris-"
echo.

echo ========================================
echo Step 3: Start Local Doris Cluster
echo ========================================
echo.

echo Stopping existing containers...
docker-compose -f docker-compose-local.yaml down 2>nul

echo Starting Doris cluster (FE + BE)...
docker-compose -f docker-compose-local.yaml up -d

echo.
echo Waiting for FE to be ready (90s)...
timeout /t 90 /nobreak > nul

echo.
echo ========================================
echo Step 4: Verify Cluster Status
echo ========================================
echo.

echo [FE Status]
docker exec doris-local-fe curl -s http://localhost:8030/api/health 2>nul
if errorlevel 1 (
    echo FE is starting up, waiting more...
    timeout /t 60 /nobreak > nul
)
docker exec doris-local-fe curl -s http://localhost:8030/api/health
echo.

echo [BE Status]
docker exec doris-local-be curl -s http://localhost:8040/api/health
echo.

echo ========================================
echo Step 5: Add BE to Cluster
echo ========================================
echo.

echo Waiting for BE to register with FE...
timeout /t 30 /nobreak > nul

echo.
echo Checking BE registration...
docker exec doris-local-fe mysql -h127.0.0.1 -P9030 -uroot -e "SHOW BACKENDS\G" 2>nul
echo.

echo ========================================
echo Setup Complete!
echo ========================================
echo.
echo Access points:
echo   - FE Web UI:     http://localhost:8030
echo   - BE Web UI:     http://localhost:8040
echo   - MySQL Client:  mysql -h127.0.0.1 -P9030 -uroot
echo.
echo Useful commands:
echo   - View logs:     docker-compose -f docker-compose-local.yaml logs -f
echo   - Stop cluster:  docker-compose -f docker-compose-local.yaml down
echo   - Restart:       docker-compose -f docker-compose-local.yaml restart
echo   - Connect to FE: docker exec -it doris-local-fe mysql -h127.0.0.1 -P9030 -uroot
echo.

pause
