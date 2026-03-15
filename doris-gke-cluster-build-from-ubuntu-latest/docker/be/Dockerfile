# ==========================================
# Doris Backend - Security Hardened Image
# ==========================================
# Base: Ubuntu 22.04 LTS
# Version: 3.1.4
# Purpose: 从源码构建安全加固的 Doris BE 镜像

# ==========================================
# 构建参数
# ==========================================
ARG DORIS_VERSION=3.1.4
ARG DOWNLOAD_SOURCE=local
ARG NEXUS_URL=nexus.company.com:8082
ARG GCS_BUCKET=gs://doris-build-packages
ARG OFFLINE_PATH=/build-context/offline-packages

# ==========================================
# 阶段 1: 下载阶段
# ==========================================
FROM ubuntu:22.04 AS downloader

ARG DORIS_VERSION
ARG DOWNLOAD_SOURCE
ARG NEXUS_URL
ARG OFFLINE_PATH

RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    tar \
    gzip \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/downloads

# 下载 Doris BE
COPY --chmod=755 <<'EOF' /tmp/download.sh
#!/bin/bash
set -e
OFFLINE_PATH="${OFFLINE_PATH:-/build-context/offline-packages}"
if [ -f "${OFFLINE_PATH}/doris-be/apache-doris-be-${DORIS_VERSION}-bin-x86_64.tar.gz" ]; then
    cp "${OFFLINE_PATH}/doris-be/apache-doris-be-${DORIS_VERSION}-bin-x86_64.tar.gz" ./
elif [ -f "/offline-packages/doris-be/apache-doris-be-${DORIS_VERSION}-bin-x86_64.tar.gz" ]; then
    cp "/offline-packages/doris-be/apache-doris-be-${DORIS_VERSION}-bin-x86_64.tar.gz" ./
else
    echo "ERROR: Package not found"
    exit 1
fi
EOF

# 从 Nexus 下载 (需要 --secret 传递凭据)
RUN --mount=type=secret,id=nexus_env \
    if [ -f /run/secrets/nexus_env ]; then \
        source /run/secrets/nexus_env; \
        curl -u "${NEXUS_USER}:${NEXUS_PASS}" \
            "http://${NEXUS_URL}/repository/doris-packages/doris-be/${DORIS_VERSION}/apache-doris-be-${DORIS_VERSION}-bin-x86_64.tar.gz" \
            -o "apache-doris-be-${DORIS_VERSION}-bin-x86_64.tar.gz"; \
    else \
        /tmp/download.sh; \
    fi || /tmp/download.sh

# 解压
RUN tar -xzf apache-doris-be-${DORIS_VERSION}-bin-x86_64.tar.gz && \
    mv apache-doris-be-${DORIS_VERSION}-bin-x86_64 /doris-be && \
    rm -f apache-doris-be-${DORIS_VERSION}-bin-x86_64.tar.gz

# ==========================================
# 阶段 2: 运行时镜像
# ==========================================
FROM ubuntu:22.04

LABEL maintainer="Doris Team"
LABEL version="3.1.4-secure"
LABEL description="Doris Backend - Security Hardened Image"

ENV TZ=UTC
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-0

RUN groupadd -r doris && useradd -r -g doris -d /opt/doris -s /sbin/nologin doris

RUN apt-get update && apt-get install -y --no-install-recommends \
    libstdc++6 \
    tzdata \
    && apt-get upgrade -y \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY --from=downloader /doris-be /opt/doris/be

RUN mkdir -p /opt/doris/be/log /opt/doris/be/storage && \
    chown -R doris:doris /opt/doris

RUN chmod -R 750 /opt/doris/be && \
    find /opt/doris/be -type f -exec chmod 640 {} \; && \
    find /opt/doris/be/bin -type f -exec chmod 750 {} \;

RUN rm -rf /opt/doris/be/*.md /opt/doris/be/NOTICE /opt/doris/be/LICENSE

ENV DORIS_HOME=/opt/doris/be
ENV PATH=$DORIS_HOME/bin:$PATH

USER doris
WORKDIR /opt/doris/be

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8040/api/health || exit 1

EXPOSE 8040 9050 8060 9060

ENTRYPOINT ["/opt/doris/be/bin/start_be.sh"]
CMD ["--daemon=false"]
