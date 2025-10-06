#!/usr/bin/env bash
# =============================================================================
#  NiceOS Redis-Cluster Environment — drop-in replacement for Bitnami's
#  redis-cluster-env.sh (same env var names & semantics, /app-only paths).
#
#  Philosophy
#  ----------
#  - "Environment contract" only: declare sane defaults and map *_FILE → VAR.
#  - Do NOT mutate shell options; caller may be in `set -euo pipefail`.
#  - Keep Bitnami variable names to remain drop-in compatible.
#  - Enforce a strict "/app" sandbox for all runtime paths.
# =============================================================================
# shellcheck disable=SC1090,SC1091,SC2155

# --------------------------- Logging bootstrap --------------------------------
# Prefer NiceOS logger if present; otherwise provide tiny fallbacks.
if [[ -r /nicesoft/niceos/scripts/liblog.sh ]]; then
  . /nicesoft/niceos/scripts/liblog.sh
  # Set module name for liblog pretty prefixes (NiceOS convention).
  export NICEOS_MODULE="${NICEOS_MODULE:-redis-cluster}"
else
  warn()    { printf 'WARN: %s\n' "$*"; }
  info()    { printf '%s\n' "$*"; }
  error()   { printf 'ERROR: %s\n' "$*"; }
  debug()   { :; }     # no-op when liblog isn't available
  success() { printf 'OK: %s\n' "$*"; }
fi

# Keep Bitnami debug switch wired to NiceOS one.
export NICEOS_DEBUG="${NICEOS_DEBUG:-false}"
export BITNAMI_DEBUG="${BITNAMI_DEBUG:-${NICEOS_DEBUG}}"

# --------------------------- Constants (layout) -------------------------------
# Strong policy: ALL Redis paths must live under /app.
# NOTE: NICEOS_ROOT_DIR is used only for auxiliary tools (if any).
export NICEOS_ROOT_DIR="${NICEOS_ROOT_DIR:-/nicesoft/niceos}"
export NICEOS_APP_DIR="${NICEOS_APP_DIR:-/app}"

# Bitnami compatibility knobs — we keep them but "park" volumes under /app.
# This preserves drop-in semantics without escaping the app sandbox.
export BITNAMI_ROOT_DIR="${BITNAMI_ROOT_DIR:-${NICEOS_APP_DIR}}"
export BITNAMI_VOLUME_DIR="${BITNAMI_VOLUME_DIR:-${NICEOS_APP_DIR}/bitnami}"

# -------------------- Support *_FILE secret-style environment -----------------
# For each VAR in the list: if VAR_FILE is set and readable, export VAR
# with the file contents. This mirrors Bitnami's pattern and Docker secrets.
# IMPORTANT: We do NOT include path variables here to avoid overriding
# filesystem layout by accident.
redis_cluster_env_vars=(
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
  REDIS_CLUSTER_CREATOR
  REDIS_CLUSTER_REPLICAS
  REDIS_CLUSTER_DYNAMIC_IPS
  REDIS_CLUSTER_ANNOUNCE_IP
  REDIS_CLUSTER_ANNOUNCE_PORT
  REDIS_CLUSTER_ANNOUNCE_BUS_PORT
  REDIS_DNS_RETRIES
  REDIS_NODES
  REDIS_CLUSTER_SLEEP_BEFORE_DNS_LOOKUP
  REDIS_CLUSTER_DNS_LOOKUP_RETRIES
  REDIS_CLUSTER_DNS_LOOKUP_SLEEP
  REDIS_CLUSTER_ANNOUNCE_HOSTNAME
  REDIS_CLUSTER_PREFERRED_ENDPOINT_TYPE
  # Historical alias sometimes seen in configs:
  REDIS_TLS_PORT
)
for env_var in "${redis_cluster_env_vars[@]}"; do
  file_env_var="${env_var}_FILE"
  if [[ -n "${!file_env_var:-}" ]]; then
    if [[ -r "${!file_env_var}" ]]; then
      # Read file content without trailing newline quirks.
      export "${env_var}=$(< "${!file_env_var}")"
      unset "${file_env_var}"
      debug "Loaded ${env_var} from ${!file_env_var}"
    else
      warn "Skipping '${env_var}': '${!file_env_var}' is not readable."
    fi
  fi
done
unset redis_cluster_env_vars file_env_var

