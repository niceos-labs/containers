#!/usr/bin/env bash
# =============================================================================
#  NiceOS · Redis Setup
#
#  Purpose
#  -------
#  - Prepare filesystem (data/run dirs, ownership).
#  - Tweak redis.conf using redis_conf_set (idempotent).
#  - Apply safe dev-friendly defaults while keeping production toggles controllable
#    via environment variables.
#
#  Notes
#  -----
#  - This script does not start Redis; it only prepares config and fs state.
#  - It is safe to run multiple times (idempotent setters).
# =============================================================================
set -Eeuo pipefail

# shellcheck disable=SC1091
. /nicesoft/niceos/scripts/redis-cluster-env.sh
. /nicesoft/niceos/scripts/liblog.sh
. /nicesoft/niceos/scripts/libos.sh
. /nicesoft/niceos/scripts/libredis.sh

# --------------------------- sanity & paths ----------------------------------
: "${REDIS_CONF_FILE:?REDIS_CONF_FILE is required}"
: "${REDIS_DATA_DIR:?REDIS_DATA_DIR is required}"

REDIS_PID_FILE="${REDIS_PID_FILE:-${REDIS_TMP_DIR:-/app/run}/redis.pid}"
REDIS_PORT_NUMBER="${REDIS_PORT_NUMBER:-${REDIS_PORT:-6379}}"

# ------------------------------ filesystem -----------------------------------
info "Ensuring Redis directories exist and are writable"
ensure_dir_exists "${REDIS_DATA_DIR}"
ensure_dir_exists "${REDIS_TMP_DIR:-/app/run}"

# Drop privileges target (if needed)
REDIS_DAEMON_USER="${REDIS_DAEMON_USER:-app}"
if am_i_root; then
  chown -R "${REDIS_DAEMON_USER}:${REDIS_DAEMON_USER}" "${REDIS_DATA_DIR}" "${REDIS_TMP_DIR:-/app/run}"
fi

# ---------------------------- base config ------------------------------------
# Networking: protected-mode & bind (dev-friendly overrides)
if is_boolean_yes "${ALLOW_EMPTY_PASSWORD:-no}"; then
  warn "ALLOW_EMPTY_PASSWORD=${ALLOW_EMPTY_PASSWORD} — this is unsafe in production."
  redis_conf_set protected-mode no
fi

if is_boolean_yes "${REDIS_ALLOW_REMOTE_CONNECTIONS:-yes}"; then
  # Allow IPv4/IPv6 binds by default (container use-case)
  redis_conf_set bind "0.0.0.0 ::"
fi

# Port / dir / pidfile
redis_conf_set port    "${REDIS_PORT_NUMBER}"
redis_conf_set dir     "${REDIS_DATA_DIR}"
redis_conf_set pidfile "${REDIS_PID_FILE}"

# Daemon / logging
# - Keep daemonize 'yes' in file (default), but runtime wrapper will pass --daemonize no.
# - Force no logfile so Redis writes to stdout (then wrapper redirects to stderr).
redis_conf_set daemonize yes
redis_conf_set logfile   ""

# Auth
if [[ -n "${REDIS_PASSWORD:-}" ]]; then
  redis_conf_set requirepass   "${REDIS_PASSWORD}"
  redis_conf_set masterauth    "${REDIS_PASSWORD}"
fi

# Persistence toggles
if is_boolean_yes "${REDIS_RDB_POLICY_DISABLED:-no}"; then
  redis_conf_set save ""
fi

if is_boolean_yes "${REDIS_AOF_ENABLED:-no}"; then
  redis_conf_set appendonly yes
  # Optional AOF settings (appendfsync everysec is a practical default)
  redis_conf_set appendfsync everysec
else
  redis_conf_set appendonly no
fi

# Cluster mode (enabled only if requested)
if is_boolean_yes "${REDIS_CLUSTER_ENABLED:-yes}"; then
  redis_conf_set cluster-enabled yes
  redis_conf_set cluster-config-file "${REDIS_CLUSTER_NODES_FILE:-${REDIS_DATA_DIR}/nodes.conf}"
  redis_conf_set cluster-node-timeout "${REDIS_CLUSTER_NODE_TIMEOUT_MS:-5000}"
else
  redis_conf_set cluster-enabled no
fi

# TLS (optional – only touch if explicitly enabled)
if is_boolean_yes "${REDIS_TLS_ENABLED:-no}"; then
  redis_conf_set tls-port        "${REDIS_TLS_PORT_NUMBER:-6379}"
  redis_conf_set port            "0"
  # Paths must be provided by env
  redis_conf_set tls-cert-file   "${REDIS_TLS_CERT_FILE:?REDIS_TLS_CERT_FILE required for TLS}"
  redis_conf_set tls-key-file    "${REDIS_TLS_KEY_FILE:?REDIS_TLS_KEY_FILE required for TLS}"
  redis_conf_set tls-ca-cert-file "${REDIS_TLS_CA_FILE:?REDIS_TLS_CA_FILE required for TLS}"
fi

success "setup.sh finished: filesystem prepared and redis.conf updated"
