#!/usr/bin/env bash
# =============================================================================
#  NiceOS Redis Cluster Library — drop-in replacement for Bitnami's librediscluster.sh
#
#  Purpose
#  -------
#  Provide Redis Cluster helpers (validation, initialization, creation, DNS/IP
#  recovery) in NiceOS containers. Public API (function names/args and env var
#  semantics) remains compatible with the original script.
#
#  Design choices
#  --------------
#  • Safe under `set -euo pipefail` in the caller (we do not change shell opts).
#  • Arguments and command lines assembled via arrays (no fragile word-splitting).
#  • TLS & password are consistently propagated to redis-cli (both waits & create).
#  • Strict logging via liblog; we avoid noisy output except INFO/WARN/ERROR.
#  • IPv6 addresses are announced WITHOUT brackets in redis.conf (Redis expects raw).
#  • Cluster bus port defaults to data port + 10000 unless explicitly set.
# =============================================================================
# shellcheck disable=SC1090,SC1091,SC2155,SC2207

# --------------------------- Load NiceOS libraries (soft) ---------------------
# We source "softly": the library is source-able in different runtimes.
[ -r /nicesoft/niceos/scripts/libfile.sh ]         && . /nicesoft/niceos/scripts/libfile.sh
[ -r /nicesoft/niceos/scripts/libfs.sh ]           && . /nicesoft/niceos/scripts/libfs.sh
[ -r /nicesoft/niceos/scripts/liblog.sh ]          && . /nicesoft/niceos/scripts/liblog.sh
[ -r /nicesoft/niceos/scripts/libnet.sh ]          && . /nicesoft/niceos/scripts/libnet.sh
[ -r /nicesoft/niceos/scripts/libos.sh ]           && . /nicesoft/niceos/scripts/libos.sh
[ -r /nicesoft/niceos/scripts/libservice.sh ]      && . /nicesoft/niceos/scripts/libservice.sh
[ -r /nicesoft/niceos/scripts/libvalidations.sh ]  && . /nicesoft/niceos/scripts/libvalidations.sh
[ -r /nicesoft/niceos/scripts/libredis.sh ]        && . /nicesoft/niceos/scripts/libredis.sh

# ------------------------------ Internal helpers -----------------------------
# These helpers are private (underscore prefix). They do not change shell opts.

# Strip IPv6 square brackets if present: "[2001:db8::1]" -> "2001:db8::1"
_strip_brackets_if_v6() {
  local ip="${1:-}"
  ip="${ip#[}"
  ip="${ip%]}"
  printf '%s\n' "$ip"
}

# Return absolute path to redis-cli that matches the bundled redis
# NOTE: We prefer the embedded binary to avoid PATH ambiguity.
_redis_cli() {
  local base="${REDIS_BASE_DIR:-/app}"
  printf '%s\n' "${base}/bin/redis-cli"
}

# Compose common redis-cli flags (TLS, auth). Accepts extra args via "$@"
# Usage: mapfile -t out < <(_redis_cli_common_flags); then: "${cli}" "${out[@]}" ping
_redis_cli_common_flags() {
  local -a flags=()
  # Password: use "-a" only if defined and non-empty.
  if [[ -n "${REDIS_PASSWORD:-}" ]]; then
    flags+=("-a" "${REDIS_PASSWORD}")
  fi
  # TLS: if enabled, pass cert/key and CA (dir or file).
  if is_boolean_yes "${REDIS_TLS_ENABLED:-no}"; then
    flags+=("--tls")
    [[ -n "${REDIS_TLS_CERT_FILE:-}" ]] && flags+=("--cert"   "${REDIS_TLS_CERT_FILE}")
    [[ -n "${REDIS_TLS_KEY_FILE:-}"  ]] && flags+=("--key"    "${REDIS_TLS_KEY_FILE}")
    if   [[ -n "${REDIS_TLS_CA_FILE:-}" ]]; then
      flags+=("--cacert"   "${REDIS_TLS_CA_FILE}")
    elif [[ -n "${REDIS_TLS_CA_DIR:-}"  ]]; then
      flags+=("--cacertdir" "${REDIS_TLS_CA_DIR}")
    fi
  fi
  printf '%s\n' "${flags[@]}"
}

