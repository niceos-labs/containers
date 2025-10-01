#!/usr/bin/env bash
# =============================================================================
#  NiceOS OpenJDK Entrypoint
#
#  Purpose
#    A safe, container-friendly entrypoint for OpenJDK-based images on NiceOS.
#    It gently wires in NiceOS logging/util libraries (and locale overlays),
#    applies sane Java defaults for containers, fixes pre-Java 9 edge cases,
#    and finally `exec`s the target command.
#
#  Key behaviors
#    • Refuses to run as root unless explicitly allowed.
#    • Auto-loads NiceOS base libs if present; auto-loads RU locale overlays
#      when LANG is ru_RU.UTF8 (or compatible UTF-8 variants).
#    • Prints a welcome banner if available.
#    • On NiceOS + APP_VERSION=1.8*, removes module-related flags from
#      JAVA_TOOL_OPTIONS (the module system exists only since Java 9).
#    • Establishes container-friendly Java defaults without overriding
#      explicit user-provided settings.
#
#  Environment knobs
#    NICEOS_ALLOW_ROOT=1            # allow running as root (not recommended)
#    NICEOS_WELC_STYLE=emoji|clean  # welcome banner style (default: emoji)
#    NICEOS_MODULE=openjdk-entrypoint
#    APP_VERSION=...                # app/runtime version hint (e.g., 1.8.0_392)
#    JAVA_TOOL_OPTIONS              # respected; defaults are only applied if unset
#    JAVA_OPTS                      # forwarded to Java by the app (not modified)
#
#  Notes on Java defaults (see the section "Container‑sane Java defaults")
#    • We prefer memory-percent flags in modern JDKs.
#    • For JDK 8 series we avoid module flags and suggest cgroup awareness.
#    • Defaults are conservative; users can override via JAVA_TOOL_OPTIONS.
# =============================================================================

set -o errexit
set -o nounset
set -o pipefail
# set -o xtrace  # enable for debugging this script

# -----------------------------------------------------------------------------
# Root hard-deny (can be overridden explicitly)
# -----------------------------------------------------------------------------
if [ "${NICEOS_ALLOW_ROOT:-0}" != "1" ] && [ "$(id -u)" -eq 0 ]; then
  echo "Refusing to run as root. Set NICEOS_ALLOW_ROOT=1 to override (not recommended)." >&2
  exit 1
fi

# -----------------------------------------------------------------------------
# Source NiceOS base libraries if available (safe to skip if missing)
# -----------------------------------------------------------------------------
if [ -r /nicesoft/niceos/scripts/liblog.sh ]; then
  # shellcheck disable=SC1091
  . /nicesoft/niceos/scripts/liblog.sh
fi
if [ -r /nicesoft/niceos/scripts/libniceos.sh ]; then
  # shellcheck disable=SC1091
  . /nicesoft/niceos/scripts/libniceos.sh
fi

# -----------------------------------------------------------------------------
# Optional RU locale overlays (only when LANG is ru_RU.* UTF‑8)
#   • This allows localized messages/log formatting while preserving the
#     default behavior for all other locales.
# -----------------------------------------------------------------------------
_lang=${LANG:-}
if printf '%s' "${_lang}" | grep -Eq '^ru_RU\.(UTF-?8|utf-?8)$'; then
  if [ -r /nicesoft/niceos/scripts/locale/liblog.ru.sh ]; then
    # shellcheck disable=SC1091
    . /nicesoft/niceos/scripts/locale/liblog.ru.sh
  fi
  if [ -r /nicesoft/niceos/scripts/locale/libniceos.ru.sh ]; then
    # shellcheck disable=SC1091
    . /nicesoft/niceos/scripts/locale/libniceos.ru.sh
  fi
fi

# -----------------------------------------------------------------------------
# Minimal logger shims: use NiceOS logger if present, otherwise fall back
# -----------------------------------------------------------------------------
log_info()  { if command -v info  >/dev/null 2>&1; then info  "$@";  else printf '[INFO] %s\n'  "$*" >&2; fi; }
log_warn()  { if command -v warn  >/dev/null 2>&1; then warn  "$@";  else printf '[WARN] %s\n'  "$*" >&2; fi; }
log_error() { if command -v error >/dev/null 2>&1; then error "$@";  else printf '[ERROR] %s\n' "$*" >&2; fi; }

# Module tag for NiceOS logger (if used)
: "${NICEOS_MODULE:=openjdk21}"
export NICEOS_MODULE=openjdk21

# -----------------------------------------------------------------------------
# Helper utilities
# -----------------------------------------------------------------------------
_lower() { printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]'; }

# Read lowercase ID and ID_LIKE from /etc/os-release; returns "id,id_like"
_detect_os_id_and_like() {
  local id="" like=""
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    id="$(_lower "${ID:-}")"
    like="$(_lower "${ID_LIKE:-}")"
  fi
  printf '%s,%s' "$id" "$like"
}

# -----------------------------------------------------------------------------
# Detect NiceOS and sanitize JAVA_TOOL_OPTIONS for legacy JDK 1.8
# -----------------------------------------------------------------------------
_os_ids="$(_detect_os_id_and_like)"   # e.g., "niceos,linux" or ","
_app_version="${APP_VERSION:-}"
case "${_os_ids}" in
  niceos,*|*,*niceos*|*,*niceos) _is_niceos=true ;;
  *)                             _is_niceos=false ;;
esac

