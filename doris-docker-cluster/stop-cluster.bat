@echo off
REM Doris集群停止脚本

echo Stopping Doris cluster...
docker-compose down

echo Doris cluster stopped successfully!

pause