# Turn "host[:port]" into "host port" pair.
# • Defaults to REDIS_TLS_PORT_NUMBER if TLS is enabled, otherwise REDIS_PORT_NUMBER.
# • Strips IPv6 brackets in host component.
_to_host_and_port() {
  local input="${1:?host is required}"
  local host="${input%%:*}"
  local port="${input#*:}"
  if [[ "$host" == "$port" ]]; then
    # No colon present -> only host given. Use defaults.
    if is_boolean_yes "${REDIS_TLS_ENABLED:-no}"; then
      port="${REDIS_TLS_PORT_NUMBER:?REDIS_TLS_PORT_NUMBER is required when TLS is enabled}"
    else
      port="${REDIS_PORT_NUMBER:?REDIS_PORT_NUMBER is required}"
    fi
  fi
  host="$(_strip_brackets_if_v6 "${host}")"
  printf '%s %s\n' "${host}" "${port}"
}

# Safe DNS lookup with retries; returns a single IPv4/IPv6 (first A/AAAA)
# Uses: getent hosts (POSIX-ish) and respects both A and AAAA.
_wait_for_dns_lookup() {
  local host="${1:?host}"
  local retries="${2:-20}"
  local sleep_s="${3:-2}"
  local ip=""
  local i=0
  while (( i < retries )); do
    # Prefer 'getent hosts'; fallback to 'host' if available; else try 'getent ahosts'
    if ip="$(getent hosts "${host}" 2>/dev/null | awk '{print $1; exit}')"; then
      [[ -n "${ip}" ]] && { printf '%s\n' "$ip"; return 0; }
    elif command -v host >/dev/null 2>&1; then
      ip="$(host "${host}" 2>/dev/null | awk '/has address|IPv6 address/ {print $NF; exit}')"
      [[ -n "${ip}" ]] && { printf '%s\n' "$ip"; return 0; }
    elif ip="$(getent ahosts "${host}" 2>/dev/null | awk '!/RAW/ {print $1; exit}')"; then
      [[ -n "${ip}" ]] && { printf '%s\n' "$ip"; return 0; }
    fi
    sleep "${sleep_s}"
    ((i++))
  done
  return 1
}

# Wait until TCP port is connectable (uses bash /dev/tcp). No output; just rc.
_wait_for_tcp_port() {
  local host="${1:?host}"; local port="${2:?port}"
  local retries="${3:-24}"; local sleep_s="${4:-2}"
  local i=0
  while (( i < retries )); do
    if (echo >"/dev/tcp/${host}/${port}") >/dev/null 2>&1; then
      return 0
    fi
    sleep "${sleep_s}"
    ((i++))
  done
  return 1
}

# ------------------------------ Public API -----------------------------------