# Remove module flags for 1.8.* to avoid startup failures
if ${_is_niceos} && printf '%s' "${_app_version}" | grep -Eq '^1[.]8'; then
  if [ -n "${JAVA_TOOL_OPTIONS:-}" ]; then
    log_info "NiceOS + APP_VERSION=${_app_version}: sanitizing JAVA_TOOL_OPTIONS for legacy JDK 1.8"
    _filtered_opts=()
    _skip_next=0
    for tok in ${JAVA_TOOL_OPTIONS}; do
      if [ "${_skip_next}" -eq 1 ]; then _skip_next=0; continue; fi
      case "${tok}" in
        --module-path)   _skip_next=1; continue ;;
        --module-path=*)              continue ;;
      esac
      _filtered_opts+=("${tok}")
    done
    JAVA_TOOL_OPTIONS="${_filtered_opts[*]:-}"
    export JAVA_TOOL_OPTIONS
    log_info "JAVA_TOOL_OPTIONS sanitized: '${JAVA_TOOL_OPTIONS}'"
  fi
fi

# -----------------------------------------------------------------------------
# Java discovery: ensure JAVA_HOME and PATH are sensible
# -----------------------------------------------------------------------------
DEFAULT_PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
PATH="${PATH:-$DEFAULT_PATH}"

if [ -z "${JAVA_HOME:-}" ]; then
  # Probe a few common NiceOS locations; keep search cheap to avoid cold-start
  for d in /usr/lib/jvm/OpenJDK-* /lib64/jvm/OpenJDK-*; do
    if [ -x "$d/bin/java" ]; then
      export JAVA_HOME="$d"
      break
    fi
  done
fi

if [ -n "${JAVA_HOME:-}" ] && [ -d "${JAVA_HOME}/bin" ]; then
  case ":${PATH}:" in
    *:"${JAVA_HOME}/bin":*) : ;;  # already present
    *) PATH="${JAVA_HOME}/bin:${PATH}" ;;
  esac
fi
export PATH

# -----------------------------------------------------------------------------
# Container‑sane Java defaults (applied ONLY if JAVA_TOOL_OPTIONS is unset)
#   Why JAVA_TOOL_OPTIONS?
#     • It is recognized by the JVM automatically without changing app launchers.
#     • It keeps users in control: any explicit JAVA_TOOL_OPTIONS overrides this.
#   Memory policy:
#     • Modern JDKs understand MaxRAMPercentage/InitialRAMPercentage.
#     • For 1.8 we provide cgroup hints and a safer MaxRAMFraction.
#   Other flags:
#     • AlwaysPreTouch reduces first-GC latency by committing heap up front.
#     • ExitOnOutOfMemoryError ensures the process fails fast under OOM.
#     • UTF-8 default encodings avoid mojibake in logs and filenames.
#     • java.security.egd speeds up SecureRandom seeding in containers.
#   System-level knobs:
#     • MALLOC_ARENA_MAX=2 reduces glibc heap fragmentation on multi-core.
# -----------------------------------------------------------------------------
export MALLOC_ARENA_MAX="${MALLOC_ARENA_MAX:-2}"

if [ -z "${JAVA_TOOL_OPTIONS:-}" ]; then
  # Default set for modern JDKs (9+). Conservative but container-aware.
  _DEFAULT_JAVA_TOOL_OPTIONS=(
    "-XX:MaxRAMPercentage=75.0"         # leave ~25% headroom for native libs/GC/metaspace
    "-XX:InitialRAMPercentage=10.0"     # avoid grabbing too much at startup
    "-XX:+ExitOnOutOfMemoryError"       # crash fast on OOM (lets orchestrators restart)
    "-XX:+AlwaysPreTouch"               # reduce page faults during runtime
    "-Dfile.encoding=UTF-8"             # predictable charset for streams
    "-Dsun.jnu.encoding=UTF-8"          # predictable charset for filenames
    "-Djava.security.egd=file:/dev/urandom"  # faster SecureRandom seeding
  )

  # If APP_VERSION hints a JDK 1.8 runtime, append legacy-friendly defaults.
  if printf '%s' "${_app_version}" | grep -Eq '^1[.]8'; then
    _DEFAULT_JAVA_TOOL_OPTIONS+=(
      "-XX:+UnlockExperimentalVMOptions"        # required for some cgroup flags in older 8u builds
      "-XX:+UseCGroupMemoryLimitForHeap"        # best-effort cgroup awareness (8u191+)
      "-XX:MaxRAMFraction=2"                    # similar to 50% heap; safer for mixed workloads
      "-XX:+UseG1GC"                            # consistent GC default for server workloads
    )
  fi

  JAVA_TOOL_OPTIONS="${_DEFAULT_JAVA_TOOL_OPTIONS[*]}"
  export JAVA_TOOL_OPTIONS
  log_info "Applied container-sane JAVA_TOOL_OPTIONS defaults"
fi

# -----------------------------------------------------------------------------
# Welcome banner (if NiceOS helper is present)
# -----------------------------------------------------------------------------
if command -v niceos_print_welcome_page >/dev/null 2>&1; then
  niceos_print_welcome_page || true
else
  printf 'NiceOS OpenJDK Entrypoint: base libraries not found, continuing.\n' 1>&2
fi

# A blank line for readability before handing control to the app
printf '\n'

# -----------------------------------------------------------------------------
# Hand over control to the target command
# -----------------------------------------------------------------------------
exec "$@"
