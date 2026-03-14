@echo off
REM ========================================
REM Initialize Doris Cluster
REM ========================================

echo ========================================
echo Initializing Doris Cluster
echo ========================================

REM Wait for FE to be ready
echo Waiting for FE to be ready...
:wait_fe
curl -s http://localhost:8030/api/bootstrap >nul 2>&1
if %errorlevel% neq 0 (
    echo FE not ready yet, waiting...
    timeout /t 5 /nobreak >nul
    goto wait_fe
)

echo FE is ready!
echo.

REM Connect to FE and add BE nodes
echo Adding BE nodes to cluster...

REM Add be1
mysql -h 127.0.0.1 -P 9030 -u root -e "ALTER SYSTEM ADD BACKEND 'be1:9050';" 2>nul
if %errorlevel% equ 0 (
    echo be1 added successfully
) else (
    echo be1 may already exist
)

REM Add be2
mysql -h 127.0.0.1 -P 9030 -u root -e "ALTER SYSTEM ADD BACKEND 'be2:9050';" 2>nul
if %errorlevel% equ 0 (
    echo be2 added successfully
) else (
    echo be2 may already exist
)

REM Add be3
mysql -h 127.0.0.1 -P 9030 -u root -e "ALTER SYSTEM ADD BACKEND 'be3:9050';" 2>nul
if %errorlevel% equ 0 (
    echo be3 added successfully
) else (
    echo be3 may already exist
)

echo.
echo Waiting for BE nodes to join cluster...
timeout /t 10 /nobreak >nul

REM Check cluster status
echo.
echo ========================================
echo Cluster Status:
echo ========================================
echo.
echo Frontends:
mysql -h 127.0.0.1 -P 9030 -u root -e "SHOW FRONTENDS\G"

echo.
echo Backends:
mysql -h 127.0.0.1 -P 9030 -u root -e "SHOW BACKENDS;"

echo.
echo ========================================
echo Cluster Initialization Complete!
echo ========================================
echo.
echo You can now:
echo   1. Connect to MySQL: mysql -h 127.0.0.1 -P 9030 -u root
echo   2. Access FE Web UI: http://localhost:8030
echo   3. Create databases and tables
echo.

pause
