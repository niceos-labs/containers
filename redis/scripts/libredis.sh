#!/usr/bin/env bash
# =============================================================================
#  NiceOS Redis Library
#  File: libredis.sh
#
#  Copyright (c) 2025, NiceSOFT.
#  All rights reserved. Non-free software.
#
#  Purpose
#  -------
#  A focused helper set for configuring and managing Redis under NiceOS.
#  It provides thin, careful wrappers to:
#    • read/write redis.conf
#    • query Redis version
#    • check/stop a running Redis
#    • validate REDIS_* environment
#    • configure replication and defaults
#
#  Design principles
#  -----------------
#  - Safe to `source`: does not mutate caller's set/shopt/traps; never exits
#    the caller (except redis_validate() which intentionally exits on errors
#    to preserve historical contract in setup flows).
#  - NO duplication of utilities: relies on NiceOS libraries exclusively:
#      /nicesoft/niceos/scripts/libfile.sh        replace_in_file/remove_in_file
#      /nicesoft/niceos/scripts/liblog.sh         info/warn/error/debug/trace, indent
#      /nicesoft/niceos/scripts/libnet.sh         wait-for-port / wait_for_port
#      /nicesoft/niceos/scripts/libos.sh          am_i_root/run_as_user/ensure_dir_exists
#      /nicesoft/niceos/scripts/libservice.sh     get_pid_from_file/is_service_running
#      /nicesoft/niceos/scripts/libvalidations.sh is_boolean_yes, validate_port, is_empty_value, …
#  - Backward compatibility: function names/arguments are preserved.
#  - Explicit, human-friendly log messages (NiceOS style).
#
#  Key environment variables (commonly set by the image/entrypoint)
#  ----------------------------------------------------------------
#    REDIS_BASE_DIR               e.g. /opt/redis
#    REDIS_CONF_FILE              path to redis.conf (defaults to $REDIS_BASE_DIR/etc/redis.conf)
#    REDIS_MOUNTED_CONF_DIR       external config mount (if present, takes precedence)
#    REDIS_OVERRIDES_FILE         extra include file appended to redis.conf
#    REDIS_DATA_DIR, REDIS_LOG_DIR
#    REDIS_DAEMON_USER, REDIS_DAEMON_GROUP
#    REDIS_AOF_ENABLED            yes/no
#    REDIS_RDB_POLICY             "sec#times sec#times …"  (space-separated)
#    REDIS_RDB_POLICY_DISABLED    yes/no
#    ALLOW_EMPTY_PASSWORD         yes/no
#    REDIS_ALLOW_REMOTE_CONNECTIONS yes/no
#    REDIS_PASSWORD               if set -> requirepass
#    REDIS_DISABLE_COMMANDS       comma-separated list
#    REDIS_ACLFILE                path to ACL file
#    REDIS_PORT_NUMBER            default 6379
#    REDIS_TLS_ENABLED            yes/no
#    REDIS_TLS_PORT_NUMBER        default 6379
#    REDIS_TLS_*                  cert/key/CA params
#    REDIS_IO_THREADS, REDIS_IO_THREADS_DO_READS
#    REDIS_REPLICATION_MODE       master|replica|slave
#    REDIS_MASTER_HOST, REDIS_MASTER_PORT_NUMBER, REDIS_MASTER_PASSWORD
#    REDIS_REPLICA_IP, REDIS_REPLICA_PORT
#    REDIS_SENTINEL_*             for auto-discovery (optional)
# =============================================================================
# shellcheck disable=SC1091

# --------------------------- Load NiceOS libraries ----------------------------
. /nicesoft/niceos/scripts/libfile.sh
. /nicesoft/niceos/scripts/liblog.sh
. /nicesoft/niceos/scripts/libnet.sh
. /nicesoft/niceos/scripts/libos.sh
. /nicesoft/niceos/scripts/libservice.sh
. /nicesoft/niceos/scripts/libvalidations.sh

# --------------------------- Internals ----------------------------------------
# Resolve the active redis.conf path, honoring REDIS_CONF_FILE if exported.
_redis__conf_path() {
  local base="${REDIS_BASE_DIR:-/app}"
  if [[ -n "${REDIS_CONF_FILE:-}" ]]; then
    printf '%s\n' "$REDIS_CONF_FILE"
  else
    printf '%s\n' "${base}/etc/redis.conf"
  fi
}

