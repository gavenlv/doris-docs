@echo off
REM ========================================
REM Quick Start - One Command Setup
REM ========================================

echo ========================================
echo Doris Quick Start
echo ========================================
echo.
echo This script will:
echo   1. Start the Doris cluster
echo   2. Wait for it to be ready
echo   3. Initialize the cluster
echo   4. Run a test
echo.
echo Press any key to continue or Ctrl+C to cancel...
pause >nul

REM Step 1: Start cluster
echo.
echo [Step 1/4] Starting cluster...
call start.bat

REM Step 2: Wait for cluster
echo.
echo [Step 2/4] Waiting for cluster to be ready (90 seconds)...
timeout /t 90 /nobreak >nul

REM Step 3: Initialize cluster
echo.
echo [Step 3/4] Initializing cluster...
call init-cluster.bat

REM Step 4: Test cluster
echo.
echo [Step 4/4] Testing cluster...
call test-cluster.bat

echo.
echo ========================================
echo Quick Start Complete!
echo ========================================
echo.
echo You can now:
echo   - Connect to MySQL: .\connect-mysql.bat
echo   - Access Web UI: http://localhost:8030
echo   - Check health: .\health-check.bat
echo   - View logs: .\view-logs.bat
echo.
echo For more commands, see README-WINDOWS.md
echo.

pause
