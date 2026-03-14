@echo off
REM ========================================
REM Health Check for Doris Cluster
REM ========================================

echo ========================================
echo Doris Cluster Health Check
echo ========================================

REM Check container status
echo.
echo 1. Container Status:
docker-compose ps

REM Check FE health
echo.
echo 2. FE Health Check:
for /L %%i in (1,1,3) do (
    set /a PORT=8030 + %%i - 1
    echo   - FE%%i (port !PORT!):
    curl -s http://localhost:!PORT!/api/bootstrap >nul 2>&1
    if !errorlevel! equ 0 (
        echo     Ready
    ) else (
        echo     Not ready
    )
)

REM Check BE health
echo.
echo 3. BE Health Check:
for /L %%i in (1,1,3) do (
    set /a PORT=8040 + %%i - 1
    echo   - BE%%i (port !PORT!):
    curl -s http://localhost:!PORT!/api/health >nul 2>&1
    if !errorlevel! equ 0 (
        echo     Ready
    ) else (
        echo     Not ready
    )
)

REM Check MySQL connection
echo.
echo 4. MySQL Connection Check:
mysql -h 127.0.0.1 -P 9030 -u root -e "SELECT 1 as test;" >nul 2>&1
if %errorlevel% equ 0 (
    echo   MySQL connection OK
) else (
    echo   MySQL connection failed
)

REM Check cluster status
echo.
echo 5. Cluster Status:
mysql -h 127.0.0.1 -P 9030 -u root -e "SHOW FRONTENDS\G" 2>nul | findstr /C:"Name" /C:"Host" /C:"Port" /C:"Role" /C:"Alive"
if %errorlevel% neq 0 echo   Unable to get FE status

echo.
mysql -h 127.0.0.1 -P 9030 -u root -e "SHOW BACKENDS;" 2>nul
if %errorlevel% neq 0 echo   Unable to get BE status

REM Check resource usage
echo.
echo 6. Resource Usage:
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" | findstr doris

echo.
echo ========================================
echo Health Check Complete!
echo ========================================
echo.

pause