# Escape a value for sed-friendly replacement and strip control whitespace.
_redis__escape_value() {
  local v="${1-}"
  v="${v//\\/\\\\}"        # backslashes
  v="${v//&/\\&}"          # sed replacement ampersand
  v="${v//\?/\\?}"         # literal question mark for some sed flavors
  v="${v//$'\t'/ }"        # tabs -> space
  v="${v//$'\n'/ }"        # newlines -> space
  v="${v//$'\r'/ }"        # CR -> space
  [[ -z "$v" ]] && v='""'  # keep explicit empty
  printf '%s' "$v"
}

# =========================== PUBLIC API (unchanged) ===========================

########################
# Retrieve a configuration setting value
# Globals:
#   REDIS_BASE_DIR, REDIS_CONF_FILE (optional)
# Arguments:
#   $1 - key
#   $2 - conf file (optional)
# Returns:
#   Prints the value (2nd whitespace-separated field) if found.
#########################
redis_conf_get() {
    local -r key="${1:?missing key}"
    local -r conf_file="${2:-"$(_redis__conf_path)"}"

    if [[ ! -r "$conf_file" ]]; then
      debug "redis_conf_get: redis.conf is not readable: $conf_file"
      return 0
    fi
    # Prefer the last definition to reflect the current effective value
    if grep -q -E "^[[:space:]]*#*[[:space:]]*${key}[[:space:]]+" "$conf_file"; then
        grep -E "^[[:space:]]*#*[[:space:]]*${key}[[:space:]]+" "$conf_file" | tail -n 1 | awk '{print $2}'
    fi
}

########################
# Set a configuration setting value
# Notes:
#   - Key 'save' is additive (multiple lines allowed) → always append.
#   - Other keys: replace existing (commented/uncommented) or append if missing.
# Globals:
#   REDIS_BASE_DIR, REDIS_CONF_FILE (optional)
# Arguments:
#   $1 - key
#   $2 - value
#########################
redis_conf_set() {
    local -r key="${1:?missing key}"
    local value="${2:-}"
    local -r conf="$(_redis__conf_path)"

    if [[ ! -f "$conf" ]]; then
      error "redis_conf_set: redis.conf not found at $conf"
      return 1
    fi

    value="$(_redis__escape_value "$value")"

    if [[ "$key" == "save" ]]; then
        echo "${key} ${value}" >> "$conf"
        debug "redis_conf_set: appended 'save ${value}'"
        return 0
    fi

    # Replace comment/uncomment forms; else append
    local -r pattern="^#*[[:space:]]*${key}[[:space:]].*$"
    if grep -q -E "$pattern" "$conf"; then
        replace_in_file "$conf" "$pattern" "${key} ${value}" false
        debug "redis_conf_set: replaced '${key}' with '${value}'"
    else
        echo "${key} ${value}" >> "$conf"
        debug "redis_conf_set: appended '${key} ${value}'"
    fi
}

########################
# Unset a configuration setting value
# Globals:
#   REDIS_BASE_DIR, REDIS_CONF_FILE (optional)
# Arguments:
#   $1 - key
#########################
redis_conf_unset() {
    local -r key="${1:?missing key}"
    local -r conf="$(_redis__conf_path)"
    remove_in_file "$conf" "^[[:space:]]*#*[[:space:]]*${key}[[:space:]].*$" false
    debug "redis_conf_unset: removed all '${key}' lines"
}

########################
# Get Redis version X.Y.Z
# Globals:
#   REDIS_BASE_DIR
#########################
redis_version() {
    local bin="${REDIS_BIN_DIR:-/usr/bin}"
    if command -v "${bin}/redis-server" >/dev/null 2>&1; then
        "${bin}/redis-server" -v 2>/dev/null | grep -Eo "[0-9]+\.[0-9]+\.[0-9]+"
    elif command -v "${bin}/redis-cli" >/dev/null 2>&1; then
        "${bin}/redis-cli" --version 2>/dev/null | grep -Eo "[0-9]+\.[0-9]+\.[0-9]+"
    fi
}


########################
# Get Redis major version
# Globals:
#   REDIS_BASE_DIR
#########################
redis_major_version() {
    redis_version | grep -E -o "^[0-9]+"
}

