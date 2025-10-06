#!/usr/bin/env bash
# =============================================================================
#  NiceOS Redis Library
#  File: libredis.sh
#
#  Purpose
#  -------
#  Focused helpers for configuring and managing Redis under NiceOS:
#    • read/write redis.conf
#    • query Redis version
#    • check/stop a running Redis
#    • validate REDIS_* environment
#    • configure replication and sane defaults
#
#  Design
#  ------
#  - Safe to `source` under `set -u -e -o pipefail` (no option changes here).
#  - Avoid duplication: relies on NiceOS libs only.
#  - Backward-compatible function names and I/O contracts.
#
#  Conventions
#  -----------
#  - All external commands are quoted; awk/grep run with LC_ALL=C.
#  - Functions do not produce noisy output unless using liblog.
#  - redis_conf_get returns ONLY the first value token (historical behavior).
#  - "save" rules append lines by design (preserves existing behavior).
# =============================================================================
# shellcheck disable=SC1091

# --------------------------- Load NiceOS libraries ----------------------------
. /nicesoft/niceos/scripts/libfile.sh          # replace_in_file/remove_in_file
. /nicesoft/niceos/scripts/liblog.sh           # info/warn/error/debug/trace, indent
. /nicesoft/niceos/scripts/libnet.sh           # wait-for-port / wait_for_port
. /nicesoft/niceos/scripts/libos.sh            # am_i_root/run_as_user
. /nicesoft/niceos/scripts/libservice.sh       # get_pid_from_file/is_service_running
. /nicesoft/niceos/scripts/libvalidations.sh   # is_boolean_yes, validate_port, is_empty_value, …
. /nicesoft/niceos/scripts/libfs.sh            # ensure_dir_exists

# ------------------------------- Internals -----------------------------------
# NOTE: Keep internal helpers "private" by underscore prefix; public API intact.

# Resolve the primary redis.conf path.
# Honors $REDIS_CONF_FILE if provided; otherwise defaults to ${REDIS_BASE_DIR}/etc/redis.conf.
_redis_conf_path() {
    # Using parameter expansion only; do not set options here to remain "source"-safe.
    local conf="${REDIS_CONF_FILE:-}"
    if [[ -z "${conf}" ]]; then
        conf="${REDIS_BASE_DIR}/etc/redis.conf"
    fi
    printf '%s\n' "${conf}"
}

