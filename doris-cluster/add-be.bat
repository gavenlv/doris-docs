@echo off
echo Adding new BE node to scalable cluster
echo ========================================
set ENV_FILE=.env.1fe2be.scalable
set COMPOSE_FILE=docker-compose.1fe2be.scalable.yml

if "%1"=="" (
    echo Usage: add-be.bat ^<be_number^> ^<be_ip^>
    echo Example: add-be.bat 3 172.23.0.23
    exit /b 1
)

set BE_NUM=%1
set BE_IP=%2

if "%BE_IP%"=="" (
    echo Error: BE IP address is required!
    echo Usage: add-be.bat ^<be_number^> ^<be_ip^>
    echo Example: add-be.bat 3 172.23.0.23
    exit /b 1
)

echo Adding BE%BE_NUM% with IP: %BE_IP%

echo.
echo Please add the following to %COMPOSE_FILE%:
echo.
echo   be%BE_NUM%:
echo     ^<^<: *be-common
echo     container_name: doris_be%BE_NUM%
echo     hostname: be%BE_NUM%
echo     ports:
echo       - "906%BE_NUM%:9060"
echo       - "804%BE_NUM%:8040"
echo       - "905%BE_NUM%:9050"
echo     volumes:
echo       - ./be/be%BE_NUM%/conf:/opt/doris/be/conf
echo       - ./be/be%BE_NUM%/data:/opt/doris/be/storage
echo       - ./be/be%BE_NUM%/log:/opt/doris/be/log
echo     environment:
echo       - FE_SERVERS=${DORIS_FE_SERVERS}
echo       - BE_ADDR=%BE_IP%:9050
echo     networks:
echo       doris_net:
echo         ipv4_address: %BE_IP%
echo.
echo Then add to %ENV_FILE%:
echo   DORIS_BE%BE_NUM%_IP=%BE_IP%
echo.
echo After updating files, run:
echo   docker-compose -f %COMPOSE_FILE% --env-file %ENV_FILE% up -d
echo.
echo Finally, add the BE to Doris cluster:
echo   docker exec doris_fe1 mysql -h 127.0.0.1 -P 9030 -u root -e "ALTER SYSTEM ADD BACKEND '%BE_IP%:9050';"
pause