########################
# Check if Redis is running
# Globals:
#   REDIS_BASE_DIR
# Arguments:
#   $1 - pid file (optional, defaults to $REDIS_BASE_DIR/tmp/redis.pid)
# Returns:
#   0 if running; 1 otherwise
#########################
is_redis_running() {
    local pid_file="${1:-"${REDIS_PID_FILE:-${REDIS_TMP_DIR:-/app/run}/redis.pid}"}"
    local pid
    pid="$(get_pid_from_file "$pid_file")"

    if [[ -z "$pid" ]]; then
        false
    else
        is_service_running "$pid"
    fi
}

########################
# Check if Redis is not running
# (utility wrapper preserved for readability)
#########################
is_redis_not_running() {
    ! is_redis_running "$@"
}

########################
# Stop Redis (gracefully via redis-cli shutdown)
# TLS-aware: will pick tls-port if REDIS_TLS_ENABLED=yes
# Globals:
#   REDIS_*
#########################
redis_stop() {
    local pass port
    local args=()

    ! is_redis_running && return 0

    pass="$(redis_conf_get "requirepass")"
    if is_boolean_yes "$REDIS_TLS_ENABLED"; then
        port="$(redis_conf_get "tls-port")"
        [[ -z "$port" || "$port" == "0" ]] && port="${REDIS_TLS_PORT_NUMBER:-6379}"
        args+=("--tls" "-h" "127.0.0.1" "-p" "$port")
        [[ -n "${REDIS_TLS_CERT_FILE:-}" ]] && args+=("--cert" "${REDIS_TLS_CERT_FILE}")
        [[ -n "${REDIS_TLS_KEY_FILE:-}"  ]] && args+=("--key"  "${REDIS_TLS_KEY_FILE}")
        if [[ -n "${REDIS_TLS_CA_FILE:-}" ]]; then
          args+=("--cacert" "${REDIS_TLS_CA_FILE}")
        elif [[ -n "${REDIS_TLS_CA_DIR:-}" ]]; then
          args+=("--cacertdir" "${REDIS_TLS_CA_DIR}")
        fi
    else
        port="$(redis_conf_get "port")"
        [[ -z "$port" || "$port" == "0" ]] && port="${REDIS_PORT_NUMBER:-6379}"
        args+=("-h" "127.0.0.1" "-p" "$port")
    fi

    [[ -n "$pass" ]] && args+=("-a" "$pass")

    debug "Stopping Redis using redis-cli shutdown"
    local cli="${REDIS_BIN_DIR:-/usr/bin}/redis-cli"
    if am_i_root; then
        run_as_user "$REDIS_DAEMON_USER" "$cli" "${args[@]}" shutdown
    else
        "$cli" "${args[@]}" shutdown
    fi
}


