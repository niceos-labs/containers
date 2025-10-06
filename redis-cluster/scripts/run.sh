#!/usr/bin/env bash
# =============================================================================
# NiceOS · Redis Cluster Runner
# File: /app/run.sh
#
# Purpose:
# This script acts as the main (PID 1) process for a Redis Cluster container.
# It performs full initialization, environment validation, Redis startup,
# readiness checks, optional cluster creation, and graceful signal handling.
#
# Workflow:
# 1) Executes the centralized NiceOS setup script:
#    prepares filesystem (directories, permissions) and modifies redis.conf.
# 2) Launches redis-server in foreground mode (no daemon).
#    Logs go to stderr for container-friendly behavior.
# 3) Waits until the local Redis node replies with PONG (readiness check).
# 4) If REDIS_CLUSTER_CREATOR=yes, waits for peers and creates the cluster.
# 5) Forwards signals (SIGTERM/SIGINT) to redis-server and exits with its code.
# =============================================================================

set -Eeuo pipefail  # Strict Bash mode:
# -E: trap ERR in functions
# -e: exit immediately on any command error
# -u: error on unset variables
# -o pipefail: fail if any command in a pipeline fails

# -----------------------------------------------------------------------------
# Load NiceOS libraries
# -----------------------------------------------------------------------------
# redis-cluster-env.sh may predefine environment variables.
# liblog.sh provides logging functions (info/warn/error/debug/success).
# libos.sh provides OS-level helpers like ensure_dir_exists.
# -----------------------------------------------------------------------------
# shellcheck disable=SC1091
[[ -r /nicesoft/niceos/scripts/redis-cluster-env.sh ]] && . /nicesoft/niceos/scripts/redis-cluster-env.sh
. /nicesoft/niceos/scripts/liblog.sh
. /nicesoft/niceos/scripts/libos.sh

# -----------------------------------------------------------------------------
# Environment variables and defaults
# -----------------------------------------------------------------------------
APP_DIR="${APP_DIR:-/app}"                                    # Root directory of the application
REDIS_CONF_FILE="${REDIS_CONF_FILE:-${APP_DIR}/etc/redis.conf}" # Redis main configuration file
REDIS_DATA_DIR="${REDIS_DATA_DIR:-${APP_DIR}/data}"           # Data directory for Redis
REDIS_TMP_DIR="${REDIS_TMP_DIR:-/app/run}"                    # Temp directory (for PID files, sockets)
REDIS_PID_FILE="${REDIS_PID_FILE:-${REDIS_TMP_DIR}/redis.pid}" # PID file location

# Port compatibility: support both REDIS_PORT_NUMBER and REDIS_PORT
REDIS_PORT_NUMBER="${REDIS_PORT_NUMBER:-${REDIS_PORT:-6379}}"

# Host advertised to other nodes; may be DNS name (e.g. r1, r2, etc.)
REDIS_HOST="${REDIS_HOST:-${HOSTNAME:-127.0.0.1}}"

# Cluster configuration flags
REDIS_CLUSTER_ENABLED="${REDIS_CLUSTER_ENABLED:-yes}"          # Enable cluster mode
REDIS_CLUSTER_CREATOR="${REDIS_CLUSTER_CREATOR:-no}"           # Mark this node as cluster creator
REDIS_CLUSTER_REPLICAS="${REDIS_CLUSTER_REPLICAS:-1}"          # Number of replicas when creating cluster

# Extra runtime flags passed directly to redis-server (string)
REDIS_EXTRA_FLAGS="${REDIS_EXTRA_FLAGS:-}"

# Node list can be comma- or space-separated
# Example: "r2:6379 r3:6379" or "r2:6379,r3:6379"
IFS=', ' read -r -a REDIS_NODES_ARR <<< "${REDIS_NODES:-}"

# -----------------------------------------------------------------------------
# Helper functions
# -----------------------------------------------------------------------------

# Wait until cluster_state:ok appears in "redis-cli cluster info"
_wait_cluster_ok() {
    # Usage: _wait_cluster_ok <timeout_seconds>
    local -r timeout="${1:-60}"
    local start now
    start="$(date +%s)"
    while true; do
        if _redis_cli_local cluster info 2>/dev/null | grep -q '^cluster_state:ok'; then
            return 0  # Cluster is healthy
        fi
        sleep 0.5
        now="$(date +%s)"
        (( now - start >= timeout )) && return 1  # Timed out
    done
}

# Mask sensitive data (like passwords) when echoing commands for logging
_safe_cmd() {
    printf '%q ' "$@" | \
    sed -E 's/(--requirepass|-a|--cluster-auth)[[:space:]]+[^ ]+/\1 ****/g'
}

