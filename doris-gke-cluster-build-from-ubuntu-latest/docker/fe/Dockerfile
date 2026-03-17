# ==========================================
# Doris Frontend - Security Hardened Image
# ==========================================
# Base: Ubuntu 22.04 LTS
# Version: 3.0.5
# Package Format: apache-doris-3.0.5-bin-x64.tar.gz (unified package containing both fe/ and be/)
# Purpose: Build security-hardened Doris FE image from unified binary package
# Note: Doris 3.x uses unified package format: apache-doris-{VERSION}-bin-x64.tar.gz

# ==========================================
# Build Arguments
# ==========================================
ARG DORIS_VERSION=3.0.5
ARG OFFLINE_PATH=/build-context/offline-packages

# ==========================================
# Stage 1: Download and Extract
# ==========================================
FROM ubuntu:22.04 AS downloader

ARG DORIS_VERSION
ARG OFFLINE_PATH

# Install extraction tools only
RUN apt-get update && apt-get install -y --no-install-recommends \
    tar \
    gzip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/downloads

# Copy and extract Doris unified package
# The unified package contains both fe/ and be/ directories
COPY ${OFFLINE_PATH}/apache-doris-${DORIS_VERSION}-bin-x64.tar.gz /tmp/

RUN tar -xzf /tmp/apache-doris-${DORIS_VERSION}-bin-x64.tar.gz && \
    mv apache-doris-${DORIS_VERSION}-bin-x64 /doris-package && \
    ls -la /doris-package/

# Verify FE exists in the package
RUN if [ ! -d "/doris-package/fe" ]; then \
        echo "ERROR: FE directory not found in unified package"; \
        ls -la /doris-package/; \
        exit 1; \
    fi

# ==========================================
# Stage 2: Runtime Image (No extra tools)
# ==========================================
FROM ubuntu:22.04

LABEL maintainer="Doris Team"
LABEL version="3.0.5-secure"
LABEL description="Doris Frontend - Security Hardened Image"

# Security: Set timezone and locale
ENV TZ=UTC
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# Security: Create non-root user
RUN groupadd -r doris && useradd -r -g doris -d /opt/doris -s /sbin/nologin doris

# Install only runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-17-jre-headless \
    tzdata \
    curl \
    && apt-get upgrade -y \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Copy FE from unified package
COPY --from=downloader /doris-package/fe /opt/doris/fe

# Create required directories
RUN mkdir -p /opt/doris/fe/log /opt/doris/fe/doris-meta && \
    chown -R doris:doris /opt/doris

# Security: Set file permissions
RUN chmod -R 750 /opt/doris/fe && \
    find /opt/doris/fe -type f -exec chmod 640 {} \; && \
    find /opt/doris/fe/bin -type f -exec chmod 750 {} \;

# Remove unnecessary files
RUN rm -rf /opt/doris/fe/*.md /opt/doris/fe/NOTICE /opt/doris/fe/LICENSE 2>/dev/null || true

# Set environment variables
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ENV DORIS_HOME=/opt/doris/fe
ENV PATH=$DORIS_HOME/bin:$PATH

# Use non-root user
USER doris
WORKDIR /opt/doris/fe

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8030/api/health || exit 1

# Expose ports
EXPOSE 8030 9010 9020 9030

# Startup command
ENTRYPOINT ["/opt/doris/fe/bin/start_fe.sh"]
CMD ["--daemon=false"]
