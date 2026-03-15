# ==========================================
# FoundationDB - Security Hardened Image
# ==========================================
# Base: Ubuntu 22.04 LTS
# Version: 7.1.37
# Purpose: 安全加固的 FoundationDB 镜像

# ==========================================
# 构建参数
# ==========================================
ARG FDB_VERSION=7.1.37
ARG NEXUS_URL=nexus.company.com:8082
ARG OFFLINE_PATH=/build-context/offline-packages

# ==========================================
# 阶段 1: 下载阶段
# ==========================================
FROM ubuntu:22.04 AS downloader

ARG FDB_VERSION
ARG NEXUS_URL
ARG OFFLINE_PATH

RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    curl \
    dpkg-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/downloads

# 下载 FoundationDB
COPY --chmod=755 <<'EOF' /tmp/download-fdb.sh
#!/bin/bash
set -e
OFFLINE_PATH="${OFFLINE_PATH:-/build-context/offline-packages}"
if [ -f "${OFFLINE_PATH}/foundationdb/foundationdb-clients_${FDB_VERSION}-1_amd64.deb" ]; then
    cp "${OFFLINE_PATH}"/foundationdb/foundationdb-*_${FDB_VERSION}-1_amd64.deb ./
elif [ -f "/offline-packages/foundationdb/foundationdb-clients_${FDB_VERSION}-1_amd64.deb" ]; then
    cp /offline-packages/foundationdb/foundationdb-*_${FDB_VERSION}-1_amd64.deb ./
else
    echo "ERROR: Packages not found"
    exit 1
fi
EOF

RUN --mount=type=secret,id=nexus_env \
    if [ -f /run/secrets/nexus_env ]; then \
        source /run/secrets/nexus_env; \
        curl -u "${NEXUS_USER}:${NEXUS_PASS}" \
            "http://${NEXUS_URL}/repository/doris-packages/foundationdb-clients/${FDB_VERSION}/foundationdb-clients_${FDB_VERSION}-1_amd64.deb" \
            -o "foundationdb-clients_${FDB_VERSION}-1_amd64.deb"; \
        curl -u "${NEXUS_USER}:${NEXUS_PASS}" \
            "http://${NEXUS_URL}/repository/doris-packages/foundationdb-server/${FDB_VERSION}/foundationdb-server_${FDB_VERSION}-1_amd64.deb" \
            -o "foundationdb-server_${FDB_VERSION}-1_amd64.deb"; \
    else \
        /tmp/download-fdb.sh; \
    fi || /tmp/download-fdb.sh

# ==========================================
# 阶段 2: 运行时镜像
# ==========================================
FROM ubuntu:22.04

LABEL maintainer="Doris Team"
LABEL version="7.1.37-secure"
LABEL description="FoundationDB - Security Hardened Image"

ENV TZ=UTC
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

RUN groupadd -r fdb && useradd -r -g fdb -d /var/lib/foundationdb -s /sbin/nologin fdb

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    tzdata \
    libfoundationdb3 \
    && apt-get upgrade -y \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 从下载阶段复制并安装
COPY --from=downloader /tmp/downloads/*.deb /tmp/fdb/
RUN dpkg -i /tmp/fdb/foundationdb-clients_${FDB_VERSION}-1_amd64.deb \
    && dpkg -i /tmp/fdb/foundationdb-server_${FDB_VERSION}-1_amd64.deb \
    || apt-get install -f -y \
    && rm -rf /tmp/fdb

RUN mkdir -p /var/lib/foundationdb/data /var/log/foundationdb && \
    chown -R fdb:fdb /var/lib/foundationdb /var/log/foundationdb && \
    chmod 750 /var/lib/foundationdb /var/log/foundationdb && \
    chmod 640 /etc/foundationdb/foundationdb.conf

ENV FDB_CLUSTER_FILE=/etc/foundationdb/fdb.cluster

USER fdb
WORKDIR /var/lib/foundationdb

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD fdbcli --exec "status" || exit 1

EXPOSE 4500

CMD ["/usr/sbin/fdbserver", "--cluster-file", "/etc/foundationdb/fdb.cluster", "--public-address", "auto:4500"]
