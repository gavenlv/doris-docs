# ==========================================
# Doris Backend - Security Hardened Image
# ==========================================
# Base: Ubuntu 22.04 LTS
# Version: 4.0.4
# Purpose: Build security-hardened Doris BE image from local binary package
#
# Build Arguments:
#   DORIS_VERSION: Doris version (default: 4.0.4)
#   SOURCE_TAR: Path to local Doris tar.gz package (optional, for offline build)
#
# Usage:
#   # Online build (download from network)
#   docker build -t doris/be:4.0.4 -f Dockerfile ..
#
#   # Offline build (use local package)
#   docker build \
#       --build-arg SOURCE_TAR=/path/to/apache-doris-4.0.4-bin-x64.tar.gz \
#       -t doris/be:4.0.4 \
#       -f Dockerfile .
# ==========================================

ARG DORIS_VERSION=4.0.4

# ==========================================
# Stage 1: Download or Copy Source
# ==========================================
FROM ubuntu:22.04 AS downloader

ARG DORIS_VERSION

WORKDIR /tmp/downloads

RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    tar \
    gzip \
    && rm -rf /var/lib/apt/lists/*

# If SOURCE_TAR is provided as build arg, copy it; otherwise download
RUN if [ -n "${SOURCE_TAR:-}" ] && [ -f "${SOURCE_TAR}" ]; then \
        echo "Using local package: ${SOURCE_TAR}"; \
        cp "${SOURCE_TAR}" "/tmp/downloads/apache-doris-${DORIS_VERSION}-bin-x64.tar.gz"; \
    else \
        echo "Downloading Doris ${DORIS_VERSION} from network..."; \
        wget -q --timeout=300 \
            "https://apache-doris-releases.oss-accelerate.aliyuncs.com/apache-doris-${DORIS_VERSION}-bin-x64.tar.gz" \
            -O "apache-doris-${DORIS_VERSION}-bin-x64.tar.gz"; \
    fi

RUN tar -xzf "apache-doris-${DORIS_VERSION}-bin-x64.tar.gz" && \
    mv "apache-doris-${DORIS_VERSION}-bin-x64" /doris-package

RUN if [ ! -d "/doris-package/be" ]; then \
        echo "ERROR: BE directory not found in unified package"; \
        ls -la /doris-package/; \
        exit 1; \
    fi

# ==========================================
# Stage 2: Runtime Image
# ==========================================
FROM ubuntu:22.04

LABEL maintainer="Doris Team"
LABEL version="${DORIS_VERSION}-secure"
LABEL description="Doris Backend - Security Hardened Image"

ENV TZ=UTC
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

RUN groupadd -r doris && useradd -r -g doris -d /opt/doris -s /sbin/nologin doris

RUN apt-get update && apt-get install -y --no-install-recommends \
    libstdc++6 \
    tzdata \
    curl \
    && apt-get upgrade -y \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY --from=downloader /doris-package/be /opt/doris/be

RUN mkdir -p /opt/doris/be/log /opt/doris/be/storage && \
    chown -R doris:doris /opt/doris

RUN chmod -R 750 /opt/doris/be && \
    find /opt/doris/be -type f -exec chmod 640 {} \; && \
    find /opt/doris/be/bin -type f -exec chmod 750 {} \;

RUN rm -rf /opt/doris/be/*.md /opt/doris/be/NOTICE /opt/doris/be/LICENSE 2>/dev/null || true

ENV DORIS_HOME=/opt/doris/be
ENV PATH=$DORIS_HOME/bin:$PATH

USER doris
WORKDIR /opt/doris/be

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8040/api/health || exit 1

EXPOSE 8040 9050 8060 9060

ENTRYPOINT ["/opt/doris/be/bin/start_be.sh"]
CMD ["--daemon=false"]