# Doris 4.0.2 客户端配置
# 连接到已有的 Doris 集群

HOST=your-doris-fe-service.namespace.svc.cluster.local
PORT=9030
USER=root
PASSWORD=

# 示例：创建表
# mysql -h$HOST -P$PORT -u$USER -p$PASSWORD

# 如果是本地 Docker Desktop K8s:
# HOST=localhost
# PORT=9030 (需要端口转发)