########################
# Validate settings in REDIS_* env vars.
# Note: preserves historical contract — exits non-zero on validation errors.
# Globals:
#   REDIS_*
#########################
redis_validate() {
    debug "Validating settings in REDIS_* environment…"
    local error_code=0

    print_validation_error() {
        error "$1"
        error_code=1
    }

    empty_password_enabled_warn() {
        warn "ALLOW_EMPTY_PASSWORD=${ALLOW_EMPTY_PASSWORD} — this is unsafe in production."
    }
    empty_password_error() {
        print_validation_error "Missing $1. For development only, set ALLOW_EMPTY_PASSWORD=yes to allow blank passwords."
    }

    if is_boolean_yes "$ALLOW_EMPTY_PASSWORD"; then
        empty_password_enabled_warn
    else
        [[ -z "$REDIS_PASSWORD" ]] && empty_password_error REDIS_PASSWORD
    fi

    if [[ -n "$REDIS_REPLICATION_MODE" ]]; then
        if [[ "$REDIS_REPLICATION_MODE" =~ ^(slave|replica)$ ]]; then
            if [[ -n "$REDIS_MASTER_PORT_NUMBER" ]]; then
                if ! err=$(validate_port "$REDIS_MASTER_PORT_NUMBER"); then
                    print_validation_error "Invalid REDIS_MASTER_PORT_NUMBER: $err"
                fi
            fi
            if ! is_boolean_yes "$ALLOW_EMPTY_PASSWORD" && [[ -z "$REDIS_MASTER_PASSWORD" ]]; then
                empty_password_error REDIS_MASTER_PASSWORD
            fi
        elif [[ "$REDIS_REPLICATION_MODE" != "master" ]]; then
            print_validation_error "Invalid REDIS_REPLICATION_MODE. Use 'master' or 'replica'."
        fi
    fi

    if is_boolean_yes "$REDIS_TLS_ENABLED"; then
        if [[ "$REDIS_PORT_NUMBER" == "$REDIS_TLS_PORT_NUMBER" ]] && [[ "$REDIS_PORT_NUMBER" != "6379" ]]; then
            print_validation_error "REDIS_PORT_NUMBER and REDIS_TLS_PORT_NUMBER are equal (${REDIS_PORT_NUMBER}). Use different ports or set REDIS_PORT_NUMBER=0 to disable non-TLS."
        fi
        if [[ -z "$REDIS_TLS_CERT_FILE" ]]; then
            print_validation_error "TLS is enabled but REDIS_TLS_CERT_FILE is not set."
        elif [[ ! -f "$REDIS_TLS_CERT_FILE" ]]; then
            print_validation_error "TLS certificate file does not exist: ${REDIS_TLS_CERT_FILE}"
        fi
        if [[ -z "$REDIS_TLS_KEY_FILE" ]]; then
            print_validation_error "TLS is enabled but REDIS_TLS_KEY_FILE is not set."
        elif [[ ! -f "$REDIS_TLS_KEY_FILE" ]]; then
            print_validation_error "TLS private key file does not exist: ${REDIS_TLS_KEY_FILE}"
        fi
        if [[ -z "$REDIS_TLS_CA_FILE" ]]; then
            if [[ -z "$REDIS_TLS_CA_DIR" ]]; then
                print_validation_error "Provide REDIS_TLS_CA_FILE or REDIS_TLS_CA_DIR when TLS is enabled."
            elif [[ ! -d "$REDIS_TLS_CA_DIR" ]]; then
                print_validation_error "CA directory does not exist: ${REDIS_TLS_CA_DIR}"
            fi
        elif [[ ! -f "$REDIS_TLS_CA_FILE" ]]; then
            print_validation_error "CA file does not exist: ${REDIS_TLS_CA_FILE}"
        fi
        if [[ -n "$REDIS_TLS_DH_PARAMS_FILE" ]] && [[ ! -f "$REDIS_TLS_DH_PARAMS_FILE" ]]; then
            print_validation_error "DH params file does not exist: ${REDIS_TLS_DH_PARAMS_FILE}"
        fi
    fi

    [[ "$error_code" -eq 0 ]] || exit "$error_code"
}

########################
# Configure Redis replication
# - Sets announce ip/port
# - Enables tls-replication when TLS is on
# - Master mode: sets masterauth from REDIS_PASSWORD (if any)
# - Replica/slave: optional Sentinel discovery, wait for master port, set masterauth/replicaof
# Globals:
#   REDIS_BASE_DIR, REDIS_* (see header)
#########################
redis_configure_replication() {
    info "Configuring Redis replication mode"

    redis_conf_set replica-announce-ip   "${REDIS_REPLICA_IP:-$(get_machine_ip)}"
    redis_conf_set replica-announce-port "${REDIS_REPLICA_PORT:-$REDIS_MASTER_PORT_NUMBER}"

    if is_boolean_yes "$REDIS_TLS_ENABLED"; then
        redis_conf_set tls-replication yes
    fi

    if [[ "$REDIS_REPLICATION_MODE" = "master" ]]; then
        [[ -n "$REDIS_PASSWORD" ]] && redis_conf_set masterauth "$REDIS_PASSWORD"
    elif [[ "$REDIS_REPLICATION_MODE" =~ ^(slave|replica)$ ]]; then
        if [[ -n "$REDIS_SENTINEL_HOST" ]]; then
            local -a sentinel_info_command=("redis-cli" "-h" "${REDIS_SENTINEL_HOST}" "-p" "${REDIS_SENTINEL_PORT_NUMBER}")
            if is_boolean_yes "$REDIS_TLS_ENABLED"; then
                sentinel_info_command+=("--tls")
                [[ -n "${REDIS_TLS_CERT_FILE:-}" ]] && sentinel_info_command+=("--cert" "${REDIS_TLS_CERT_FILE}")
                [[ -n "${REDIS_TLS_KEY_FILE:-}"  ]] && sentinel_info_command+=("--key"  "${REDIS_TLS_KEY_FILE}")
                if [[ -n "${REDIS_TLS_CA_FILE:-}" ]]; then
                    sentinel_info_command+=("--cacert" "${REDIS_TLS_CA_FILE}")
                else
                    sentinel_info_command+=("--cacertdir" "${REDIS_TLS_CA_DIR}")
                fi
            fi
            sentinel_info_command+=("sentinel" "get-master-addr-by-name" "${REDIS_SENTINEL_MASTER_NAME}")
            read -r -a REDIS_SENTINEL_INFO <<< "$("${sentinel_info_command[@]}" | tr '\n' ' ')"
            REDIS_MASTER_HOST=${REDIS_SENTINEL_INFO[0]}
            REDIS_MASTER_PORT_NUMBER=${REDIS_SENTINEL_INFO[1]}
            info "Discovered master via Sentinel ${REDIS_SENTINEL_HOST}:${REDIS_SENTINEL_PORT_NUMBER} ⇒ ${REDIS_MASTER_HOST}:${REDIS_MASTER_PORT_NUMBER}"
        fi

        wait-for-port --host "$REDIS_MASTER_HOST" "$REDIS_MASTER_PORT_NUMBER"
        [[ -n "$REDIS_MASTER_PASSWORD" ]] && redis_conf_set masterauth "$REDIS_MASTER_PASSWORD"
        redis_conf_set "replicaof" "$REDIS_MASTER_HOST $REDIS_MASTER_PORT_NUMBER"
    fi
}

