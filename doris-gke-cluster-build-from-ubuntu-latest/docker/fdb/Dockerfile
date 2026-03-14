# ==========================================
# FoundationDB - Security Hardened Image
# ==========================================
# Base: Ubuntu 22.04 LTS
# Version: 7.1.37
# Purpose: 安全加固的 FoundationDB 镜像

FROM ubuntu:22.04

LABEL maintainer="Doris Team"
LABEL version="7.1.37-secure"
LABEL description="FoundationDB - Security Hardened Image"

ARG FDB_VERSION=7.1.37
ARG FDB_WEBSITE=https://github.com/apple/foundationdb/releases/download

# 安全加固: 设置时区和语言
ENV TZ=UTC
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# 安全加固: 创建非 root 用户
RUN groupadd -r fdb && useradd -r -g fdb -d /var/lib/foundationdb -s /sbin/nologin fdb

# 安装 FoundationDB 并进行安全加固
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    curl \
    ca-certificates \
    tzdata \
    && apt-get upgrade -y \
    && wget -q ${FDB_WEBSITE}/${FDB_VERSION}/foundationdb-clients_${FDB_VERSION}-1_amd64.deb \
    && wget -q ${FDB_WEBSITE}/${FDB_VERSION}/foundationdb-server_${FDB_VERSION}-1_amd64.deb \
    && dpkg -i foundationdb-clients_${FDB_VERSION}-1_amd64.deb \
    && dpkg -i foundationdb-server_${FDB_VERSION}-1_amd64.deb \
    && rm -f *.deb \
    && apt-get remove -y wget \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 创建目录并设置权限
RUN mkdir -p /var/lib/foundationdb/data /var/log/foundationdb \
    && chown -R fdb:fdb /var/lib/foundationdb /var/log/foundationdb \
    && chmod 750 /var/lib/foundationdb /var/log/foundationdb

# 安全加固: 设置配置文件权限
RUN chmod 640 /etc/foundationdb/foundationdb.conf

# 设置环境变量
ENV FDB_CLUSTER_FILE=/etc/foundationdb/fdb.cluster

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD fdbcli --exec "status" || exit 1

# 暴露端口
EXPOSE 4500

# 启动命令
USER fdb
WORKDIR /var/lib/foundationdb

CMD ["/usr/sbin/fdbserver"]
