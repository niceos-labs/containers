# syntax=docker/dockerfile:1.7

ARG ROOTFS_TAR=rootfs.tar.zst
ARG ROOTFS_COMPRESSION=zstd
ARG ROOTFS_SHA=f55f3940146315bf9f05a5df1f7a060d1d41a0625d556b6249b0678e5da90196

# -------- Stage 1: importer --------
FROM niceos/base-os:5.2-latest-x86_64 AS importer
ARG ROOTFS_TAR
ARG ROOTFS_COMPRESSION
ARG ROOTFS_SHA
ENV ROOTFS_TAR=${ROOTFS_TAR} ROOTFS_COMPRESSION=${ROOTFS_COMPRESSION} ROOTFS_SHA=${ROOTFS_SHA}

SHELL ["/usr/bin/bash","-o","errexit","-o","nounset","-o","pipefail","-c"]

# Minimal tooling to unpack compressed rootfs
RUN tdnf -y install tar xz zstd gzip coreutils \
 && tdnf -y clean all \
 && rm -rf /var/cache/tdnf/* /var/log/*

WORKDIR /work
RUN mkdir -p /rootfs
# IMPORTANT: keep ${ROOTFS_TAR} literal so build arg substitution works
COPY ${ROOTFS_TAR} /work/

# Verify checksum (if provided) and extract in a single layer
RUN set -euo pipefail; \
    f="/work/$(basename "${ROOTFS_TAR}")"; \
    if [[ ! -f "$f" ]]; then echo "[ERROR] rootfs tar not found: $f" >&2; exit 1; fi; \
    if [[ -n "${ROOTFS_SHA:-}" && "${ROOTFS_SHA}" != "null" ]]; then \
      echo "${ROOTFS_SHA}  $f" | sha256sum -c - ; \
    else \
      echo "[WARN] ROOTFS_SHA is empty; skip checksum verification" >&2; \
    fi; \
    case "${ROOTFS_COMPRESSION}" in \
      xz)   xz   -dc "$f" | tar -C /rootfs -xf - ;; \
      zstd) zstd -dc "$f" | tar -C /rootfs -xf - ;; \
      gzip) gzip -dc "$f" | tar -C /rootfs -xf - ;; \
      none) tar  -C /rootfs -xf "$f" ;; \
      *)    echo "Unknown ROOTFS_COMPRESSION=${ROOTFS_COMPRESSION}" >&2; exit 1 ;; \
    esac; \
    rm -f "$f"; \
    test -x /rootfs/usr/bin/bash || { echo "no /usr/bin/bash in rootfs" >&2; exit 1; }

# -------- Stage 2: final (scratch) --------
FROM scratch

# OCI labels: keep single layer and valid continuations (no stray backslashes)
LABEL org.opencontainers.image.base.name="niceos/base-os:5.2-latest-x86_64" \
      org.opencontainers.image.created="2025-10-02T10:25:42Z" \
      org.opencontainers.image.description="redis image for NiceOS 5.2 (profile: runtime)" \
      org.opencontainers.image.documentation="https://nice-soft.com/containers/redis" \
      org.opencontainers.image.source="https://nice-soft.com/package/redis" \
      org.opencontainers.image.title="redis" \
      org.opencontainers.image.vendor="NiceSOFT / NiceOS" \
      org.opencontainers.image.version="8.2.1" \
      org.opencontainers.image.url="https://nice-soft.com" \
      org.opencontainers.image.revision="latest" \
      org.opencontainers.image.authors="NiceOS Containers Team <containers@nice-soft-com>" \
      io.niceos.releasever="5.2" \
      io.niceos.arch="x86_64" \
      io.niceos.profile="runtime" \
      io.niceos.build_number="latest" \
      io.niceos.products='["redis"]' \
      io.niceos.product_versions='{"redis":"8.2.1"}' \
      io.niceos.product_primary="redis" \
      io.niceos.product_version_tag="" \
      io.niceos.reports.index='/nicesoft/niceos/reports/5.2-latest-x86_64/index.json'

# Bring rootfs
COPY --from=importer /rootfs/ /

SHELL ["/usr/bin/bash","-o","errexit","-o","nounset","-o","pipefail","-c"]

# Copy NiceOS scripts
COPY scripts/ /nicesoft/niceos/scripts/
COPY entrypoint.sh /nicesoft/niceos/scripts/entrypoint.sh

# System/user setup and filesystem ownership — do it in ONE RUN for fewer layers
RUN set -Eeuo pipefail; \
    chmod +x /nicesoft/niceos/scripts/entrypoint.sh || true; \
    install -d /etc/profile.d; \
    printf '%s\n' 'export PATH="__NICEOS_PATH__"' > /etc/profile.d/10-niceos-path.sh; \
    sed -ri 's|__NICEOS_PATH__|'"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"'|' /etc/profile.d/10-niceos-path.sh; \
    chmod 0644 /etc/profile.d/10-niceos-path.sh; \
    if ! grep -q '/etc/profile.d' /etc/profile 2>/dev/null; then \
      printf '\n# NiceOS: source /etc/profile.d/*.sh\nif [ -d /etc/profile.d ]; then\n  for s in /etc/profile.d/*.sh; do [ -r "$s" ] && . "$s"; done\nfi\n' >> /etc/profile; \
    fi; \
    [[ -s /etc/nsswitch.conf ]] || printf '%s\n' 'passwd: files' 'group: files' 'shadow: files' > /etc/nsswitch.conf; \
    command -v useradd >/dev/null 2>&1 || { echo "[ERROR] shadow-utils (useradd) missing in rootfs" >&2; exit 1; }; \
    if ! getent group 10001 >/dev/null 2>&1; then \
      if getent group app >/dev/null 2>&1; then groupmod -g 10001 app; else groupadd -g 10001 app; fi; \
    fi; \
    if id -u app >/dev/null 2>&1; then \
      usermod -u 10001 -g 10001 -d /home/app -s /usr/bin/bash app; \
    else \
      useradd -m -k /etc/skel -d /home/app -s /usr/bin/bash -u 10001 -g 10001 -c "NiceOS App User" app; \
    fi; \
    [[ -d /etc/skel ]] && cp -an /etc/skel/. /home/app/ || true; \
    mkdir -p /app /tmp /var/tmp; \
    chown -R 10001:10001 /home/app /app; \
    chmod 1777 /tmp /var/tmp; \
    chmod g+rwX /nicesoft/niceos || true; \
    mkdir -p /app/etc /app/etc.default /app/data /app/logs /app/run; \
    cp -a /etc/redis.conf /app/etc.default/redis.conf; \
    test -x /usr/bin/redis-server && test -x /usr/bin/redis-cli; \
    chown -R app:app /app


# Base environment in a single layer
ENV APP_NAME="redis" \
    APP_VERSION="8.2.1" \
    IMAGE_REVISION="latest" \
    NICEOS_RELEASEVER="5.2" \
    NICEOS_BUILD_NUMBER="latest" \
    NICEOS_PROFILE="runtime" \
    JAVA_HOME="" \
    HOME="/home/app" \
    LANG="en_US.UTF-8" \
    LC_ALL="en_US.UTF-8" \
    PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    REDIS_CONF_DIR="/app/etc" \
    REDIS_DEFAULT_CONF_DIR="/app/etc.default" \
    REDIS_MOUNTED_CONF_DIR="/app/mounted-etc" \
    REDIS_CONF_FILE="/app/etc/redis.conf" \
    REDIS_DATA_DIR="/app/data" \
    REDIS_LOG_DIR="/app/logs" \
    REDIS_TMP_DIR="/app/run" \
    REDIS_BIN_DIR="/usr/bin" \
    REDIS_LOG_FILE="/app/logs/redis.log" \
    REDIS_PID_FILE="/app/run/redis.pid" \
    NICEOS_REDIS_RUN_SETUP="yes"

EXPOSE 6379

WORKDIR /app
USER 10001:10001

# VOLUME ["/app/data", "/app/logs"]

# Healthcheck: simple liveness probe using redis-cli
# Note: relies on PATH and that Redis listens on 127.0.0.1:6379 by default
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD /usr/bin/env REDISCLI_AUTH="${REDIS_PASSWORD:-}" /usr/bin/redis-cli \
      $([ "${REDIS_TLS_ENABLED}" = "yes" ] && echo --tls) -h 127.0.0.1 \
      -p $([ "${REDIS_TLS_ENABLED}" = "yes" ] && echo "${REDIS_TLS_PORT_NUMBER:-6379}" || echo 6379) \
      ping | grep -qi PONG || exit 1

ENTRYPOINT [ "/nicesoft/niceos/scripts/entrypoint.sh" ]
CMD [ "/nicesoft/niceos/scripts/run-redis.sh" ]
