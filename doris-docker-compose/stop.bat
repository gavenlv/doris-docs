@echo off
REM ========================================
REM Doris Local Cluster - Windows Stop Script
REM ========================================

echo ========================================
echo Stopping Doris Local Cluster
echo ========================================

REM Stop all services
docker-compose down

echo.
echo Cluster stopped successfully!
echo.
echo To remove all data volumes, run:
echo   cleanup.bat
echo.

pause
