# ==========================================
# Doris Operator - Security Hardened Image
# ==========================================
# Base: Ubuntu 22.04 LTS
# Version: v1.1.0
# Purpose: 安全加固的 Doris Operator 镜像

# 阶段 1: 构建阶段
FROM golang:1.21-alpine AS builder

ARG OPERATOR_VERSION=v1.1.0
ARG OPERATOR_REPO=https://github.com/apache/doris-operator

# 安装构建依赖
RUN apk add --no-cache git make

# 克隆并构建
WORKDIR /build
RUN git clone --depth 1 --branch ${OPERATOR_VERSION} ${OPERATOR_REPO} . \
    && go mod download \
    && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o /doris-operator ./cmd/operator

# 阶段 2: 安全加固的运行时镜像
FROM ubuntu:22.04

LABEL maintainer="Doris Team"
LABEL version="v1.1.0-secure"
LABEL description="Doris Operator - Security Hardened Image"

# 安全加固: 设置时区和语言
ENV TZ=UTC
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# 安全加固: 创建非 root 用户
RUN groupadd -r doris-operator && useradd -r -g doris-operator -d /app -s /sbin/nologin doris-operator

# 安装最小依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    tzdata \
    && apt-get upgrade -y \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 复制二进制文件
COPY --from=builder /doris-operator /app/doris-operator

# 设置权限
RUN chmod 750 /app/doris-operator \
    && chown -R doris-operator:doris-operator /app

# 使用非 root 用户
USER doris-operator
WORKDIR /app

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8081/healthz || exit 1

# 暴露端口
EXPOSE 8080 8081

# 启动命令
ENTRYPOINT ["/app/doris-operator"]
CMD ["--leader-elect"]
