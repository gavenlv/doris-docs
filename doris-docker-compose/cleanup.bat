@echo off
REM ========================================
REM Cleanup Doris Local Environment
REM ========================================

echo ========================================
echo Cleaning Up Doris Local Environment
echo ========================================

REM Stop all containers
echo Stopping all containers...
docker-compose down

REM Remove volumes
echo Removing data volumes...
docker-compose down -v

REM Ask to remove images
set /p REMOVE_IMAGES="Do you want to remove Doris Docker images? (y/N): "
if /I "%REMOVE_IMAGES%"=="y" (
    echo Removing Doris images...
    docker rmi apache/doris:fe-3.1.4 2>nul
    docker rmi apache/doris:be-3.1.4 2>nul
    docker rmi foundationdb/foundationdb:7.1.37 2>nul
    docker rmi prom/prometheus:v2.45.0 2>nul
    docker rmi grafana/grafana:10.2.0 2>nul
    echo Images removed.
)

REM Remove network
echo Removing network...
docker network rm doris-local 2>nul

echo.
echo ========================================
echo Cleanup Complete!
echo ========================================
echo.
echo To start fresh, run:
echo   start.bat
echo.

pause