# ------------------------------- PATH & Binaries ------------------------------
# Binaries are strictly in /usr/bin by policy.
export REDIS_BASE_DIR="${REDIS_BASE_DIR:-${NICEOS_APP_DIR}}"
export REDIS_BIN_DIR="/usr/bin"
export PATH="/usr/bin:${NICEOS_ROOT_DIR}/common/bin:${PATH}"
if [[ ! -x "/usr/bin/redis-server" || ! -x "/usr/bin/redis-cli" ]]; then
  warn "Redis binaries not found in /usr/bin. Ensure the redis package is installed."
fi
# ------------------------------- Core paths -----------------------------------
# All under /app by policy.
export REDIS_CONF_DIR="${REDIS_CONF_DIR:-${REDIS_BASE_DIR}/etc}"
export REDIS_DEFAULT_CONF_DIR="${REDIS_DEFAULT_CONF_DIR:-${REDIS_BASE_DIR}/etc.default}"
export REDIS_MOUNTED_CONF_DIR="${REDIS_MOUNTED_CONF_DIR:-${REDIS_BASE_DIR}/mounted-etc}"

export REDIS_DATA_DIR="${REDIS_DATA_DIR:-${REDIS_BASE_DIR}/data}"
export REDIS_LOG_DIR="${REDIS_LOG_DIR:-${REDIS_BASE_DIR}/logs}"
export REDIS_TMP_DIR="${REDIS_TMP_DIR:-${REDIS_BASE_DIR}/run}"

export REDIS_CONF_FILE="${REDIS_CONF_FILE:-${REDIS_CONF_DIR}/redis.conf}"
export REDIS_LOG_FILE="${REDIS_LOG_FILE:-${REDIS_LOG_DIR}/redis.log}"
export REDIS_PID_FILE="${REDIS_PID_FILE:-${REDIS_TMP_DIR}/redis.pid}"

# ------------------------------- System users ---------------------------------
# Containers usually run as non-root (uid=10001:10001 → "app"), keep it explicit.
export REDIS_DAEMON_USER="${REDIS_DAEMON_USER:-app}"
export REDIS_DAEMON_GROUP="${REDIS_DAEMON_GROUP:-app}"

# ------------------------------- Redis toggles --------------------------------
# Most defaults mirror Bitnami images while staying safe by design.
export REDIS_DISABLE_COMMANDS="${REDIS_DISABLE_COMMANDS:-}"        # e.g. "FLUSHDB,FLUSHALL"
export REDIS_DATABASE="${REDIS_DATABASE:-redis}"
export REDIS_AOF_ENABLED="${REDIS_AOF_ENABLED:-yes}"               # AOF on by default (safer durability)
export REDIS_RDB_POLICY="${REDIS_RDB_POLICY:-}"                    # e.g. "900#1 300#10 60#10000"
export REDIS_RDB_POLICY_DISABLED="${REDIS_RDB_POLICY_DISABLED:-no}"

export REDIS_MASTER_HOST="${REDIS_MASTER_HOST:-}"
export REDIS_MASTER_PORT_NUMBER="${REDIS_MASTER_PORT_NUMBER:-6379}"

# Base port defaults (data port). Build-time default is 6379; runtime may override.
export REDIS_DEFAULT_PORT_NUMBER="6379"
export REDIS_PORT_NUMBER="${REDIS_PORT_NUMBER:-${REDIS_DEFAULT_PORT_NUMBER}}"

# Allow remote connections (bind 0.0.0.0 ::) — keep Bitnami default "yes".
export REDIS_ALLOW_REMOTE_CONNECTIONS="${REDIS_ALLOW_REMOTE_CONNECTIONS:-yes}"

# Replication knobs
export REDIS_REPLICATION_MODE="${REDIS_REPLICATION_MODE:-}"        # "master" | "replica"
export REDIS_REPLICA_IP="${REDIS_REPLICA_IP:-}"
export REDIS_REPLICA_PORT="${REDIS_REPLICA_PORT:-}"

# Extra flags passed to redis-server (string, space-separated)
export REDIS_EXTRA_FLAGS="${REDIS_EXTRA_FLAGS:-}"

# Password policy
export ALLOW_EMPTY_PASSWORD="${ALLOW_EMPTY_PASSWORD:-no}"          # "yes" only for development
export REDIS_PASSWORD="${REDIS_PASSWORD:-}"                        # requirepass
export REDIS_MASTER_PASSWORD="${REDIS_MASTER_PASSWORD:-}"          # masterauth (for replicas)
export REDIS_ACLFILE="${REDIS_ACLFILE:-}"

