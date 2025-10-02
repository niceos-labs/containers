#  NiceOS · Redis Environment (adapted to system redis layout)
#  File: redis-env.sh
#
#  Copyright (c) 2025, NiceSOFT.
#  All rights reserved. Non-free software.
#
#  This variant replaces NiceOS canonical paths with the real-system
#  redis package layout (e.g., /etc/redis.conf, /usr/bin/*, /var/lib/redis).
#
#  Precedence (highest → lowest)
#  -----------------------------
#  1) Custom env vars defined AFTER the defaults below (you may append edits).
#  2) Constants in this file (e.g., NICEOS_ROOT_DIR) when they have no defaults.
#  3) External files via *_FILE (e.g., REDIS_PASSWORD_FILE) — value is file content.
#  4) Already-exported environment (e.g., from Docker, systemd, user shells).
#
# =============================================================================
# shellcheck disable=SC1090,SC1091

# ---------- Logging ----------
. /nicesoft/niceos/scripts/liblog.sh || true
export NICEOS_MODULE="${NICEOS_MODULE:-redis}"
export MODULE="${MODULE:-redis}"

export NICEOS_ROOT_DIR="${NICEOS_ROOT_DIR:-/}"
export NICEOS_VOLUME_DIR="${NICEOS_VOLUME_DIR:-/var/lib}"
export BITNAMI_ROOT_DIR="${BITNAMI_ROOT_DIR:-$NICEOS_ROOT_DIR}"
export BITNAMI_VOLUME_DIR="${BITNAMI_VOLUME_DIR:-$NICEOS_VOLUME_DIR}"

# Verbosity
export NICEOS_DEBUG="${NICEOS_DEBUG:-${BITNAMI_DEBUG:-false}}"
export BITNAMI_DEBUG="$NICEOS_DEBUG"

# ---------- *_FILE secret loader (с trim CR/LF) ----------
_redis__read_file_var() {
  # $1=path -> echo value w/o trailing CR/LF
  local f="$1" v
  v="$(tr -d '\r' < "$f" 2>/dev/null || true)"
  v="${v%$'\n'}"
  printf '%s' "$v"
}

redis_env_vars=(
  REDIS_DATA_DIR
  REDIS_OVERRIDES_FILE
  REDIS_DISABLE_COMMANDS
  REDIS_DATABASE
  REDIS_AOF_ENABLED
  REDIS_RDB_POLICY
  REDIS_RDB_POLICY_DISABLED
  REDIS_MASTER_HOST
  REDIS_MASTER_PORT_NUMBER
  REDIS_PORT_NUMBER
  REDIS_ALLOW_REMOTE_CONNECTIONS
  REDIS_REPLICATION_MODE
  REDIS_REPLICA_IP
  REDIS_REPLICA_PORT
  REDIS_EXTRA_FLAGS
  ALLOW_EMPTY_PASSWORD
  REDIS_PASSWORD
  REDIS_MASTER_PASSWORD
  REDIS_ACLFILE
  REDIS_IO_THREADS_DO_READS
  REDIS_IO_THREADS
  REDIS_TLS_ENABLED
  REDIS_TLS_PORT_NUMBER
  REDIS_TLS_CERT_FILE
  REDIS_TLS_CA_DIR
  REDIS_TLS_KEY_FILE
  REDIS_TLS_KEY_FILE_PASS
  REDIS_TLS_CA_FILE
  REDIS_TLS_DH_PARAMS_FILE
  REDIS_TLS_AUTH_CLIENTS
  REDIS_SENTINEL_MASTER_NAME
  REDIS_SENTINEL_HOST
  REDIS_SENTINEL_PORT_NUMBER
  REDIS_TLS_PORT
)
for env_var in "${redis_env_vars[@]}"; do
  file_env_var="${env_var}_FILE"
  if [[ -n "${!file_env_var:-}" ]]; then
    if [[ -r "${!file_env_var}" ]]; then
      export "$env_var"="$(_redis__read_file_var "${!file_env_var}")"
      unset "$file_env_var"
      debug "redis-env: loaded ${env_var} from file"
    else
      warn "redis-env: skipping ${env_var}; '${!file_env_var}' is not readable"
    fi
  fi
done
unset redis_env_vars file_env_var env_var

export REDIS_BASE_DIR="${REDIS_BASE_DIR:-/app}"
export REDIS_BIN_DIR="${REDIS_BIN_DIR:-/usr/bin}"
export PATH="${REDIS_BIN_DIR}:${NICEOS_ROOT_DIR}/common/bin:${PATH}"

export REDIS_CONF_DIR="${REDIS_CONF_DIR:-${REDIS_BASE_DIR}/etc}"
export REDIS_DEFAULT_CONF_DIR="${REDIS_DEFAULT_CONF_DIR:-${REDIS_BASE_DIR}/etc.default}"
export REDIS_MOUNTED_CONF_DIR="${REDIS_MOUNTED_CONF_DIR:-${REDIS_BASE_DIR}/mounted-etc}"

