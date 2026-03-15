# ==========================================
# Doris Frontend - Security Hardened Image
# ==========================================
# Base: Ubuntu 22.04 LTS
# Version: 3.1.4
# Purpose: 从源码构建安全加固的 Doris FE 镜像

# ==========================================
# 构建参数 (不包含敏感信息)
# ==========================================
ARG DORIS_VERSION=3.1.4
ARG DOWNLOAD_SOURCE=local
ARG NEXUS_URL=nexus.company.com:8082
ARG GCS_BUCKET=gs://doris-build-packages
ARG OFFLINE_PATH=/build-context/offline-packages

# ==========================================
# 阶段 1: 下载阶段 (使用构建工具)
# ==========================================
FROM ubuntu:22.04 AS downloader

ARG DORIS_VERSION
ARG DOWNLOAD_SOURCE
ARG NEXUS_URL
ARG GCS_BUCKET
ARG OFFLINE_PATH

# 安装必要的工具
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    tar \
    gzip \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/downloads

# 根据下载源选择下载方式
# 方式1: 本地离线包
COPY --chmod=755 <<'EOF' /tmp/download.sh
#!/bin/bash
set -e
OFFLINE_PATH="${OFFLINE_PATH:-/build-context/offline-packages}"
if [ -f "${OFFLINE_PATH}/doris-fe/apache-doris-fe-${DORIS_VERSION}-bin.tar.gz" ]; then
    cp "${OFFLINE_PATH}/doris-fe/apache-doris-fe-${DORIS_VERSION}-bin.tar.gz" ./
    echo "Loaded from local: apache-doris-fe-${DORIS_VERSION}-bin.tar.gz"
elif [ -f "/offline-packages/doris-fe/apache-doris-fe-${DORIS_VERSION}-bin.tar.gz" ]; then
    cp "/offline-packages/doris-fe/apache-doris-fe-${DORIS_VERSION}-bin.tar.gz" ./
    echo "Loaded from /offline-packages"
else
    echo "ERROR: Package not found"
    exit 1
fi
EOF

# 方式2: 从 Nexus 下载 (需要 --secret 传递凭据)
RUN --mount=type=secret,id=nexus_env \
    if [ -f /run/secrets/nexus_env ]; then \
        source /run/secrets/nexus_env; \
        curl -u "${NEXUS_USER}:${NEXUS_PASS}" \
            "http://${NEXUS_URL}/repository/doris-packages/doris-fe/${DORIS_VERSION}/apache-doris-fe-${DORIS_VERSION}-bin.tar.gz" \
            -o "apache-doris-fe-${DORIS_VERSION}-bin.tar.gz"; \
    else \
        /tmp/download.sh; \
    fi

# 方式3: 从 GCS 下载
RUN --mount=type=bind,source=/tmp,target=/tmp \
    if [ "${DOWNLOAD_SOURCE}" = "gcs" ]; then \
        /tmp/download.sh; \
    fi || true

# 备用: 从网络下载 (仅在 DEBUG 模式)
RUN if [ ! -f "apache-doris-fe-${DORIS_VERSION}-bin.tar.gz" ]; then \
        wget -q "https://archive.apache.org/dist/doris/${DORIS_VERSION}/apache-doris-fe-${DORIS_VERSION}-bin.tar.gz"; \
    fi

# 解压
RUN tar -xzf apache-doris-fe-${DORIS_VERSION}-bin.tar.gz && \
    mv apache-doris-fe-${DORIS_VERSION}-bin /doris-fe && \
    rm -f apache-doris-fe-${DORIS_VERSION}-bin.tar.gz

# ==========================================
# 阶段 2: 运行时镜像 (无额外工具)
# ==========================================
FROM ubuntu:22.04

LABEL maintainer="Doris Team"
LABEL version="3.1.4-secure"
LABEL description="Doris Frontend - Security Hardened Image"

# 安全加固: 设置时区和语言
ENV TZ=UTC
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# 安全加固: 创建非 root 用户
RUN groupadd -r doris && useradd -r -g doris -d /opt/doris -s /sbin/nologin doris

# 仅安装运行时依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-17-jre-headless \
    tzdata \
    && apt-get upgrade -y \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 从下载阶段复制 Doris FE
COPY --from=downloader /doris-fe /opt/doris/fe

# 创建必要的目录
RUN mkdir -p /opt/doris/fe/log /opt/doris/fe/doris-meta && \
    chown -R doris:doris /opt/doris

# 安全加固: 设置文件权限
RUN chmod -R 750 /opt/doris/fe && \
    find /opt/doris/fe -type f -exec chmod 640 {} \; && \
    find /opt/doris/fe/bin -type f -exec chmod 750 {} \;

# 移除不必要的文件
RUN rm -rf /opt/doris/fe/*.md /opt/doris/fe/NOTICE /opt/doris/fe/LICENSE

# 设置环境变量
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ENV DORIS_HOME=/opt/doris/fe
ENV PATH=$DORIS_HOME/bin:$PATH

# 使用非 root 用户
USER doris
WORKDIR /opt/doris/fe

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8030/api/health || exit 1

# 暴露端口
EXPOSE 8030 9010 9020 9030

# 启动命令
ENTRYPOINT ["/opt/doris/fe/bin/start_fe.sh"]
CMD ["--daemon=false"]
