# ==========================================
# Doris Operator - Security Hardened Image
# ==========================================
# Base: Ubuntu 22.04 LTS
# Version: v1.1.0
# Purpose: 安全加固的 Doris Operator 镜像

# ==========================================
# 构建参数
# ==========================================
ARG OPERATOR_VERSION=v1.1.0

# ==========================================
# 阶段 1: 构建阶段
# ==========================================
FROM golang:1.21-alpine AS builder

ARG OPERATOR_VERSION

RUN apk add --no-cache git make

WORKDIR /build

RUN git clone --depth 1 --branch ${OPERATOR_VERSION} https://github.com/apache/doris-operator . \
    && go mod download \
    && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o /doris-operator ./cmd/operator

# ==========================================
# 阶段 2: 运行时镜像
# ==========================================
FROM ubuntu:22.04

LABEL maintainer="Doris Team"
LABEL version="v1.1.0-secure"
LABEL description="Doris Operator - Security Hardened Image"

ENV TZ=UTC
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

RUN groupadd -r doris-operator && useradd -r -g doris-operator -d /app -s /sbin/nologin doris-operator

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    tzdata \
    && apt-get upgrade -y \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY --from=builder /doris-operator /app/doris-operator

RUN chmod 750 /app/doris-operator && \
    chown -R doris-operator:doris-operator /app

USER doris-operator
WORKDIR /app

HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8081/healthz || exit 1

EXPOSE 8080 8081

ENTRYPOINT ["/app/doris-operator"]
CMD ["--leader-elect"]
