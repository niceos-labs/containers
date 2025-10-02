#!/usr/bin/env bash
# =============================================================================
#  NiceOS · Redis Setup (Bitnami-like tuning via libredis; no config generation)
# =============================================================================
# shellcheck disable=SC1091

set -Eeuo pipefail

# --------------------------- Load environment & libs --------------------------
. /nicesoft/niceos/scripts/redis-env.sh
. /nicesoft/niceos/scripts/liblog.sh
. /nicesoft/niceos/scripts/libos.sh
[[ -r /nicesoft/niceos/scripts/libfs.sh ]] && . /nicesoft/niceos/scripts/libfs.sh
. /nicesoft/niceos/scripts/libredis.sh

info "🔧 NiceOS Redis setup starting…"
debug "Paths:
$(indent "BASE=${REDIS_BASE_DIR:-/usr}
CONF_DIR=${REDIS_CONF_DIR}
CONF_FILE=${REDIS_CONF_FILE}
DEFAULT_CONF_DIR=${REDIS_DEFAULT_CONF_DIR}
DATA_DIR=${REDIS_DATA_DIR}
LOG_DIR=${REDIS_LOG_DIR}
TMP_DIR=${REDIS_TMP_DIR}
BIN_DIR=${REDIS_BIN_DIR}" 2)
"

# --------------------------- Validate environment -----------------------------
_validate_minimal() {
  local ok=true
  command -v redis-server >/dev/null 2>&1 || { error "redis-server not found in PATH (${PATH})"; ok=false; }
  if [[ -z "${REDIS_CONF_FILE:-}" ]]; then
    error "REDIS_CONF_FILE is empty"; ok=false
  elif [[ ! -r "${REDIS_CONF_FILE}" ]]; then
    error "Redis config is missing or not readable: '${REDIS_CONF_FILE}' (no auto-generation by design)"; ok=false
  fi
  for d in "$REDIS_DATA_DIR" "$REDIS_LOG_DIR" "$REDIS_TMP_DIR"; do
    [[ -n "$d" ]] || { error "One of required dirs is empty (DATA/LOG/TMP)."; ok=false; }
  done
  $ok || return 1
}

if declare -F redis_validate >/dev/null 2>&1; then
  redis_validate
else
  _validate_minimal
fi
info "✓ Environment validation passed"

# --------------------------- Users & directories ------------------------------
# Create runtime directories (idempotent)
for d in "$REDIS_DATA_DIR" "$REDIS_LOG_DIR" "$REDIS_TMP_DIR"; do
  [[ -d "$d" ]] || mkdir -p "$d"
done

if am_i_root; then
  ensure_user_exists "${REDIS_DAEMON_USER}" --group "${REDIS_DAEMON_GROUP}"
  chown -R "${REDIS_DAEMON_USER}:${REDIS_DAEMON_GROUP}" \
    "$REDIS_DATA_DIR" "$REDIS_LOG_DIR" "$REDIS_TMP_DIR"
  chmod 750 "$REDIS_TMP_DIR" || true
  chown root:"${REDIS_DAEMON_GROUP}" "${REDIS_CONF_FILE}" || true
  chmod 0640 "${REDIS_CONF_FILE}" || true
  case "${NICEOS_REDIS_CONF_GROUP_WRITABLE:-no}" in
    1|true|yes|TRUE|YES) chmod g+rw "${REDIS_CONF_FILE}" || true ;;
  esac
else
  for d in "$REDIS_DATA_DIR" "$REDIS_LOG_DIR" "$REDIS_TMP_DIR"; do
    [[ -w "$d" ]] || warn "Non-root user cannot write to '${d}'. Consider fixing ownership at build-time."
  done
  [[ -r "${REDIS_CONF_FILE}" ]] || warn "Config not readable by the current user: '${REDIS_CONF_FILE}'"
fi

# --------------------------- Bitnami-like config tuning -----------------------
info "Applying Bitnami-like defaults to the existing redis.conf (idempotent)…"

