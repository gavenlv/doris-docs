@echo off
chcp 65001 > nul

echo ========================================
echo Doris 4.0.2 Local Cluster Starter
echo ========================================
echo.

echo [Step 1] Cleaning up old containers...
docker rm -f doris-local-fe doris-local-be 2>nul

echo.
echo [Step 2] Starting FE...
docker run -d \
  --name doris-local-fe \
  -p 8030:8030 \
  -p 9030:9030 \
  -e FE_SERVERS=fe1:127.0.0.1:9010 \
  -e FE_ID=1 \
  zlsmshoqvwt6q1.xuanyuan.run/apache/doris:fe-4.0.2

if errorlevel 1 (
  echo [Error] FE failed to start
  echo.
  echo Trying alternative: apache/doris:fe-3.1.4...
  docker run -d \
    --name doris-local-fe \
    -p 8030:8030 \
    -p 9030:9030 \
    -e FE_SERVERS=fe1:127.0.0.1:9010 \
    -e FE_ID=1 \
    apache/doris:fe-3.1.4
)

echo.
echo [Step 3] Starting BE...
docker run -d \
  --name doris-local-be \
  -p 8040:8040 \
  -p 9050:9050 \
  -e BE_ADDR=127.0.0.1:9050 \
  -e FE_HOSTS=doris-local-fe \
  -e FE_PORT=9030 \
  zlsmshoqvwt6q1.xuanyuan.run/apache/doris:be-4.0.2

if errorlevel 1 (
  echo [Error] BE failed to start
  echo.
  echo Note: BE requires FE to be running first!
)

echo.
echo [Step 4] Waiting for services to initialize (60s)...
timeout /t 60 /nobreak > nul

echo.
echo [Step 5] Checking status...
echo.
echo FE Logs:
docker logs doris-local-fe 2>&1 | tail -20
echo.
echo BE Logs:
docker logs doris-local-be 2>&1 | tail -20

echo.
echo ========================================
echo Container Status:
echo ========================================
docker ps -a --filter name=doris-local

echo.
echo Access points:
echo   - FE Web UI:     http://localhost:8030
echo   - MySQL Client: mysql -h127.0.0.1 -P9030 -uroot
echo.
pause