# Require that a binary is available in PATH
_require_bin() {
    local -r bin="$1"
    if ! command -v "${bin}" >/dev/null 2>&1; then
        error "Required binary not found in PATH: '${bin}'"
        exit 127
    fi
}

# Require that a file exists and is readable
_require_readable() {
    local -r path="$1"
    if [[ ! -r "${path}" ]]; then
        error "Required file is not readable: '${path}'"
        exit 1
    fi
}

# Resolve local hostname (prefer REDIS_HOST, then HOSTNAME, fallback 127.0.0.1)
_resolve_local_host() {
    if [[ -n "${REDIS_HOST:-}" ]]; then
        printf '%s' "${REDIS_HOST}"
    elif [[ -n "${HOSTNAME:-}" ]]; then
        printf '%s' "${HOSTNAME}"
    else
        printf '%s' "127.0.0.1"
    fi
}

# redis-cli wrapper with host, port, and optional password
_redis_cli_hostport() {
    local -r host="$1" port="$2"; shift 2
    if [[ -n "${REDIS_PASSWORD:-}" ]]; then
        redis-cli -h "${host}" -p "${port}" -a "${REDIS_PASSWORD}" "$@"
    else
        redis-cli -h "${host}" -p "${port}" "$@"
    fi
}

# redis-cli for local instance
_redis_cli_local() {
    _redis_cli_hostport "$(_resolve_local_host)" "${REDIS_PORT_NUMBER}" "$@"
}

# Check readiness: expect "PONG" from redis-cli ping
_is_ready_hostport() {
    local -r host="$1" port="$2"
    _redis_cli_hostport "${host}" "${port}" -r 1 -t 1 ping 2>&1 | {
        if grep -q 'PONG'; then
            exit 0
        fi
        read -r line || true
        [[ -n "$line" ]] && debug "redis-cli ping ${host}:${port} => ${line}"
        exit 1
    }
}

# Check local Redis node readiness
_is_local_ready() {
    _is_ready_hostport "$(_resolve_local_host)" "${REDIS_PORT_NUMBER}"
}

# Wait until a given command succeeds or timeout expires
_wait_until() {
    # Usage: _wait_until <timeout_seconds> <command ...>
    local -r timeout="$1"; shift
    local start now
    start="$(date +%s)"
    sleep 0.3  # short grace delay before first probe
    while ! "$@"; do
        sleep 0.3
        now="$(date +%s)"
        if (( now - start >= timeout )); then
            return 1
        fi
    done
}

# Build a unique node list: self first, then peers (no duplicates, no empties)
_build_all_nodes() {
    local self="$(_resolve_local_host):${REDIS_PORT_NUMBER}"
    local -a all=()
    local seen=",${self},"
    all+=("${self}")
    for hp in "${REDIS_NODES_ARR[@]}"; do
        [[ -z "${hp}" ]] && continue
        [[ "${hp}" == "${self}" ]] && continue
        if [[ "${seen}" != *",${hp},"* ]]; then
            all+=("${hp}")
            seen+="${hp},"
        fi
    done
    printf '%s\n' "${all[@]}"
}

