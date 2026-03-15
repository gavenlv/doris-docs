# ==========================================
# FoundationDB - Security Hardened Image
# ==========================================
# Base: Ubuntu 22.04 LTS
# Version: 7.1.37
# Purpose: 安全加固的 FoundationDB 镜像

# 阶段 1: 下载阶段 (构建工具)
FROM ubuntu:22.04 AS downloader

ARG FDB_VERSION=7.1.37
ARG FDB_WEBSITE=https://github.com/apple/foundationdb/releases/download

# 安装下载和安装工具 (仅用于构建)
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    dpkg-dev \
    && rm -rf /var/lib/apt/lists/*

# 下载 FoundationDB DEB 包
WORKDIR /tmp/fdb
RUN wget -q ${FDB_WEBSITE}/${FDB_VERSION}/foundationdb-clients_${FDB_VERSION}-1_amd64.deb \
    && wget -q ${FDB_WEBSITE}/${FDB_VERSION}/foundationdb-server_${FDB_VERSION}-1_amd64.deb

# 阶段 2: 安全加固的运行时镜像 (无额外工具)
FROM ubuntu:22.04

LABEL maintainer="Doris Team"
LABEL version="7.1.37-secure"
LABEL description="FoundationDB - Security Hardened Image"

# 安全加固: 设置时区和语言
ENV TZ=UTC
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# 安全加固: 创建非 root 用户
RUN groupadd -r fdb && useradd -r -g fdb -d /var/lib/foundationdb -s /sbin/nologin fdb

# 安装运行时依赖 (无构建工具)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    tzdata \
    libfoundationdb3 \
    && apt-get upgrade -y \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 从构建阶段复制 DEB 包并安装
COPY --from=downloader /tmp/fdb/*.deb /tmp/
RUN dpkg -i /tmp/foundationdb-clients_${FDB_VERSION}-1_amd64.deb \
    && dpkg -i /tmp/foundationdb-server_${FDB_VERSION}-1_amd64.deb \
    || apt-get install -f -y \
    && rm -rf /tmp/*.deb

# 创建目录并设置权限
RUN mkdir -p /var/lib/foundationdb/data /var/log/foundationdb \
    && chown -R fdb:fdb /var/lib/foundationdb /var/log/foundationdb \
    && chmod 750 /var/lib/foundationdb /var/log/foundationdb

# 设置配置文件权限
RUN chmod 640 /etc/foundationdb/foundationdb.conf

# 设置环境变量
ENV FDB_CLUSTER_FILE=/etc/foundationdb/fdb.cluster

# 使用非 root 用户
USER fdb
WORKDIR /var/lib/foundationdb

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD fdbcli --exec "status" || exit 1

# 暴露端口
EXPOSE 4500

# 启动命令
CMD ["/usr/sbin/fdbserver", "--cluster-file", "/etc/foundationdb/fdb.cluster", "--public-address", "auto:4500"]