########################
# Disable Redis command(s)
# Globals:
#   REDIS_CONF_FILE or defaults via REDIS_BASE_DIR
#   REDIS_DISABLE_COMMANDS (comma-separated)
#########################
redis_disable_unsafe_commands() {
    local -r conf="$(_redis__conf_path)"
    # comma → space, then into array
    read -r -a disabledCommands <<< "$(tr ',' ' ' <<< "$REDIS_DISABLE_COMMANDS")"
    [[ "${#disabledCommands[@]}" -gt 0 ]] || return 0

    debug "Disabling Redis commands: ${disabledCommands[*]}"
    for cmd in "${disabledCommands[@]}"; do
        if grep -E -q "^[[:space:]]*rename-command[[:space:]]+$cmd[[:space:]]+\"\"[[:space:]]*$" "$conf"; then
            debug "Command '$cmd' already disabled"
            continue
        fi
        echo "rename-command $cmd \"\"" >> "$conf"
    done
}

########################
# Redis configure permissions
# Ensures directories exist and have appropriate ownership.
# Globals:
#   REDIS_BASE_DIR, REDIS_DATA_DIR, REDIS_LOG_DIR, REDIS_DAEMON_USER/GROUP
#########################
redis_configure_permissions() {
  debug "Ensuring Redis directories exist and have correct ownership"
  for dir in "${REDIS_BASE_DIR}" "${REDIS_DATA_DIR}" "${REDIS_TMP_DIR}" "${REDIS_LOG_DIR}"; do
      [[ -n "$dir" ]] || continue
      ensure_dir_exists "$dir"
      if am_i_root; then
          chown "$REDIS_DAEMON_USER:$REDIS_DAEMON_GROUP" "$dir"
      fi
  done
}

########################
# Redis specific configuration overrides (replication etc.)
# Applied only when a user-supplied redis.conf is NOT provided.
#########################
redis_override_conf() {
  if [[ ! -e "${REDIS_MOUNTED_CONF_DIR}/redis.conf" ]]; then
      if [[ -n "$REDIS_REPLICATION_MODE" ]]; then
          redis_configure_replication
      fi
  fi
}

########################
# Ensure Redis is initialized (main high-level entry)
#########################
redis_initialize() {
  redis_configure_default
  redis_override_conf
}

#########################
# Append include directives to redis.conf (idempotent pattern)
# Removes any previous include lines and appends a single include to overrides.
#########################
redis_append_include_conf() {
    if [[ -f "$REDIS_OVERRIDES_FILE" ]]; then
        # Ensure the final state: only one include line at EOF
        redis_conf_unset "include"
        echo "include $REDIS_OVERRIDES_FILE" >> "$(_redis__conf_path)"
        debug "Appended include $REDIS_OVERRIDES_FILE to redis.conf"
    fi
}

