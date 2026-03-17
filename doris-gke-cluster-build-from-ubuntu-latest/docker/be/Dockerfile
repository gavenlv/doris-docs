# ==========================================
# Doris Backend - Security Hardened Image
# ==========================================
# Base: Ubuntu 22.04 LTS
# Version: 3.0.5
# Package Format: apache-doris-3.0.5-bin-x64.tar.gz (unified package containing both fe/ and be/)
# Purpose: Build security-hardened Doris BE image from unified binary package
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
COPY ${OFFLINE_PATH}/apache-doris-${DORIS_VERSION}-bin-x64.tar.gz /tmp/

RUN tar -xzf /tmp/apache-doris-${DORIS_VERSION}-bin-x64.tar.gz && \
    mv apache-doris-${DORIS_VERSION}-bin-x64 /doris-package && \
    ls -la /doris-package/

# Verify BE exists in the package
RUN if [ ! -d "/doris-package/be" ]; then \
        echo "ERROR: BE directory not found in unified package"; \
        ls -la /doris-package/; \
        exit 1; \
    fi

# ==========================================
# Stage 2: Runtime Image (No extra tools)
# ==========================================
FROM ubuntu:22.04

LABEL maintainer="Doris Team"
LABEL version="3.0.5-secure"
LABEL description="Doris Backend - Security Hardened Image"

ENV TZ=UTC
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# Security: Create non-root user
RUN groupadd -r doris && useradd -r -g doris -d /opt/doris -s /sbin/nologin doris

# Install only runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libstdc++6 \
    tzdata \
    curl \
    && apt-get upgrade -y \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Copy BE from unified package
COPY --from=downloader /doris-package/be /opt/doris/be

# Create required directories
RUN mkdir -p /opt/doris/be/log /opt/doris/be/storage && \
    chown -R doris:doris /opt/doris

# Security: Set file permissions
RUN chmod -R 750 /opt/doris/be && \
    find /opt/doris/be -type f -exec chmod 640 {} \; && \
    find /opt/doris/be/bin -type f -exec chmod 750 {} \;

# Remove unnecessary files
RUN rm -rf /opt/doris/be/*.md /opt/doris/be/NOTICE /opt/doris/be/LICENSE 2>/dev/null || true

ENV DORIS_HOME=/opt/doris/be
ENV PATH=$DORIS_HOME/bin:$PATH

# Use non-root user
USER doris
WORKDIR /opt/doris/be

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8040/api/health || exit 1

# Expose ports
EXPOSE 8040 9050 8060 9060

ENTRYPOINT ["/opt/doris/be/bin/start_be.sh"]
CMD ["--daemon=false"]