# Networking: protected-mode & bind (dev-friendly overrides)
if is_boolean_yes "${ALLOW_EMPTY_PASSWORD:-no}"; then
  warn "ALLOW_EMPTY_PASSWORD=${ALLOW_EMPTY_PASSWORD} — this is unsafe in production."
  redis_conf_set protected-mode no
fi
if is_boolean_yes "${REDIS_ALLOW_REMOTE_CONNECTIONS:-yes}"; then
  redis_conf_set bind "0.0.0.0 ::"
fi

# Port / dir / pidfile
redis_conf_set port    "${REDIS_PORT_NUMBER}"
redis_conf_set dir     "${REDIS_DATA_DIR}"
redis_conf_set pidfile "${REDIS_PID_FILE}"

# Daemon / logging
redis_conf_set daemonize yes
redis_conf_set logfile ""

# Persistence: AOF on, disable RDB snapshots by default
# Ref: https://redis.io/docs/latest/operate/oss_and_stack/management/persistence/#interactions-between-aof-and-rdb-persistence
redis_conf_set save ""
redis_conf_set appendonly "${REDIS_AOF_ENABLED:-yes}"
redis_conf_set appendfsync everysec

# Authentication
if [[ -n "${REDIS_PASSWORD:-}" ]]; then
  redis_conf_set requirepass "${REDIS_PASSWORD}"
else
  redis_conf_unset requirepass
fi

# Disable unsafe commands (default hardened baseline unless overridden)
if [[ -z "${REDIS_DISABLE_COMMANDS:-}" ]]; then
  REDIS_DISABLE_COMMANDS="FLUSHALL,FLUSHDB,CONFIG,SHUTDOWN,DEBUG,CLUSTER"
fi
[[ -n "${REDIS_DISABLE_COMMANDS:-}" ]] && redis_disable_unsafe_commands

# TLS (full block)
if is_boolean_yes "${REDIS_TLS_ENABLED:-no}"; then
  # Port collision handling (TLS-only if оба по умолчанию)
  if [[ "${REDIS_PORT_NUMBER}" == "6379" && "${REDIS_TLS_PORT_NUMBER:-6379}" == "6379" ]]; then
    redis_conf_set port 0
  fi
  redis_conf_set tls-port       "${REDIS_TLS_PORT_NUMBER:-6379}"
  [[ -n "${REDIS_TLS_CERT_FILE:-}" ]]      && redis_conf_set tls-cert-file       "${REDIS_TLS_CERT_FILE}"
  [[ -n "${REDIS_TLS_KEY_FILE:-}"  ]]      && redis_conf_set tls-key-file        "${REDIS_TLS_KEY_FILE}"
  [[ -n "${REDIS_TLS_KEY_FILE_PASS:-}" ]]  && redis_conf_set tls-key-file-pass   "${REDIS_TLS_KEY_FILE_PASS}"
  if [[ -n "${REDIS_TLS_CA_FILE:-}" ]]; then
    redis_conf_set tls-ca-cert-file "${REDIS_TLS_CA_FILE}"
  elif [[ -n "${REDIS_TLS_CA_DIR:-}" ]]; then
    redis_conf_set tls-ca-cert-dir  "${REDIS_TLS_CA_DIR}"
  fi
  [[ -n "${REDIS_TLS_DH_PARAMS_FILE:-}" ]] && redis_conf_set tls-dh-params-file "${REDIS_TLS_DH_PARAMS_FILE}"
  [[ -n "${REDIS_TLS_AUTH_CLIENTS:-}" ]]   && redis_conf_set tls-auth-clients   "${REDIS_TLS_AUTH_CLIENTS}"
fi

# Replication / Sentinel (reuse library, если роль задана)
if [[ -n "${REDIS_REPLICATION_MODE:-}" ]]; then
  redis_configure_replication
fi

info "✓ Redis initialized (directories/permissions ready; redis.conf tuned)"
debug "Setup completed. You can now start redis-server with your entrypoint."