########################
# Validate settings in REDIS_* env vars.
# Globals:
#   REDIS_*
# Arguments:
#   None
# Returns:
#   Exits non-zero on validation errors.
#########################
redis_cluster_validate() {
  debug "Validating settings in REDIS_* env vars.."
  local error_code=0

  print_validation_error() { error "$1"; error_code=1; }
  empty_password_enabled_warn() {
    warn "You set ALLOW_EMPTY_PASSWORD=${ALLOW_EMPTY_PASSWORD:-}. Never use this flag in production."
  }
  empty_password_error() {
    print_validation_error "The $1 environment variable is empty or not set. Set ALLOW_EMPTY_PASSWORD=yes to allow blank passwords (development only)."
  }

  # Password policy
  if is_boolean_yes "${ALLOW_EMPTY_PASSWORD:-no}"; then
    empty_password_enabled_warn
  else
    [[ -z "${REDIS_PASSWORD:-}" ]] && empty_password_error REDIS_PASSWORD
  fi


  # Nodes list
  if [[ -z "${REDIS_NODES:-}" ]]; then
    print_validation_error "REDIS_NODES is required (comma/semicolon-separated host[:port] entries)."
  fi


  # Announce IP logic
  if ! is_boolean_yes "${REDIS_CLUSTER_DYNAMIC_IPS:-no}"; then
    [[ -z "${REDIS_CLUSTER_ANNOUNCE_IP:-}" ]] && print_validation_error "REDIS_CLUSTER_ANNOUNCE_IP is required when REDIS_CLUSTER_DYNAMIC_IPS=no."
  fi

  # Data ports
  if [[ -z "${REDIS_PORT_NUMBER:-}" ]]; then
    print_validation_error "REDIS_PORT_NUMBER cannot be empty."
  fi
  if is_boolean_yes "${REDIS_TLS_ENABLED:-no}" && [[ -z "${REDIS_TLS_PORT_NUMBER:-}" ]]; then
    print_validation_error "REDIS_TLS_PORT_NUMBER is required when TLS is enabled."
  fi

  # Creation parameters
  if is_boolean_yes "${REDIS_CLUSTER_CREATOR:-no}"; then
    [[ -z "${REDIS_CLUSTER_REPLICAS:-}" ]] && print_validation_error "REDIS_CLUSTER_REPLICAS must be provided to create the cluster."
  fi

  # Sleep before DNS lookup
  if [[ -n "${REDIS_CLUSTER_SLEEP_BEFORE_DNS_LOOKUP:-}" ]]; then
    if (( REDIS_CLUSTER_SLEEP_BEFORE_DNS_LOOKUP < 0 )); then
      print_validation_error "REDIS_CLUSTER_SLEEP_BEFORE_DNS_LOOKUP must be >= 0."
    fi
  fi

  [[ "${error_code}" -eq 0 ]] || exit "${error_code}"
}

########################
# RedisCluster-specific configuration to override the default one.
# Adds cluster-related announce values and TLS cluster flags into redis.conf.
# Globals: REDIS_*
#########################
redis_cluster_override_conf() {
  # Announce IP/hostname/endpoints
  if is_boolean_yes "${REDIS_CLUSTER_DYNAMIC_IPS:-no}"; then
    # Use current machine IP (stripped IPv6 brackets). Useful behind proxies.
    redis_conf_set cluster-announce-ip "$(_strip_brackets_if_v6 "$(get_machine_ip)")"
  else
    redis_conf_set cluster-announce-ip "$(_strip_brackets_if_v6 "${REDIS_CLUSTER_ANNOUNCE_IP}")"
  fi
  if ! is_empty_value "${REDIS_CLUSTER_ANNOUNCE_HOSTNAME:-}"; then
    redis_conf_set cluster-announce-hostname "${REDIS_CLUSTER_ANNOUNCE_HOSTNAME}"
  fi
  if ! is_empty_value "${REDIS_CLUSTER_PREFERRED_ENDPOINT_TYPE:-}"; then
    # Valid values: ip, hostname, all-interfaces; leave as provided.
    redis_conf_set cluster-preferred-endpoint-type "${REDIS_CLUSTER_PREFERRED_ENDPOINT_TYPE}"
  fi

  # TLS cluster interconnect (auth & replication via TLS)
  if is_boolean_yes "${REDIS_TLS_ENABLED:-no}"; then
    redis_conf_set tls-cluster yes
    redis_conf_set tls-replication yes
  fi

  # Announce ports (data + bus). If not provided, keep Redis defaults:
  #   data: REDIS_PORT_NUMBER or REDIS_TLS_PORT_NUMBER
  #   bus:  data + 10000 (Redis default)
  if ! is_empty_value "${REDIS_CLUSTER_ANNOUNCE_PORT:-}"; then
    redis_conf_set cluster-announce-port "${REDIS_CLUSTER_ANNOUNCE_PORT}"
  fi
  if ! is_empty_value "${REDIS_CLUSTER_ANNOUNCE_BUS_PORT:-}"; then
    redis_conf_set cluster-announce-bus-port "${REDIS_CLUSTER_ANNOUNCE_BUS_PORT}"
  else
    # Provide bus-port only if user explicitly set one — otherwise rely on Redis default (port+10000).
    :
  fi

  # Optional threading knobs (pass-through)
  [[ -n "${REDIS_IO_THREADS_DO_READS:-}" ]] && redis_conf_set io-threads-do-reads "${REDIS_IO_THREADS_DO_READS}"
  [[ -n "${REDIS_IO_THREADS:-}"          ]] && redis_conf_set io-threads          "${REDIS_IO_THREADS}"
}

