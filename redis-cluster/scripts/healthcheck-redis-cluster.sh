#!/usr/bin/env bash
# Robust Redis/Redis-Cluster healthcheck
# Works with: non-TLS, TLS (server-auth), mutual-TLS (client cert/key),
# password or no password, optional ACL user, cluster on/off.

set -euo pipefail

CLI="/usr/bin/redis-cli"

# --- Effective host/port detection -------------------------------------------
HOST="${REDIS_HOST:-${HOSTNAME:-127.0.0.1}}"

# If TLS is enabled, prefer TLS port; otherwise data port.
TLS_ENABLED="${REDIS_TLS_ENABLED:-no}"
if [[ "${TLS_ENABLED}" =~ ^(yes|true|on|1)$ ]]; then
  PORT="${REDIS_TLS_PORT_NUMBER:-6379}"
else
  PORT="${REDIS_PORT_NUMBER:-6379}"
fi

# Allow overrides for HC timing via env (optional)
HC_TIMEOUT="${HC_TIMEOUT:-1}"      # seconds for redis-cli -t
HC_RETRIES="${HC_RETRIES:-1}"      # -r count
HC_CLUSTER_CHECK="${HC_CLUSTER_CHECK:-auto}"  # auto|on|off

# --- Build redis-cli args safely ---------------------------------------------
args=(-h "${HOST}" -p "${PORT}" -t "${HC_TIMEOUT}" -r "${HC_RETRIES}")

# Password (global requirepass or ACL pass). Masking происходит на уровне журналирования runner-а.
if [[ -n "${REDIS_PASSWORD:-}" ]]; then
  args+=(-a "${REDIS_PASSWORD}")
fi

# ACL user (optional). If set, redis-cli will use it with the provided password.
if [[ -n "${REDIS_ACL_USERNAME:-}" ]]; then
  args+=(--user "${REDIS_ACL_USERNAME}")
fi

# TLS flags
if [[ "${TLS_ENABLED}" =~ ^(yes|true|on|1)$ ]]; then
  args+=(--tls)
  # Server authentication: pick either CA file or CA dir
  if [[ -n "${REDIS_TLS_CA_FILE:-}" ]]; then
    args+=(--cacert "${REDIS_TLS_CA_FILE}")
  elif [[ -n "${REDIS_TLS_CA_DIR:-}" ]]; then
    args+=(--cacertdir "${REDIS_TLS_CA_DIR}")
  fi
  # Mutual TLS (optional)
  [[ -n "${REDIS_TLS_CERT_FILE:-}" ]] && args+=(--cert "${REDIS_TLS_CERT_FILE}")
  [[ -n "${REDIS_TLS_KEY_FILE:-}"  ]] && args+=(--key  "${REDIS_TLS_KEY_FILE}")
fi

# --- 1) Liveness: PING -> PONG -----------------------------------------------
if ! out="$("${CLI}" "${args[@]}" ping 2>&1)"; then
  echo "PING failed: ${out}" >&2
  exit 1
fi
if [[ "${out}" != "PONG" ]]; then
  echo "Unexpected PING response: ${out}" >&2
  exit 1
fi

# --- 2) Cluster readiness (optional) -----------------------------------------
# auto: check only if REDIS_CLUSTER_ENABLED=yes|true|on|1 (default).
should_check_cluster="no"
case "${HC_CLUSTER_CHECK}" in
  on|ON|true|TRUE|1) should_check_cluster="yes" ;;
  off|OFF|false|FALSE|0) should_check_cluster="no" ;;
  auto|AUTO|"")
    if [[ "${REDIS_CLUSTER_ENABLED:-yes}" =~ ^(yes|true|on|1)$ ]]; then
      should_check_cluster="yes"
    fi
    ;;
  *) should_check_cluster="no" ;;
esac

if [[ "${should_check_cluster}" == "yes" ]]; then
  if ! cinfo="$("${CLI}" "${args[@]}" cluster info 2>/dev/null)"; then
    echo "cluster info failed" >&2
    exit 1
  fi
  if ! grep -q '^cluster_state:ok' <<<"${cinfo}"; then
    echo "cluster_state not OK" >&2
    exit 1
  fi
fi

exit 0