# Quick guard for required env pieces; logs but does not exit (library may be
# sourced early). Callers that need hard guarantees should validate explicitly.
_require_env_soft() {
    local -a missing=()
    [[ -z "${REDIS_BASE_DIR:-}" ]] && missing+=("REDIS_BASE_DIR")
    if ((${#missing[@]} > 0)); then
        warn "Some expected environment variables are not set yet: ${missing[*]}"
    fi
}

_strip_brackets_if_v6() { local ip="${1:-}"; ip="${ip#[}"; ip="${ip%]}"; printf '%s\n' "$ip"; }

_escape_ere() {
  local s="${1:-}"
  s="${s//\\/\\\\}"; s="${s//./\\.}"; s="${s//+/\\+}"; s="${s//\*/\\*}"
  s="${s//\?/\\?}";  s="${s//[/\\[}";  s="${s//^/\\^}";  s="${s//]/\\]}"
  s="${s//\$/\\$}";  s="${s//(/\\(}";  s="${s//)/\\)}";  s="${s//\{/\\{}"
  s="${s//\}/\\}}";  s="${s//=\\/=}";  s="${s//!/\\!}";  s="${s//</\\<}"
  s="${s//>/\\>}";   s="${s//|/\\|}";  s="${s//:/\\:}";  printf '%s\n' "$s"
}

wait_for_tcp_port() {
  local host="${1:?missing host}" port="${2:?missing port}" retries="${3:-24}" sleep_s="${4:-2}"
  _tcp_probe(){ (echo >"/dev/tcp/${host}/${port}") >/dev/null 2>&1; }
  retry_while "_tcp_probe" "$retries" "$sleep_s" || { error "wait_for_tcp_port: cannot connect to ${host}:${port}"; return 1; }
}

# Ensure locale-neutral, faster grep/awk.
_GREP() { LC_ALL=C grep "$@"; }
_EGREP(){ LC_ALL=C grep -E "$@"; }
_AWK()  { LC_ALL=C awk "$@"; }

_require_env_soft

# -------------------------------- Functions ----------------------------------

########################
# Retrieve a configuration setting value (first value token)
# Globals:
#   REDIS_BASE_DIR, REDIS_CONF_FILE (optional)
# Arguments:
#   $1 - key
#   $2 - conf file (optional; defaults to resolved redis.conf)
# Returns:
#   Prints first value token to stdout if the key exists (non-commented line)
#########################
redis_conf_get() {
  local -r raw_key="${1:?missing key}"
  local -r key="$(_escape_ere "${raw_key}")"
  local -r conf_file="${2:-"$(_redis_conf_path)"}"
  [[ -f "$conf_file" ]] || return 0
  if _EGREP -q "^[[:space:]]*${key}[[:space:]]+" "$conf_file"; then
    _EGREP "^[[:space:]]*${key}[[:space:]]+" "$conf_file" | _AWK '{print $2; exit}'
  fi
}

########################
# Set a configuration setting value
# Globals:
#   REDIS_BASE_DIR, REDIS_CONF_FILE (optional)
# Arguments:
#   $1 - key
#   $2 - value (raw; will be sanitized for sed-safe replacing)
# Returns:
#   None
#########################
redis_conf_set() {
  local -r raw_key="${1:?missing key}"
  local value="${2-}"
  local -r conf_file="$(_redis_conf_path)"
  local -r key_ere="$(_escape_ere "${raw_key}")"
  local -r key="${raw_key}"

  # Ensure target file exists to make replace_in_file/remove_in_file atomic and predictable.
  # We also make sure the parent dir exists.
  local conf_dir
  conf_dir="$(dirname -- "${conf_file}")"
  ensure_dir_exists "${conf_dir}"
  [[ -f "${conf_file}" ]] || : > "${conf_file}"

  # Sanitize the value for sed/regex contexts used by replace_in_file.
  # 1) Escape backslashes and sed's '&' and '?' which are special in some sed builds.
  # 2) Strip literal newlines/tabs/CRs to keep redis.conf single-line values.
  # 3) Preserve explicit empty string by quoting as "" (historical behavior).
  value="${value//\\/\\\\}"
  value="${value//&/\\&}"
  value="${value//\?/\\?}"
  value="${value//$'\n'/}"
  value="${value//$'\r'/}"
  value="${value//$'\t'/}"
  [[ -z "${value}" ]] && value="\"\""

  # Special case: "save" must append rules instead of replacing existing ones.
  # This preserves the historical multi-rule behavior (e.g., save 900 1; save 300 10; ...).
  if [[ "${key}" == "save" ]]; then
      printf '%s %s\n' "${key}" "${value}" >> "${conf_file}"
      return
  fi

  # Replace existing (commented or not) or append if not present.
  replace_in_file "${conf_file}" "^#*[[:space:]]*${key_ere}[[:space:]].*" "${key} ${value}" false
  if ! _EGREP -q "^[[:space:]]*${key_ere}[[:space:]]+" "${conf_file}"; then
    printf '%s %s\n' "${key}" "${value}" >> "${conf_file}"
  fi
}



########################
# Unset a configuration setting value (remove any occurrences)
# Globals:
#   REDIS_BASE_DIR, REDIS_CONF_FILE (optional)
# Arguments:
#   $1 - key
# Returns:
#   None
#########################
redis_conf_unset() {
  local -r raw_key="${1:?missing key}"
  local -r key_ere="$(_escape_ere "${raw_key}")"
  local -r conf_file="$(_redis_conf_path)"
  remove_in_file "${conf_file}" "^[[:space:]]*${key_ere}[[:space:]].*" true
}

########################
# Get Redis version (from redis-cli)
# Globals:
#   REDIS_BASE_DIR
# Arguments:
#   None
# Returns:
#   Prints semantic version (e.g., 7.2.5)
#########################
redis_version() {
    # Sample: "redis-cli 7.2.5 ..."
    "${REDIS_BASE_DIR}/bin/redis-cli" --version 2>/dev/null \
      | _EGREP -o "[0-9]+(\.[0-9]+){2}" \
      | _AWK 'NR==1{print; exit}'
}

########################
# Get Redis major version
# Globals:
#   REDIS_BASE_DIR
# Arguments:
#   None
# Returns:
#   Prints major version (e.g., 7)
#########################
redis_major_version() {
    redis_version | _EGREP -o "^[0-9]+"
}

########################
# Check if Redis is running
# Globals:
#   REDIS_BASE_DIR
# Arguments:
#   $1 - pid file (optional; defaults to ${REDIS_BASE_DIR}/tmp/redis.pid)
# Returns:
#   Exit code 0 if running, 1 otherwise (no output)
#########################
is_redis_running() {
    local -r pid_file="${1:-"${REDIS_BASE_DIR}/tmp/redis.pid"}"
    local pid
    pid="$(get_pid_from_file "$pid_file")"

    if [[ -z "$pid" ]]; then
        return 1
    fi
    is_service_running "$pid"
}

########################
# Check if Redis is not running
# Arguments:
#   $1 - pid file (optional)
# Returns:
#   Exit code 0 if NOT running
#########################
is_redis_not_running() {
    ! is_redis_running "$@"
}

########################
# Stop Redis gracefully using redis-cli
# Globals:
#   REDIS_* (auth, TLS, user/group, base dir)
# Arguments:
#   None
# Returns:
#   None
#########################
redis_stop() {
    local pass=""
    local port=""
    local -a args=()

    is_redis_running || return 0

    pass="$(redis_conf_get "requirepass")"
    if is_boolean_yes "${REDIS_TLS_ENABLED:-no}"; then
        port="$(redis_conf_get "tls-port")"
        # Ensure redis-cli speaks TLS when server expects TLS.
        args+=("--tls")
        # Provide client auth material when present; tolerate missing files.
        [[ -n "${REDIS_TLS_CERT_FILE:-}" ]] && args+=("--cert" "${REDIS_TLS_CERT_FILE}")
        [[ -n "${REDIS_TLS_KEY_FILE:-}"  ]] && args+=("--key"  "${REDIS_TLS_KEY_FILE}")
        if [[ -n "${REDIS_TLS_CA_FILE:-}" ]]; then
            args+=("--cacert" "${REDIS_TLS_CA_FILE}")
        elif [[ -n "${REDIS_TLS_CA_DIR:-}" ]]; then
            # redis-cli supports --cacertdir (OpenSSL capath)
            args+=("--cacertdir" "${REDIS_TLS_CA_DIR}")
        fi
    else
        port="$(redis_conf_get "port")"
    fi

    [[ -n "$pass" ]] && args+=("-a" "$pass")
    [[ -n "$port" && "$port" != "0" ]] && args+=("-p" "$port")

    debug "Stopping Redis"
    if am_i_root; then
        run_as_user "${REDIS_DAEMON_USER}" "${REDIS_BASE_DIR}/bin/redis-cli" "${args[@]}" shutdown
    else
        "${REDIS_BASE_DIR}/bin/redis-cli" "${args[@]}" shutdown
    fi
}

########################
# Validate settings in REDIS_* env vars.
# Globals:
#   REDIS_*
# Arguments:
#   None
# Returns:
#   Exits with non-zero code on validation error(s)
#########################
redis_validate() {
    debug "Validating settings in REDIS_* env vars.."
    local error_code=0

    # Scoped helpers
    print_validation_error() {
        error "$1"
        error_code=1
    }
    empty_password_enabled_warn() {
        warn "You set ALLOW_EMPTY_PASSWORD=${ALLOW_EMPTY_PASSWORD}. For safety, never use this in production."
    }
    empty_password_error() {
        print_validation_error "The $1 environment variable is empty or not set. Set ALLOW_EMPTY_PASSWORD=yes to permit blank passwords (recommended only for development)."
    }

    if is_boolean_yes "${ALLOW_EMPTY_PASSWORD:-no}"; then
        empty_password_enabled_warn
    else
        [[ -z "${REDIS_PASSWORD:-}" ]] && empty_password_error REDIS_PASSWORD
    fi

    if [[ -n "${REDIS_REPLICATION_MODE:-}" ]]; then
        if [[ "${REDIS_REPLICATION_MODE}" =~ ^(slave|replica)$ ]]; then
            if [[ -n "${REDIS_MASTER_PORT_NUMBER:-}" ]]; then
                local err
                if ! err="$(validate_port "${REDIS_MASTER_PORT_NUMBER}")"; then
                    print_validation_error "An invalid port was specified in REDIS_MASTER_PORT_NUMBER: ${err}"
                fi
            fi
            if ! is_boolean_yes "${ALLOW_EMPTY_PASSWORD:-no}" && [[ -z "${REDIS_MASTER_PASSWORD:-}" ]]; then
                empty_password_error REDIS_MASTER_PASSWORD
            fi
        elif [[ "${REDIS_REPLICATION_MODE}" != "master" ]]; then
            print_validation_error "Invalid replication mode. Available options are 'master/replica'."
        fi
    fi

    if is_boolean_yes "${REDIS_TLS_ENABLED:-no}"; then
        if [[ "${REDIS_PORT_NUMBER:-}" == "${REDIS_TLS_PORT_NUMBER:-}" ]] && [[ "${REDIS_PORT_NUMBER:-}" != "6379" ]]; then
            print_validation_error "REDIS_PORT_NUMBER and REDIS_TLS_PORT_NUMBER are equal (${REDIS_PORT_NUMBER}). Change one, or disable non-TLS by setting REDIS_PORT_NUMBER=0."
        fi

        if [[ -z "${REDIS_TLS_CERT_FILE:-}" ]]; then
            print_validation_error "You must provide a X.509 certificate to use TLS."
        elif [[ ! -f "${REDIS_TLS_CERT_FILE}" ]]; then
            print_validation_error "TLS certificate file not found: ${REDIS_TLS_CERT_FILE}"
        fi

        if [[ -z "${REDIS_TLS_KEY_FILE:-}" ]]; then
            print_validation_error "You must provide a private key to use TLS."
        elif [[ ! -f "${REDIS_TLS_KEY_FILE}" ]]; then
            print_validation_error "TLS private key file not found: ${REDIS_TLS_KEY_FILE}"
        fi

        if [[ -z "${REDIS_TLS_CA_FILE:-}" ]]; then
            if [[ -z "${REDIS_TLS_CA_DIR:-}" ]]; then
                print_validation_error "Provide either a CA certificate (REDIS_TLS_CA_FILE) or a CA directory (REDIS_TLS_CA_DIR) to use TLS."
            elif [[ ! -d "${REDIS_TLS_CA_DIR}" ]]; then
                print_validation_error "CA directory not found: ${REDIS_TLS_CA_DIR}"
            fi
        elif [[ ! -f "${REDIS_TLS_CA_FILE}" ]]; then
            print_validation_error "CA certificate file not found: ${REDIS_TLS_CA_FILE}"
        fi

        if [[ -n "${REDIS_TLS_DH_PARAMS_FILE:-}" ]] && [[ ! -f "${REDIS_TLS_DH_PARAMS_FILE}" ]]; then
            print_validation_error "DH params file not found: ${REDIS_TLS_DH_PARAMS_FILE}"
        fi
    fi

    [[ "$error_code" -eq 0 ]] || exit "$error_code"
}

########################
# Configure Redis replication
# Globals:
#   REDIS_BASE_DIR, REDIS_* (replication, TLS, sentinel)
# Arguments:
#   None (uses env)
# Returns:
#   None
#########################
# --- redis_configure_replication (announce IP/port, sentinel parse, masterauth) ---
redis_configure_replication() {
  info "Configuring replication mode"

  local announce_ip
  announce_ip="$(_strip_brackets_if_v6 "${REDIS_REPLICA_IP:-$(get_machine_ip)}")"
  redis_conf_set replica-announce-ip "${announce_ip}"

  if is_boolean_yes "${REDIS_TLS_ENABLED:-no}"; then
    redis_conf_set tls-replication yes
    redis_conf_set replica-announce-port "${REDIS_TLS_PORT_NUMBER}"
  else
    redis_conf_set replica-announce-port "${REDIS_PORT_NUMBER}"
  fi

  if [[ "${REDIS_REPLICATION_MODE:-}" == "master" ]]; then
    # 'masterauth' is not needed on master; replicas will set it below.
    return
  fi

  if [[ "${REDIS_REPLICATION_MODE:-}" =~ ^(slave|replica)$ ]]; then
    if [[ -n "${REDIS_SENTINEL_HOST:-}" ]]; then
      local -a sentinel_info_command=("${REDIS_BASE_DIR}/bin/redis-cli" "-h" "${REDIS_SENTINEL_HOST}" "-p" "${REDIS_SENTINEL_PORT_NUMBER}")
      if is_boolean_yes "${REDIS_TLS_ENABLED:-no}"; then
        sentinel_info_command+=("--tls")
        [[ -n "${REDIS_TLS_CERT_FILE:-}" ]] && sentinel_info_command+=("--cert" "${REDIS_TLS_CERT_FILE}")
        [[ -n "${REDIS_TLS_KEY_FILE:-}"  ]] && sentinel_info_command+=("--key"  "${REDIS_TLS_KEY_FILE}")
        if [[ -n "${REDIS_TLS_CA_FILE:-}" ]]; then
          sentinel_info_command+=("--cacert" "${REDIS_TLS_CA_FILE}")
        elif [[ -n "${REDIS_TLS_CA_DIR:-}" ]]; then
          sentinel_info_command+=("--cacertdir" "${REDIS_TLS_CA_DIR}")
        fi
      fi
      sentinel_info_command+=("--raw" "sentinel" "get-master-addr-by-name" "${REDIS_SENTINEL_MASTER_NAME}")
      local _s_host _s_port
      _s_host="$("${sentinel_info_command[@]}" 2>/dev/null | sed -n '1p')"
      _s_port="$("${sentinel_info_command[@]}" 2>/dev/null | sed -n '2p')"
      [[ -n "${_s_host:-}" ]] && REDIS_MASTER_HOST="${_s_host}"
      [[ -n "${_s_port:-}" ]] && REDIS_MASTER_PORT_NUMBER="${_s_port}"
    fi

    wait_for_tcp_port "${REDIS_MASTER_HOST}" "${REDIS_MASTER_PORT_NUMBER}"

    [[ -n "${REDIS_MASTER_PASSWORD:-}" ]] && redis_conf_set masterauth "${REDIS_MASTER_PASSWORD}"

    local _host_no_brackets
    _host_no_brackets="$(_strip_brackets_if_v6 "${REDIS_MASTER_HOST}")"
    redis_conf_set "replicaof" "${_host_no_brackets} ${REDIS_MASTER_PORT_NUMBER}"
  fi
}


########################
# Disable Redis command(s)
# Globals:
#   REDIS_CONF_FILE (optional), REDIS_DISABLE_COMMANDS
# Arguments:
#   None (uses REDIS_DISABLE_COMMANDS)
# Returns:
#   None
#########################
redis_disable_unsafe_commands() {
    local -r conf_file="$(_redis_conf_path)"
    # Split comma-separated list into array
    # shellcheck disable=SC2207
    local -a disabledCommands=($(tr ',' ' ' <<< "${REDIS_DISABLE_COMMANDS}"))
    debug "Disabling commands: ${disabledCommands[*]}"
    local cmd
    for cmd in "${disabledCommands[@]}"; do
        if _EGREP -q "^[[:space:]]*rename-command[[:space:]]+${cmd}[[:space:]]+\"\"[[:space:]]*$" "${conf_file}"; then
            debug "${cmd} is already disabled"
            continue
        fi
        printf 'rename-command %s ""\n' "${cmd}" >> "${conf_file}"
    done
}

########################
# Redis configure permissions
# Globals:
#   REDIS_BASE_DIR, REDIS_DATA_DIR, REDIS_LOG_DIR, REDIS_DAEMON_USER, REDIS_DAEMON_GROUP
# Arguments:
#   None
# Returns:
#   None
#########################
redis_configure_permissions() {
    debug "Ensuring expected directories/files exist"
    local dir
    for dir in "${REDIS_BASE_DIR}" "${REDIS_DATA_DIR}" "${REDIS_BASE_DIR}/tmp" "${REDIS_LOG_DIR}"; do
        ensure_dir_exists "$dir"
        if am_i_root; then
            chown "${REDIS_DAEMON_USER}:${REDIS_DAEMON_GROUP}" "$dir"
        fi
    done
}

########################
# Redis specific configuration to override the default one
# Globals:
#   REDIS_MOUNTED_CONF_DIR
# Arguments:
#   None
# Returns:
#   None
#########################
redis_override_conf() {
    if [[ ! -e "${REDIS_MOUNTED_CONF_DIR}/redis.conf" ]]; then
        # Configure replication mode when no external redis.conf is provided
        if [[ -n "${REDIS_REPLICATION_MODE:-}" ]]; then
            redis_configure_replication
        fi
    fi
}

########################
# Ensure Redis is initialized
# Globals:
#   REDIS_*
# Arguments:
#   None
# Returns:
#   None
#########################
redis_initialize() {
    redis_configure_default
    redis_override_conf
}

#########################
# Append include directives to redis.conf (move include to the end)
# Globals:
#   REDIS_OVERRIDES_FILE
# Arguments:
#   None
# Returns:
#   None
#########################
redis_append_include_conf() {
    local -r conf_file="$(_redis_conf_path)"
    if [[ -f "${REDIS_OVERRIDES_FILE:-}" ]]; then
        # Remove ALL existing include lines (commented or not), then append once at the end.
        remove_in_file "${conf_file}" "^[[:space:]]*#*[[:space:]]*include[[:space:]].*$" true
        printf 'include %s\n' "${REDIS_OVERRIDES_FILE}" >> "${conf_file}"
    fi
}

########################
# Configure Redis permissions and general parameters (also used in redis-cluster container)
# Globals:
#   REDIS_* (many)
# Arguments:
#   None
# Returns:
#   None
#########################
redis_configure_default() {
    info "Initializing Redis"

    # Remove stale PID to avoid accidental termination by traps when PID is reused.
    rm -f "${REDIS_BASE_DIR}/tmp/redis.pid"

    redis_configure_permissions

    # User-injected custom configuration takes precedence
    if [[ -e "${REDIS_MOUNTED_CONF_DIR}/redis.conf" ]]; then
        if [[ -e "${REDIS_BASE_DIR}/etc/redis-default.conf" ]]; then
            rm -f "${REDIS_BASE_DIR}/etc/redis-default.conf"
        fi
        cp -f "${REDIS_MOUNTED_CONF_DIR}/redis.conf" "$(_redis_conf_path)"
        return
    fi

    info "Setting Redis config file (defaults + env overrides)"

    if is_boolean_yes "${ALLOW_EMPTY_PASSWORD:-no}"; then
        # Allow remote connections without password (dangerous in prod)
        redis_conf_set protected-mode no
    fi

    # Allow remote connections if requested
    if is_boolean_yes "${REDIS_ALLOW_REMOTE_CONNECTIONS:-no}"; then
        redis_conf_set bind "0.0.0.0 ::"
    fi

    # Persistence: AOF
    redis_conf_set appendonly "${REDIS_AOF_ENABLED}"

    # Persistence: RDB save rules
    # REDIS_RDB_POLICY example: "900#1 300#10 60#10000"
    if is_empty_value "${REDIS_RDB_POLICY:-}"; then
        if is_boolean_yes "${REDIS_RDB_POLICY_DISABLED:-no}"; then
            redis_conf_set save ""
        fi
    else
        local i
        for i in ${REDIS_RDB_POLICY}; do
            # Convert "sec#changes" to "sec changes"
            redis_conf_set save "${i//#/ }"
        done
    fi

    # Networking / TLS
    redis_conf_set port "${REDIS_PORT_NUMBER}"
    if is_boolean_yes "${REDIS_TLS_ENABLED:-no}"; then
        if [[ "${REDIS_PORT_NUMBER}" == "6379" && "${REDIS_TLS_PORT_NUMBER}" == "6379" ]]; then
            # Default overlap: enable TLS-only
            redis_conf_set port 0
            redis_conf_set tls-port "${REDIS_TLS_PORT_NUMBER}"
        else
            redis_conf_set tls-port "${REDIS_TLS_PORT_NUMBER}"
        fi
        redis_conf_set tls-cert-file "${REDIS_TLS_CERT_FILE}"
        redis_conf_set tls-key-file  "${REDIS_TLS_KEY_FILE}"
        if is_empty_value "${REDIS_TLS_CA_FILE:-}"; then
            redis_conf_set tls-ca-cert-dir "${REDIS_TLS_CA_DIR}"
        else
            redis_conf_set tls-ca-cert-file "${REDIS_TLS_CA_FILE}"
        fi
        [[ -n "${REDIS_TLS_KEY_FILE_PASS:-}"  ]] && redis_conf_set tls-key-file-pass "${REDIS_TLS_KEY_FILE_PASS}"
        [[ -n "${REDIS_TLS_DH_PARAMS_FILE:-}" ]] && redis_conf_set tls-dh-params-file "${REDIS_TLS_DH_PARAMS_FILE}"
        redis_conf_set tls-auth-clients "${REDIS_TLS_AUTH_CLIENTS}"
    fi

    # Multithreading
    [[ -n "${REDIS_IO_THREADS_DO_READS:-}" ]] && redis_conf_set "io-threads-do-reads" "${REDIS_IO_THREADS_DO_READS}"
    [[ -n "${REDIS_IO_THREADS:-}"          ]] && redis_conf_set "io-threads"          "${REDIS_IO_THREADS}"

    # Authentication
    if [[ -n "${REDIS_PASSWORD:-}" ]]; then
        redis_conf_set requirepass "${REDIS_PASSWORD}"
    else
        redis_conf_unset requirepass
    fi

    # ACL config file
    [[ -n "${REDIS_ACLFILE:-}" ]] && redis_conf_set aclfile "${REDIS_ACLFILE}"

    # Disable unsafe commands if requested
    [[ -n "${REDIS_DISABLE_COMMANDS:-}" ]] && redis_disable_unsafe_commands

    # Move include to the end to allow overrides to win
    redis_append_include_conf
}
