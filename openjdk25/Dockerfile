# syntax=docker/dockerfile:1.7

ARG ROOTFS_TAR=rootfs.tar.zst
ARG ROOTFS_COMPRESSION=zstd
ARG ROOTFS_SHA=2e0718b7a1dd7dff2f95a425bd48b9327c5e398b1cedd674c4e78fdd87a44858

# -------- Stage 1: importer --------
FROM niceos/base-os:5.2-latest-x86_64 AS importer
ARG ROOTFS_TAR
ARG ROOTFS_COMPRESSION
ARG ROOTFS_SHA
ENV ROOTFS_TAR=${ROOTFS_TAR} ROOTFS_COMPRESSION=${ROOTFS_COMPRESSION} ROOTFS_SHA=${ROOTFS_SHA}

SHELL ["/usr/bin/bash","-o","errexit","-o","nounset","-o","pipefail","-c"]
RUN tdnf -y install tar xz zstd gzip coreutils &&     tdnf -y clean all &&     rm -rf /var/cache/tdnf/* /var/log/*

WORKDIR /work
RUN mkdir -p /rootfs
# ВАЖНО: переменная — литерально ${ROOTFS_TAR}, чтобы подставилась при билде
COPY ${ROOTFS_TAR} /work/

# verify sha (если задан) + распаковка в ОДНОМ RUN
RUN set -euo pipefail;     f1="/work/rootfs.tar.zst";     f2="/work/rootfs.tar.zst";     f="";     if [[ -f "$f1" ]]; then f="$f1"; elif [[ -f "$f2" ]]; then f="$f2"; else echo "[ERROR] rootfs tar not found: tried $f1 and $f2" >&2; exit 1; fi;     if [[ -n "${ROOTFS_SHA:-}" && "${ROOTFS_SHA}" != "null" ]]; then       echo "${ROOTFS_SHA}  $f" | sha256sum -c - ;     else       echo "[WARN] ROOTFS_SHA is empty; skip checksum verify" >&2;     fi;     case "${ROOTFS_COMPRESSION}" in       xz)   xz   -dc "$f" | tar -C /rootfs -xf - ;;       zstd) zstd -dc "$f" | tar -C /rootfs -xf - ;;       gzip) gzip -dc "$f" | tar -C /rootfs -xf - ;;       none) tar  -C /rootfs -xf "$f" ;;       *)    echo "Unknown ROOTFS_COMPRESSION=${ROOTFS_COMPRESSION}" >&2; exit 1 ;;     esac;     rm -f "$f";     test -x /rootfs/usr/bin/bash || { echo "no /usr/bin/bash in rootfs" >&2; exit 1; } && test -d "/rootfs/usr/lib/jvm/OpenJDK-25" && test -x "/rootfs/usr/lib/jvm/OpenJDK-25/bin/java" || { echo "[ERROR] JAVA_HOME=/usr/lib/jvm/OpenJDK-25 missing" >&2; exit 1; }

# -------- Stage 2: final (scratch) --------
FROM scratch

# все OCI label — одним слоем
LABEL org.opencontainers.image.base.name="niceos/base-os:5.2-latest-x86_64"       org.opencontainers.image.created="2025-09-30T21:09:13Z"       org.opencontainers.image.description="OpenJDK 25 for NiceOS 5.2 (profile: runtime)"       org.opencontainers.image.documentation="https://niceos.ru/docs/containers/openjdk25"       org.opencontainers.image.source="https://niceos.ru/package/openjdk25"       org.opencontainers.image.title="openjdk25"       org.opencontainers.image.vendor="NiceSOFT / NiceOS"       org.opencontainers.image.version="25.0.0"       org.opencontainers.image.url="https://niceos.ru"       org.opencontainers.image.revision="latest"       org.opencontainers.image.licenses="GPL-2.0-only WITH Classpath-exception-2.0"       org.opencontainers.image.authors="NiceOS Containers Team <containers@niceos.ru>"       io.niceos.releasever="5.2"       io.niceos.arch="x86_64"       io.niceos.profile="runtime"       io.niceos.build_number="latest"       io.niceos.rootfs.sha256="2e0718b7a1dd7dff2f95a425bd48b9327c5e398b1cedd674c4e78fdd87a44858"       io.niceos.products='["openjdk25"]'       io.niceos.product_versions='{"openjdk25":"25.0.0"}'       io.niceos.product_primary="openjdk25"       io.niceos.product_version_tag="" \
      io.niceos.reports.index='/nicesoft/niceos/reports/5.2-latest-x86_64/index.json'

# переносим rootfs
COPY --from=importer /rootfs/ /

SHELL ["/usr/bin/bash","-o","errexit","-o","nounset","-o","pipefail","-c"]

# Скрипты из контекста — совместимо со старым билдером (раздельный COPY)
COPY scripts/ /nicesoft/niceos/scripts/
COPY entrypoint.sh /nicesoft/niceos/scripts/entrypoint.sh

# Создание пользователя через shadow-utils + копирование из /etc/skel
RUN set -Eeuo pipefail;     chmod +x /nicesoft/niceos/scripts/entrypoint.sh || true;     install -d /etc/profile.d;     printf '%s\n' 'export PATH="__NICEOS_PATH__"' > /etc/profile.d/10-niceos-path.sh;     sed -ri 's|__NICEOS_PATH__|'"/usr/lib/jvm/OpenJDK-25/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"'|' /etc/profile.d/10-niceos-path.sh;     chmod 0644 /etc/profile.d/10-niceos-path.sh;     if ! grep -q '/etc/profile.d' /etc/profile 2>/dev/null; then       printf '\n# NiceOS: source /etc/profile.d/*.sh\nif [ -d /etc/profile.d ]; then\n  for s in /etc/profile.d/*.sh; do [ -r "$s" ] && . "$s"; done\nfi\n' >> /etc/profile;     fi;     if [[ ! -s /etc/nsswitch.conf ]]; then       printf '%s\n' 'passwd: files' 'group: files' 'shadow: files' > /etc/nsswitch.conf;     fi;     if ! command -v useradd >/dev/null 2>&1; then       echo "[ERROR] shadow-utils (useradd) not found in rootfs. Please add 'shadow-utils' to the rootfs before building the image." >&2;       exit 1;     fi;     if ! getent group 10001 >/dev/null 2>&1; then       if getent group app >/dev/null 2>&1; then         groupmod -g 10001 app;       else         groupadd -g 10001 app;       fi;     fi;     if id -u app >/dev/null 2>&1; then       usermod -u 10001 -g 10001 -d /home/app -s /usr/bin/bash app;     else       useradd -m -k /etc/skel -d /home/app -s /usr/bin/bash -u 10001 -g 10001 -c "NiceOS App User" app;     fi;     if [[ -d /etc/skel ]]; then       cp -an /etc/skel/. /home/app/ || true;     fi;     mkdir -p /app /tmp /var/tmp;     chown -R 10001:10001 /home/app /app;     chmod 1777 /tmp /var/tmp

# Переменные окружения — одним слоем
ENV APP_NAME="openjdk25"     APP_VERSION="25.0.0"     IMAGE_REVISION="latest"     NICEOS_RELEASEVER="5.2"     NICEOS_BUILD_NUMBER="latest"     NICEOS_PROFILE="runtime"     JAVA_HOME="/usr/lib/jvm/OpenJDK-25"     HOME="/home/app"     LANG="en_US.UTF-8"     LC_ALL="en_US.UTF-8"     PATH="/usr/lib/jvm/OpenJDK-25/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

WORKDIR /app
USER 10001:10001

ENTRYPOINT [ "/nicesoft/niceos/scripts/entrypoint.sh" ]
CMD [ "bash" ]