########################
# Configure defaults into redis.conf (only when no full override is mounted)
# Covers: protected-mode, bind, AOF/RDB, ports/TLS, IO threads, password, ACL, includes.
#########################
redis_configure_default() {
    info "Initializing Redis configuration (defaults → redis.conf)"

    # Guard against stale PID between restarts
    rm -f "${REDIS_PID_FILE:-${REDIS_TMP_DIR:-/app/run}/redis.pid}"

    redis_configure_permissions

    # If user mounted a full redis.conf, just accept it verbatim.
    if [[ -e "${REDIS_MOUNTED_CONF_DIR}/redis.conf" ]]; then
        info "Using mounted configuration from ${REDIS_MOUNTED_CONF_DIR}/redis.conf"
        [[ -e "$REDIS_BASE_DIR/etc/redis-default.conf" ]] && rm -f "${REDIS_BASE_DIR}/etc/redis-default.conf"
        cp "${REDIS_MOUNTED_CONF_DIR}/redis.conf" "$(_redis__conf_path)"
        return 0
    fi

    info "Rendering redis.conf from environment variables"

    if is_boolean_yes "$ALLOW_EMPTY_PASSWORD"; then
        # Allow remote connections without password — development only
        redis_conf_set protected-mode no
    fi

    is_boolean_yes "$REDIS_ALLOW_REMOTE_CONNECTIONS" && redis_conf_set bind "0.0.0.0 ::"

    # AOF (fsync every second by default)
    redis_conf_set appendonly "${REDIS_AOF_ENABLED}"

    # RDB policy
    if is_empty_value "$REDIS_RDB_POLICY"; then
        if is_boolean_yes "$REDIS_RDB_POLICY_DISABLED"; then
            redis_conf_set save ""
        fi
    else
        local i
        for i in ${REDIS_RDB_POLICY}; do
            redis_conf_set save "${i//#/ }"
        done
    fi

    # Ports and TLS
    redis_conf_set port "$REDIS_PORT_NUMBER"
    if is_boolean_yes "$REDIS_TLS_ENABLED"; then
        if [[ "$REDIS_PORT_NUMBER" == "6379" ]] && [[ "$REDIS_TLS_PORT_NUMBER" == "6379" ]]; then
            # Default ports collide → TLS only
            redis_conf_set port 0
            redis_conf_set tls-port "$REDIS_TLS_PORT_NUMBER"
        else
            redis_conf_set tls-port "$REDIS_TLS_PORT_NUMBER"
        fi
        redis_conf_set tls-cert-file "$REDIS_TLS_CERT_FILE"
        redis_conf_set tls-key-file  "$REDIS_TLS_KEY_FILE"
        # Prefer explicit CA file; fall back to CA directory
        is_empty_value "$REDIS_TLS_CA_FILE" && \
          redis_conf_set tls-ca-cert-dir "$REDIS_TLS_CA_DIR" || \
          redis_conf_set tls-ca-cert-file "$REDIS_TLS_CA_FILE"
        ! is_empty_value "$REDIS_TLS_KEY_FILE_PASS" && redis_conf_set tls-key-file-pass "$REDIS_TLS_KEY_FILE_PASS"
        [[ -n "$REDIS_TLS_DH_PARAMS_FILE" ]] && redis_conf_set tls-dh-params-file "$REDIS_TLS_DH_PARAMS_FILE"
        redis_conf_set tls-auth-clients "$REDIS_TLS_AUTH_CLIENTS"
    fi

    # IO threads
    ! is_empty_value "$REDIS_IO_THREADS_DO_READS" && redis_conf_set "io-threads-do-reads" "$REDIS_IO_THREADS_DO_READS"
    ! is_empty_value "$REDIS_IO_THREADS"          && redis_conf_set "io-threads"          "$REDIS_IO_THREADS"

    # Password / ACL
    if [[ -n "$REDIS_PASSWORD" ]]; then
        redis_conf_set requirepass "$REDIS_PASSWORD"
    else
        redis_conf_unset requirepass
    fi

    [[ -n "$REDIS_DISABLE_COMMANDS" ]] && redis_disable_unsafe_commands
    [[ -n "$REDIS_ACLFILE"         ]] && redis_conf_set aclfile "$REDIS_ACLFILE"

    redis_append_include_conf
}
