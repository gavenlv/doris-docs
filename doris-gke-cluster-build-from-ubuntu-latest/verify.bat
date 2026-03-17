@echo off
chcp 65001 >nul
REM ==========================================
REM Doris Security Image - Local Verification
REM ==========================================
REM Usage: Run in project root directory

setlocal enabledelayedexpansion

echo ========================================
echo Doris Security Image Local Verification
echo ========================================
echo.

set DORIS_VERSION=3.0.5
set FDB_VERSION=7.1.37
set NEXUS_URL=localhost:8082

REM Check Docker
echo [Check] Docker...
docker version >nul 2>&1
if errorlevel 1 (
    echo [Error] Docker is not running, please start Docker Desktop first
    pause
    exit /b 1
)
echo [OK] Docker is ready
echo.

REM 1. Start Nexus
echo [Step 1] Starting Nexus...
docker ps --filter "name=doris-nexus" --format "{{.Names}}" | findstr "doris-nexus" >nul
if errorlevel 1 (
    echo     Starting Nexus container...
    docker run -d --name doris-nexus -p 8081:8081 -p 8082:8082 sonatype/nexus3:latest
    echo     Waiting for Nexus to start (about 2 minutes)...
    timeout /t 120 /nobreak >nul
)
echo [OK] Nexus is running
echo.

REM 2. Download offline packages
echo [Step 2] Preparing offline packages...
set OFFLINE_DIR=%~dp0offline-packages
if not exist "%OFFLINE_DIR%\doris-fe" mkdir "%OFFLINE_DIR%\doris-fe"
if not exist "%OFFLINE_DIR%\doris-be" mkdir "%OFFLINE_DIR%\doris-be"
if not exist "%OFFLINE_DIR%\foundationdb" mkdir "%OFFLINE_DIR%\foundationdb"

echo     Checking Doris FE package...
if not exist "%OFFLINE_DIR%\doris-fe\apache-doris-fe-%DORIS_VERSION%-bin.tar.gz" (
    echo     Downloading Doris FE...
    powershell -Command "Invoke-WebRequest -Uri 'https://archive.apache.org/dist/doris/%DORIS_VERSION%/apache-doris-fe-%DORIS_VERSION%-bin.tar.gz' -OutFile '%OFFLINE_DIR%\doris-fe\apache-doris-fe-%DORIS_VERSION%-bin.tar.gz'"
) else (
    echo     FE package exists
)

echo     Checking Doris BE package...
if not exist "%OFFLINE_DIR%\doris-be\apache-doris-be-%DORIS_VERSION%-bin-x86_64.tar.gz" (
    echo     Downloading Doris BE...
    powershell -Command "Invoke-WebRequest -Uri 'https://archive.apache.org/dist/doris/%DORIS_VERSION%/apache-doris-be-%DORIS_VERSION%-bin-x86_64.tar.gz' -OutFile '%OFFLINE_DIR%\doris-be\apache-doris-be-%DORIS_VERSION%-bin-x86_64.tar.gz'"
) else (
    echo     BE package exists
)

echo     Checking FoundationDB packages...
if not exist "%OFFLINE_DIR%\foundationdb\foundationdb-clients_%FDB_VERSION%-1_amd64.deb" (
    echo     Downloading FoundationDB...
    powershell -Command "Invoke-WebRequest -Uri 'https://github.com/apple/foundationdb/releases/download/%FDB_VERSION%/foundationdb-clients_%FDB_VERSION%-1_amd64.deb' -OutFile '%OFFLINE_DIR%\foundationdb\foundationdb-clients_%FDB_VERSION%-1_amd64.deb'"
    powershell -Command "Invoke-WebRequest -Uri 'https://github.com/apple/foundationdb/releases/download/%FDB_VERSION%/foundationdb-server_%FDB_VERSION%-1_amd64.deb' -OutFile '%OFFLINE_DIR%\foundationdb\foundationdb-server_%FDB_VERSION%-1_amd64.deb'"
) else (
    echo     FDB packages exist
)

echo [OK] Offline packages ready
echo.

REM 3. Build images
echo [Step 3] Building images...
set PROJECT_DIR=%~dp0

echo     Building Doris FE...
cd /d "%PROJECT_DIR%docker\fe"
docker build --build-arg DORIS_VERSION=%DORIS_VERSION% --build-arg OFFLINE_PATH=%PROJECT_DIR%offline-packages -t "doris-fe:%DORIS_VERSION%" .

echo     Building Doris BE...
cd /d "%PROJECT_DIR%docker\be"
docker build --build-arg DORIS_VERSION=%DORIS_VERSION% --build-arg OFFLINE_PATH=%PROJECT_DIR%offline-packages -t "doris-be:%DORIS_VERSION%" .

cd /d %PROJECT_DIR%
echo [OK] Images built successfully
docker images | findstr "doris-"
echo.

REM 4. Push to Nexus
echo [Step 4] Pushing to Nexus...
echo     Logging in to Nexus (admin/adminadmin)...
echo adminadmin | docker login %NEXUS_URL% -u admin --password-stdin

echo     Tagging images...
docker tag doris-fe:%DORIS_VERSION% %NEXUS_URL%/doris/fe:%DORIS_VERSION%-secure
docker tag doris-be:%DORIS_VERSION% %NEXUS_URL%/doris/be:%DORIS_VERSION%-secure

echo     Pushing FE...
docker push %NEXUS_URL%/doris/fe:%DORIS_VERSION%-secure

echo     Pushing BE...
docker push %NEXUS_URL%/doris/be:%DORIS_VERSION%-secure

echo [OK] Push completed
echo.

REM 5. Verify
echo [Step 5] Verifying...
echo     Pull verification...
docker rmi %NEXUS_URL%/doris/fe:%DORIS_VERSION%-secure 2>nul
docker rmi %NEXUS_URL%/doris/be:%DORIS_VERSION%-secure 2>nul
docker pull %NEXUS_URL%/doris/fe:%DORIS_VERSION%-secure
docker pull %NEXUS_URL%/doris/be:%DORIS_VERSION%-secure

echo.
echo ========================================
echo Verification Complete!
echo ========================================
echo.
echo Nexus URL: http://localhost:8081
echo Docker:    %NEXUS_URL%
echo Images:
echo   %NEXUS_URL%/doris/fe:%DORIS_VERSION%-secure
echo   %NEXUS_URL%/doris/be:%DORIS_VERSION%-secure
echo.

pause