########################
# Ensure Redis is initialized with base config and cluster overrides.
#########################
redis_cluster_initialize() {
  info "Initializing Redis (cluster mode)"
  redis_configure_default
  redis_cluster_override_conf
}

########################
# Create a Redis Cluster from provided nodes.
# Args:
#   $@ - array of host[:port] entries (same nodes as REDIS_NODES)
#########################
redis_cluster_create() {
  local -a nodes=("$@")
  local -a sockets=()
  local -a cli_flags
  mapfile -t cli_flags < <(_redis_cli_common_flags)

  # 1) Ensure all nodes are ready (PING==PONG)
  for node in "${nodes[@]}"; do
    local hp host port
    hp="$(_to_host_and_port "${node}")"
    read -r host port <<<"${hp}"

    # Wait for TCP first (avoids repeated CLI spawn cycling)
    if ! _wait_for_tcp_port "${host}" "${port}" 24 1; then
      error "Node ${node} is not connectable at ${host}:${port}"
      return 1
    fi

    # Then ask for PONG with consistent flags
    local -a ping_cmd=("$(_redis_cli)" -h "${host}" -p "${port}" "${cli_flags[@]}" ping)
    # NOTE: redis-cli returns "PONG" (stdout), rc=0 on success.
    local pong
    if ! pong="$("${ping_cmd[@]}" 2>/dev/null)" || [[ "${pong}" != "PONG" ]]; then
      error "Node ${node} is not ready (no PONG); command: ${ping_cmd[*]}"
      return 1
    fi
    debug "Node ${node} is up (PONG)."
  done

  # 2) Sleep before DNS lookup if requested (helps containers settle in SD)
  local sleep_before="${REDIS_CLUSTER_SLEEP_BEFORE_DNS_LOOKUP:-0}"
  if (( sleep_before > 0 )); then
    info "Waiting ${sleep_before}s before querying node IP addresses."
    sleep "${sleep_before}"
  fi

  # 3) Resolve DNS of each node (first A/AAAA), collect "ip:port" sockets
  local retries="${REDIS_CLUSTER_DNS_LOOKUP_RETRIES:-20}"
  local backoff="${REDIS_CLUSTER_DNS_LOOKUP_SLEEP:-2}"
  for node in "${nodes[@]}"; do
    local hp host port ip
    hp="$(_to_host_and_port "${node}")"
    read -r host port <<<"${hp}"
    if ! ip="$(_wait_for_dns_lookup "${host}" "${retries}" "${backoff}")"; then
      error "DNS lookup failed for ${host}"
      return 1
    fi
    sockets+=("$(_strip_brackets_if_v6 "${ip}"):${port}")
  done
  debug "Cluster sockets: ${sockets[*]}"

  # 4) Create the cluster (non-interactive)
  local -a create_cmd=("$(_redis_cli)" "${cli_flags[@]}" --cluster create)
  create_cmd+=("${sockets[@]}")
  create_cmd+=(--cluster-replicas "${REDIS_CLUSTER_REPLICAS:?REDIS_CLUSTER_REPLICAS required}" --cluster-yes)
  if is_boolean_yes "${REDIS_TLS_ENABLED:-no}"; then
    # TLS flags already included in cli_flags; no need to re-add here.
    :
  fi

  info "Creating cluster: ${create_cmd[*]}"
  if ! "${create_cmd[@]}" </dev/null; then
    warn "Cluster create returned non-zero. The cluster may already exist; trying a health check."
  fi

  # 5) Health check: "All 16384 slots covered"
  if redis_cluster_check "${sockets[0]}"; then
    success "Cluster correctly created / recovered."
  else
    warn "Cluster not yet fully covered; nodes should recover it if already initialized."
  fi
}

