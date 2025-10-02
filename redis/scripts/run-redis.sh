#!/usr/bin/env bash
# =============================================================================
#  NiceOS · Redis Runner
#  File: run-redis.sh
#
#  Purpose
#  -------
#  Build final arguments and exec redis-server in the foreground (PID 1):
#    • Always run with '--daemonize no' for container ergonomics.
#    • Respect REDIS_EXTRA_FLAGS and script args (highest precedence).
#    • By default, log to stdout ('--logfile ""') unless explicitly overridden.
#
#  Notes
#  -----
#  - We DO NOT generate redis.conf; it must be readable.
#  - We split REDIS_EXTRA_FLAGS safely without breaking global IFS.
#  - If running as root, we drop to $REDIS_DAEMON_USER; otherwise exec directly.
# =============================================================================
# shellcheck disable=SC1091

set -Eeuo pipefail

. /nicesoft/niceos/scripts/redis-env.sh
. /nicesoft/niceos/scripts/liblog.sh
. /nicesoft/niceos/scripts/libos.sh
[[ -r /nicesoft/niceos/scripts/libredis.sh ]] && . /nicesoft/niceos/scripts/libredis.sh

conf_path="${REDIS_CONF_FILE:-}"
if [[ -z "${conf_path}" || ! -r "${conf_path}" ]]; then
  error "Redis config not found or not readable: '${conf_path:-<empty>}'"
  exit 1
fi

# --- helpers ---
_has_flag() {
  # matches --flag  ИЛИ  --flag=value  среди REDIS_EXTRA_FLAGS и позиционных
  local needle="$1"; shift
  # check env (space separated)
  if [[ -n "${REDIS_EXTRA_FLAGS:-}" ]]; then
    # слово целиком или форма с '='
    if grep -Eq "(^|[[:space:]])${needle}([[:space:]]|=|$)" <<<"${REDIS_EXTRA_FLAGS}"; then
      return 0
    fi
  fi
  # check argv
  local a
  for a in "$@"; do
    [[ "$a" == "${needle}" || "$a" == "${needle}="* ]] && return 0
  done
  return 1
}

_strip_flag_from_array() {
  # удаляет из массива все вхождения --flag и --flag=*
  local flag="$1"; shift
  local -n arr_ref="$1"
  local out=()
  local x
  for x in "${arr_ref[@]}"; do
    if [[ "$x" == "${flag}" || "$x" == "${flag}="* ]]; then
      continue
    fi
    out+=("$x")
  done
  arr_ref=("${out[@]}")
}

# --- build args ---
args=("${conf_path}")

# Лог в stdout по умолчанию, если не указан в EXTRA/CLI
if ! _has_flag "--logfile" "$@"; then
  args+=("--logfile" "")
fi

# pidfile: либо правильный путь, либо пусто, если каталог недоступен
if ! _has_flag "--pidfile" "$@"; then
  pid_path="${REDIS_PID_FILE:-${REDIS_TMP_DIR:-/app/run}/redis.pid}"
  pid_dir="$(dirname -- "$pid_path")"
  if [[ -d "$pid_dir" && -w "$pid_dir" ]]; then
    args+=("--pidfile" "$pid_path")
  else
    warn "PID directory '$pid_dir' is not writable; starting without pidfile"
    args+=("--pidfile" "")
  fi
fi

# dir/save по умолчанию (не переопределяем явный выбор пользователя)
if ! _has_flag "--dir" "$@"; then
  args+=("--dir" "${REDIS_DATA_DIR}")
fi

if ! _has_flag "--save" "$@"; then
  if [[ "${REDIS_RDB_POLICY_DISABLED:-no}" =~ ^(1|yes|true)$ ]]; then
    args+=("--save" "")
  fi
fi

# Добавляем REDIS_EXTRA_FLAGS (без поддержки кавычек/эскейпов — сознательно)
if [[ -n "${REDIS_EXTRA_FLAGS:-}" ]]; then
  IFS=' ' read -r -a extra_flags <<< "${REDIS_EXTRA_FLAGS}"
  if [[ "${#extra_flags[@]}" -gt 0 ]]; then
    args+=("${extra_flags[@]}")
  fi
fi

# Затем — позиционные аргументы пользователя (высший приоритет, кроме daemonize)
if [[ "$#" -gt 0 ]]; then
  args+=("$@")
fi

# Жестко гарантируем foreground: убираем любые --daemonize*, и добавляем --daemonize no в КОНЕЦ
_strip_flag_from_array "--daemonize" args
args+=("--daemonize" "no")

info "Starting Redis (conf: ${conf_path})"

_safe() { printf '%q ' "$@" | sed -E 's/(--requirepass|-a) [^ ]+/\1 ****/g'; }
debug "redis-server args:
$(indent "$(_safe "${args[@]}")" 2)"

if am_i_root; then
  exec_as_user "${REDIS_DAEMON_USER}" redis-server "${args[@]}"
else
  exec redis-server "${args[@]}"
fi

