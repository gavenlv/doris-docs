@echo off
REM ========================================
REM Connect to Doris MySQL
REM ========================================

echo ========================================
echo Connecting to Doris MySQL
echo ========================================
echo.
echo Connecting to: 127.0.0.1:9030
echo User: root
echo Password: (none)
echo.
echo Type 'exit' to quit MySQL
echo.

REM Try to connect using MySQL client
mysql -h 127.0.0.1 -P 9030 -u root 2>nul

if %errorlevel% neq 0 (
    echo.
    echo MySQL client not found!
    echo.
    echo Options:
    echo   1. Install MySQL client
    echo      - Use Chocolatey: choco install mysql-cli
    echo      - Or download from: https://dev.mysql.com/downloads/installer/
    echo.
    echo   2. Use Docker MySQL client
    echo      docker run --rm -it mysql:8.0 mysql -h host.docker.internal -P 9030 -u root
    echo.
    echo   3. Use Web UI
    echo      Open browser: http://localhost:8030
    echo.
    pause
)
