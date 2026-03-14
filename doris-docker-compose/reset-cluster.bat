@echo off
REM ========================================
REM Reset Doris Cluster
REM ========================================

echo ========================================
echo Resetting Doris Cluster
echo ========================================

REM Stop all services
echo Stopping all services...
docker-compose down

REM Remove all data volumes
echo Removing all data volumes...
docker volume rm doris-local_fe1-data 2>nul
docker volume rm doris-local_fe2-data 2>nul
docker volume rm doris-local_fe3-data 2>nul
docker volume rm doris-local_be1-data 2>nul
docker volume rm doris-local_be2-data 2>nul
docker volume rm doris-local_be3-data 2>nul
docker volume rm doris-local_fdb1-data 2>nul
docker volume rm doris-local_fdb2-data 2>nul
docker volume rm doris-local_fdb3-data 2>nul
docker volume rm doris-local_prometheus-data 2>nul
docker volume rm doris-local_grafana-data 2>nul

echo.
echo Reset complete! Starting fresh cluster...
echo.

REM Start cluster
call start.bat

REM Wait for cluster to be ready
echo.
echo Waiting for cluster to be ready (60 seconds)...
timeout /t 60 /nobreak >nul

REM Initialize cluster
call init-cluster.bat
