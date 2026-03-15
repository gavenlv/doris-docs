# ==========================================
# Doris Frontend - Security Hardened Image
# ==========================================
# Base: Ubuntu 22.04 LTS
# Version: 3.1.4
# Purpose: 从源码构建安全加固的 Doris FE 镜像

# 阶段 1: 下载阶段 (构建工具)
FROM ubuntu:22.04 AS downloader

ARG DORIS_VERSION=3.1.4
ARG DORIS_DOWNLOAD_URL=https://archive.apache.org/dist/doris

# 安装下载工具 (仅用于下载)
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    tar \
    gzip \
    && rm -rf /var/lib/apt/lists/*

# 下载并解压 Doris FE
WORKDIR /tmp
RUN wget -q ${DORIS_DOWNLOAD_URL}/${DORIS_VERSION}/apache-doris-fe-${DORIS_VERSION}-bin.tar.gz \
    && tar -xzf apache-doris-fe-${DORIS_VERSION}-bin.tar.gz \
    && mv apache-doris-fe-${DORIS_VERSION}-bin /doris-fe \
    && rm -f apache-doris-fe-${DORIS_VERSION}-bin.tar.gz

# 阶段 2: 安全加固的运行时镜像 (无额外工具)
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

# 仅安装运行时依赖 (无构建工具)
RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-17-jre-headless \
    tzdata \
    && apt-get upgrade -y \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 从构建阶段复制 Doris FE
COPY --from=downloader /doris-fe /opt/doris/fe

# 创建必要的目录
RUN mkdir -p /opt/doris/fe/log /opt/doris/fe/doris-meta \
    && chown -R doris:doris /opt/doris

# 安全加固: 设置文件权限
RUN chmod -R 750 /opt/doris/fe \
    && find /opt/doris/fe -type f -exec chmod 640 {} \; \
    && find /opt/doris/fe/bin -type f -exec chmod 750 {} \;

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