export REDIS_DATA_DIR="${REDIS_DATA_DIR:-${REDIS_BASE_DIR}/data}"
export REDIS_LOG_DIR="${REDIS_LOG_DIR:-${REDIS_BASE_DIR}/logs}"
export REDIS_TMP_DIR="${REDIS_TMP_DIR:-${REDIS_BASE_DIR}/run}"

export REDIS_CONF_FILE="${REDIS_CONF_FILE:-${REDIS_CONF_DIR}/redis.conf}"
export REDIS_LOG_FILE="${REDIS_LOG_FILE:-${REDIS_LOG_DIR}/redis.log}"
export REDIS_PID_FILE="${REDIS_PID_FILE:-${REDIS_TMP_DIR}/redis.pid}"

# ---------- Users & groups ----------
export REDIS_DAEMON_USER="${REDIS_DAEMON_USER:-app}"
export REDIS_DAEMON_GROUP="${REDIS_DAEMON_GROUP:-app}"

# ---------- Core Redis settings ----------
export REDIS_DISABLE_COMMANDS="${REDIS_DISABLE_COMMANDS:-}"   # e.g. "FLUSHALL,FLUSHDB,CONFIG"
export REDIS_DATABASE="${REDIS_DATABASE:-redis}"
export REDIS_AOF_ENABLED="${REDIS_AOF_ENABLED:-yes}"
export REDIS_RDB_POLICY="${REDIS_RDB_POLICY:-}"
export REDIS_RDB_POLICY_DISABLED="${REDIS_RDB_POLICY_DISABLED:-no}"

export REDIS_MASTER_HOST="${REDIS_MASTER_HOST:-}"
export REDIS_MASTER_PORT_NUMBER="${REDIS_MASTER_PORT_NUMBER:-6379}"

export REDIS_DEFAULT_PORT_NUMBER="6379"
export REDIS_PORT_NUMBER="${REDIS_PORT_NUMBER:-$REDIS_DEFAULT_PORT_NUMBER}"
export REDIS_ALLOW_REMOTE_CONNECTIONS="${REDIS_ALLOW_REMOTE_CONNECTIONS:-yes}"

export REDIS_REPLICATION_MODE="${REDIS_REPLICATION_MODE:-}"   # master|replica|slave
export REDIS_REPLICA_IP="${REDIS_REPLICA_IP:-}"
export REDIS_REPLICA_PORT="${REDIS_REPLICA_PORT:-}"

export REDIS_EXTRA_FLAGS="${REDIS_EXTRA_FLAGS:-}"

# Authentication
export ALLOW_EMPTY_PASSWORD="${ALLOW_EMPTY_PASSWORD:-no}"
export REDIS_PASSWORD="${REDIS_PASSWORD:-}"
export REDIS_MASTER_PASSWORD="${REDIS_MASTER_PASSWORD:-}"
export REDIS_ACLFILE="${REDIS_ACLFILE:-}"

# Performance
export REDIS_IO_THREADS_DO_READS="${REDIS_IO_THREADS_DO_READS:-}"
export REDIS_IO_THREADS="${REDIS_IO_THREADS:-}"

# ---------- TLS ----------
export REDIS_TLS_ENABLED="${REDIS_TLS_ENABLED:-no}"
REDIS_TLS_PORT_NUMBER="${REDIS_TLS_PORT_NUMBER:-"${REDIS_TLS_PORT:-}"}"
export REDIS_TLS_PORT_NUMBER="${REDIS_TLS_PORT_NUMBER:-6379}"

export REDIS_TLS_CERT_FILE="${REDIS_TLS_CERT_FILE:-}"
export REDIS_TLS_KEY_FILE="${REDIS_TLS_KEY_FILE:-}"
export REDIS_TLS_KEY_FILE_PASS="${REDIS_TLS_KEY_FILE_PASS:-}"
export REDIS_TLS_CA_FILE="${REDIS_TLS_CA_FILE:-}"
export REDIS_TLS_CA_DIR="${REDIS_TLS_CA_DIR:-}"
export REDIS_TLS_DH_PARAMS_FILE="${REDIS_TLS_DH_PARAMS_FILE:-}"
export REDIS_TLS_AUTH_CLIENTS="${REDIS_TLS_AUTH_CLIENTS:-yes}"

# ---------- Sentinel ----------
export REDIS_SENTINEL_MASTER_NAME="${REDIS_SENTINEL_MASTER_NAME:-}"
export REDIS_SENTINEL_HOST="${REDIS_SENTINEL_HOST:-}"
export REDIS_SENTINEL_PORT_NUMBER="${REDIS_SENTINEL_PORT_NUMBER:-26379}"

# ---------- Notes ----------