#########################
# Check if the cluster state is correct using `redis-cli --cluster check`.
# Param:
#   $1 - socket "host:port" to query
#########################
redis_cluster_check() {
  local socket="${1:?socket host:port required}"
  local host="${socket%%:*}"
  local port="${socket##*:}"

  local -a flags
  mapfile -t flags < <(_redis_cli_common_flags)
  local -a cmd=("$(_redis_cli)" -h "${host}" -p "${port}" "${flags[@]}" --cluster check "${socket}")

  # NOTE: We capture stdout and look for the canonical phrase.
  local out
  if ! out="$("${cmd[@]}" 2>&1)"; then
    debug "cluster check failed: ${out}"
    return 1
  fi
  [[ "${out}" == *"All 16384 slots covered"* ]]
}

#########################
# Update IPs in nodes.conf when dynamic IPs are used.
# Strategy:
#  - On first init, persist host->ip map into nodes.sh
#  - On subsequent runs, replace old IPs with new ones in nodes.conf,
#    then update nodes.sh. Replacement is scoped & idempotent.
#########################
redis_cluster_update_ips() {
  local -a nodes
  # Split by comma or semicolon into array.
  read -ra nodes <<<"$(tr ',;' ' ' <<< "${REDIS_NODES:-}")"

  ensure_dir_exists "${REDIS_DATA_DIR:?REDIS_DATA_DIR required}"

  local map_file="${REDIS_DATA_DIR}/nodes.sh"
  local nodes_conf="${REDIS_DATA_DIR}/nodes.conf"

  # Build or load associative map
  declare -A host_2_ip_array

  if [[ ! -f "${map_file}" || ! -f "${nodes_conf}" ]]; then
    # First initialization: store the map.
    info "Persisting initial host->IP map."
    local node hp host port ip
    for node in "${nodes[@]}"; do
      hp="$(_to_host_and_port "${node}")"
      read -r host port <<<"${hp}"
      if ! ip="$(_wait_for_dns_lookup "${host}" "${REDIS_DNS_RETRIES:-20}" 5)"; then
        error "DNS lookup failed for ${host}"
        return 1
      fi
      host_2_ip_array["${node}"]="${ip}"
    done
    declare -p host_2_ip_array > "${map_file}"
    return 0
  fi

  # Load existing map (safe: map variable name is fixed)
  # shellcheck source=/dev/null
  . "${map_file}"

  # Update nodes.conf by replacing old IPs with new ones (only for known nodes).
  local node old new tmp
  tmp="$(mktemp -p "${REDIS_DATA_DIR}" nodes.conf.XXXXXX)"
  cp -f "${nodes_conf}" "${tmp}"
  for node in "${nodes[@]}"; do
    local hp host port
    hp="$(_to_host_and_port "${node}")"
    read -r host port <<<"${hp}"
    if ! new="$(_wait_for_dns_lookup "${host}" "${REDIS_DNS_RETRIES:-20}" 5)"; then
      warn "DNS lookup failed for ${host}; skipping replacement for this node."
      continue
    fi
    old="${host_2_ip_array[${node}]:-}"
    if [[ -n "${old}" && "${old}" != "${new}" ]]; then
      info "Changing old IP ${old} -> ${new} for node ${node}"
      # Replace " <OLD>:" to " <NEW>:" safely; angle brackets are not used here.
      # We use '|' delimiter to avoid conflicts with '/' in IPv6.
      sed -i "s| ${old}:| ${new}:|g" "${tmp}"
    fi
    host_2_ip_array["${node}"]="${new}"
  done

  mv -f "${tmp}" "${nodes_conf}"
  declare -p host_2_ip_array > "${map_file}"
}

#########################
# Assign a port to the host if one is not set using redis defaults.
# Arg:
#   $1 - "host" or "host:port"
# Returns:
#   Echo "host port"
#########################
to_host_and_port() {
  # Kept for backward compatibility with existing callers.
  _to_host_and_port "$@"
}

# =============================================================================
# End of file
# =============================================================================