# IO Threads (pass-through)
export REDIS_IO_THREADS_DO_READS="${REDIS_IO_THREADS_DO_READS:-}"
export REDIS_IO_THREADS="${REDIS_IO_THREADS:-}"

# ---------------------------------- TLS ---------------------------------------
# TLS master switch
export REDIS_TLS_ENABLED="${REDIS_TLS_ENABLED:-no}"

# Historically, some configs use REDIS_TLS_PORT; if set, it wins as the initial
# value. Then we fall back to REDIS_TLS_PORT_NUMBER (if already provided), and
# finally to 6379.
_tls_port_seed="${REDIS_TLS_PORT:-${REDIS_TLS_PORT_NUMBER:-}}"
export REDIS_TLS_PORT_NUMBER="${_tls_port_seed:-6379}"
unset _tls_port_seed

# TLS file paths (optional; validated by libredis/librediscluster at runtime)
export REDIS_TLS_CERT_FILE="${REDIS_TLS_CERT_FILE:-}"
export REDIS_TLS_KEY_FILE="${REDIS_TLS_KEY_FILE:-}"
export REDIS_TLS_KEY_FILE_PASS="${REDIS_TLS_KEY_FILE_PASS:-}"
export REDIS_TLS_CA_FILE="${REDIS_TLS_CA_FILE:-}"
export REDIS_TLS_CA_DIR="${REDIS_TLS_CA_DIR:-}"
export REDIS_TLS_DH_PARAMS_FILE="${REDIS_TLS_DH_PARAMS_FILE:-}"
export REDIS_TLS_AUTH_CLIENTS="${REDIS_TLS_AUTH_CLIENTS:-yes}"     # "yes" to require client certs

# ------------------------------ Cluster settings ------------------------------
# Creator toggles
export REDIS_CLUSTER_CREATOR="${REDIS_CLUSTER_CREATOR:-no}"
export REDIS_CLUSTER_REPLICAS="${REDIS_CLUSTER_REPLICAS:-1}"

# IP announcement strategy
export REDIS_CLUSTER_DYNAMIC_IPS="${REDIS_CLUSTER_DYNAMIC_IPS:-yes}"  # "yes" to use current machine IP
export REDIS_CLUSTER_ANNOUNCE_IP="${REDIS_CLUSTER_ANNOUNCE_IP:-}"     # used when DYNAMIC_IPS="no"
export REDIS_CLUSTER_ANNOUNCE_PORT="${REDIS_CLUSTER_ANNOUNCE_PORT:-}" # optional override
export REDIS_CLUSTER_ANNOUNCE_BUS_PORT="${REDIS_CLUSTER_ANNOUNCE_BUS_PORT:-}" # optional override

# DNS & node list
export REDIS_DNS_RETRIES="${REDIS_DNS_RETRIES:-120}"              # generic DNS retries for various ops
export REDIS_NODES="${REDIS_NODES:-}"                             # "host[:port],host[:port];..."
export REDIS_CLUSTER_SLEEP_BEFORE_DNS_LOOKUP="${REDIS_CLUSTER_SLEEP_BEFORE_DNS_LOOKUP:-0}"
export REDIS_CLUSTER_DNS_LOOKUP_RETRIES="${REDIS_CLUSTER_DNS_LOOKUP_RETRIES:-1}"
export REDIS_CLUSTER_DNS_LOOKUP_SLEEP="${REDIS_CLUSTER_DNS_LOOKUP_SLEEP:-1}"

# Endpoint presentation
export REDIS_CLUSTER_ANNOUNCE_HOSTNAME="${REDIS_CLUSTER_ANNOUNCE_HOSTNAME:-}"
export REDIS_CLUSTER_PREFERRED_ENDPOINT_TYPE="${REDIS_CLUSTER_PREFERRED_ENDPOINT_TYPE:-ip}" # ip|hostname|all-interfaces

# ------------------------------ Final notes -----------------------------------
# At this point:
#  - All paths point under /app (policy).
#  - *_FILE secrets are loaded.
#  - TLS variables honor legacy REDIS_TLS_PORT as a seed.
#
# This file intentionally avoids creating directories or touching the filesystem.
# The entrypoint/libredis will ensure dir creation and permissions during init.
#
# Custom environment variables may be defined below without breaking anything.
