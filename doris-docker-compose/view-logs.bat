@echo off
REM ========================================
REM View Doris Logs
REM ========================================

echo ========================================
echo Doris Log Viewer
echo ========================================
echo.
echo Select which logs to view:
echo   1. All services
echo   2. FE1
echo   3. FE2
echo   4. FE3
echo   5. BE1
echo   6. BE2
echo   7. BE3
echo   8. FDB1
echo   9. FDB2
echo   10. FDB3
echo.

set /p CHOICE="Enter your choice (1-10): "

if "%CHOICE%"=="1" docker-compose logs -f
if "%CHOICE%"=="2" docker-compose logs -f fe1
if "%CHOICE%"=="3" docker-compose logs -f fe2
if "%CHOICE%"=="4" docker-compose logs -f fe3
if "%CHOICE%"=="5" docker-compose logs -f be1
if "%CHOICE%"=="6" docker-compose logs -f be2
if "%CHOICE%"=="7" docker-compose logs -f be3
if "%CHOICE%"=="8" docker-compose logs -f fdb1
if "%CHOICE%"=="9" docker-compose logs -f fdb2
if "%CHOICE%"=="10" docker-compose logs -f fdb3

echo.
pause
