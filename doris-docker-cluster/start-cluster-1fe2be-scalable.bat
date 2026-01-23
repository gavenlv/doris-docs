@echo off
echo Starting Doris Cluster: 1 FE + 2 BE (Scalable)
echo ========================================
set ENV_FILE=.env.1fe2be.scalable
set COMPOSE_FILE=docker-compose.1fe2be.scalable.yml

if exist %ENV_FILE% (
    echo Using config: %ENV_FILE%
    docker-compose -f %COMPOSE_FILE% --env-file %ENV_FILE% up -d
) else (
    echo Error: %ENV_FILE% not found!
    exit /b 1
)

echo.
echo Cluster started successfully!
echo Web UI: http://localhost:8030
echo MySQL: mysql -h 127.0.0.1 -P 9030 -u root
echo.
echo To add more BE nodes, edit %COMPOSE_FILE% and add new BE services
pause