# Signal handlers for graceful shutdown
_term() {
    info "SIGTERM received — forwarding to redis-server (PID=${REDIS_PID})"
    kill -TERM "${REDIS_PID}" 2>/dev/null || true
}
_int() {
    info "SIGINT received — forwarding to redis-server (PID=${REDIS_PID})"
    kill -INT "${REDIS_PID}" 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# Pre-flight validation
# -----------------------------------------------------------------------------
info "Validating environment and required binaries…"
_require_bin redis-server
_require_bin redis-cli
_require_readable "${REDIS_CONF_FILE}"
ensure_dir_exists "${REDIS_DATA_DIR}"
ensure_dir_exists "${REDIS_TMP_DIR}"

# -----------------------------------------------------------------------------
# Centralized setup: filesystem preparation and redis.conf tuning
# -----------------------------------------------------------------------------
info "Running setup: /nicesoft/niceos/scripts/setup.sh"
/nicesoft/niceos/scripts/setup.sh 1>&2
success "Setup completed"

# -----------------------------------------------------------------------------
# Start redis-server in foreground mode
# -----------------------------------------------------------------------------
# We enforce:
# --daemonize no  -> stay in foreground (PID 1)
# --logfile ""    -> log to stderr instead of file
args=( "${REDIS_CONF_FILE}" --daemonize no --logfile "" )

# Add extra runtime flags from environment, if any
if [[ -n "${REDIS_EXTRA_FLAGS}" ]]; then
    IFS=' ' read -r -a _extra <<< "${REDIS_EXTRA_FLAGS}"
    if [[ "${#_extra[@]}" -gt 0 ]]; then
        args+=("${_extra[@]}")
    fi
fi

debug "redis-server command line:"
debug " $(_safe_cmd redis-server "${args[@]}")"

# Launch Redis as a background process; script remains PID 1
( exec redis-server "${args[@]}" 1>&2 ) &
REDIS_PID=$!
info "redis-server started (PID=${REDIS_PID})"

# Register signal traps
trap _term TERM
trap _int INT

# -----------------------------------------------------------------------------
# Wait for local Redis readiness (PING -> PONG)
# -----------------------------------------------------------------------------
info "Waiting for local node $(_resolve_local_host):${REDIS_PORT_NUMBER} to become ready…"
if ! _wait_until 90 _is_local_ready; then
    error "redis-server did not become ready within 90 seconds"
    kill -TERM "${REDIS_PID}" 2>/dev/null || true
    wait "${REDIS_PID}" || true
    exit 1
fi
success "Local node is ready (PING -> PONG)"

# -----------------------------------------------------------------------------
# Cluster creation and validation (only if REDIS_CLUSTER_CREATOR=yes)
# -----------------------------------------------------------------------------
_create_cluster_if_needed() {
    # Respect the cluster toggle
    is_boolean_yes "${REDIS_CLUSTER_ENABLED}" || {
        info "Cluster mode is disabled by environment"
        return 0
    }

    # Skip if already part of an active cluster
    if _redis_cli_local cluster info 2>/dev/null | grep -q '^cluster_state:ok'; then
        info "Cluster is already active according to the local node — skipping creation"
        return 0
    fi

    # Build full node list: self + peers
    mapfile -t all_nodes < <(_build_all_nodes)
    if (( ${#all_nodes[@]} < 3 )); then
        warn "Only ${#all_nodes[@]} node(s) in the list — typically too few for production; proceeding anyway"
    fi

    info "Waiting for all nodes to become ready: ${all_nodes[*]}"
    for hp in "${all_nodes[@]}"; do
        if ! _wait_until 90 _is_ready_hostport "${hp%%:*}" "${hp##*:}"; then
            error "Node '${hp}' did not become ready within 90 seconds — cannot create cluster"
            return 1
        fi
    done
    success "All nodes respond with PONG"

    # Compose redis-cli --cluster create arguments
    local -a cli_auth=()
    local -a replicas_flag=()
    [[ -n "${REDIS_PASSWORD:-}" ]] && cli_auth=(--cluster-auth "${REDIS_PASSWORD}")
    [[ -n "${REDIS_CLUSTER_REPLICAS:-}" ]] && replicas_flag=(--cluster-replicas "${REDIS_CLUSTER_REPLICAS}")

    info "Creating Redis Cluster (non-interactive)…"
    debug " $(_safe_cmd redis-cli "${cli_auth[@]}" --cluster create "${all_nodes[@]}" "${replicas_flag[@]}" --cluster-yes)"

    if ! redis-cli "${cli_auth[@]}" --cluster create "${all_nodes[@]}" "${replicas_flag[@]}" --cluster-yes 1>&2; then
        error "redis-cli --cluster create failed"
        return 1
    fi

    # Wait for stabilization
    info "Waiting for cluster_state:ok after creation…"
    if ! _wait_cluster_ok 90; then
        error "Cluster did not reach state OK within timeout — check bus connectivity and announcements"
        return 1
    fi
    success "Cluster reached state OK"

    # Final verification
    if _redis_cli_local cluster info 2>/dev/null | grep -q '^cluster_state:ok'; then
        success "Cluster created successfully and is in state OK"
        return 0
    else
        error "Cluster creation finished but cluster_state != ok — check logs"
        return 1
    fi
}

# If this node is designated as cluster creator
if is_boolean_yes "${REDIS_CLUSTER_CREATOR}"; then
    info "This node is the cluster creator (REDIS_CLUSTER_CREATOR=yes)"
    if ! _create_cluster_if_needed; then
        error "Cluster creation/verification failed — stopping redis-server"
        kill -TERM "${REDIS_PID}" 2>/dev/null || true
        wait "${REDIS_PID}" || true
        exit 1
    fi
else
    info "This node is not a cluster creator — skipping cluster creation"
fi

# -----------------------------------------------------------------------------
# Supervise redis-server lifecycle
# -----------------------------------------------------------------------------
info "Handing over lifecycle — waiting for redis-server (PID=${REDIS_PID}) to exit"
wait "${REDIS_PID}"
exit_code=$?
if [[ $exit_code -eq 0 ]]; then
    success "redis-server exited cleanly (code=0)"
else
    error "redis-server exited with error (code=${exit_code})"
fi
exit "${exit_code}"
