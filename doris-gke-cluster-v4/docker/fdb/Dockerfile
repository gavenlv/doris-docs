# ==========================================
# FoundationDB - Security Hardened Image
# ==========================================
# Base: Ubuntu 22.04 LTS
# Version: 7.1.37
# Purpose: Build security-hardened FoundationDB image for Doris MetaStore

# ==========================================
# Build Arguments
# ==========================================
ARG FDB_VERSION=7.1.37
ARG OFFLINE_PATH=/build-context/offline-packages

# ==========================================
# Stage 1: Download
# ==========================================
FROM ubuntu:22.04 AS downloader

ARG FDB_VERSION
ARG OFFLINE_PATH

# Install download tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/downloads

# Download FoundationDB packages
COPY ${OFFLINE_PATH}/foundationdb/*.deb /tmp/

RUN ls -la /tmp/*.deb || true

# ==========================================
# Stage 2: Runtime Image
# ==========================================
FROM ubuntu:22.04

LABEL maintainer="Doris Team"
LABEL version="7.1.37-secure"
LABEL description="FoundationDB - Security Hardened Image"

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC
ENV LANG=C.UTF-8

# Security: Create non-root user
RUN groupadd -r foundationdb && \
    useradd -r -g foundationdb -d /opt/foundationdb -s /sbin/nologin foundationdb

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libfoundationdb3 \
    && apt-get upgrade -y \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Copy FoundationDB packages
COPY --from=downloader /tmp/*.deb /tmp/

# Install FoundationDB
RUN dpkg -i /tmp/foundationdb-clients_*.deb && \
    dpkg -i /tmp/foundationdb-server_*.deb && \
    rm -f /tmp/*.deb

# Create directories
RUN mkdir -p /var/log/foundationdb /var/lib/foundationdb/data && \
    chown -R foundationdb:foundationdb /var/log/foundationdb /var/lib/foundationdb

# Configuration
RUN echo "## FoundationDB Configuration" >> /etc/foundationdb/foundationdb.conf && \
    echo "cluster_file = /var/lib/foundationdb/data/fdb.cluster" >> /etc/foundationdb/fdb.conf && \
    chown foundationdb:foundationdb /etc/foundationdb/fdb.conf

# Use non-root user
USER foundationdb
WORKDIR /opt/foundationdb

# Expose ports
EXPOSE 4500 4680

# Start command
ENTRYPOINT ["fdbserver"]
CMD ["--cluster_file", "/var/lib/foundationdb/data/fdb.cluster", "--machine_id", "1", "--address", "0.0.0.0:4500", "--datadir", "/var/lib/foundationdb/data"]
