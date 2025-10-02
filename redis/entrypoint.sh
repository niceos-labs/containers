#!/usr/bin/env bash
# =============================================================================
#  NiceOS · Redis Entrypoint
#  File: entrypoint.sh
#
#  Copyright (c) 2025, NiceSOFT.
#  All rights reserved. Non-free software.
#
#  Purpose
#  -------
#  Container entrypoint wrapper that:
#    • Loads the NiceOS Redis environment.
#    • Prints a friendly banner (version, key paths).
#    • Copies default configs into the live config dir WITHOUT overwriting
#      user-provided files (idempotent).
#    • Optionally runs the setup phase when the command indicates legacy run
#      paths (or an explicit env toggle).
#    • Finally execs the provided command (PID 1 handoff).
#
#  Notes
#  -----
#  - No duplication of helpers: relies on NiceOS libraries only.
#  - Backward-compat triggers: setup runs when arguments include
#      /nicesoft/niceos/scripts/redis/run.sh   OR   /run.sh
#    You can also force setup via NICEOS_REDIS_RUN_SETUP=true.
# =============================================================================
# shellcheck disable=SC1091

set -Eeuo pipefail
IFS=$'\n\t'
# Uncomment for debug tracing:
# set -x

# Module tag for NiceOS logger (if used)
: "${NICEOS_MODULE:=redis}"
export NICEOS_MODULE=redis

# --------------------------- Load environment & libs --------------------------
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
if [ -r /nicesoft/niceos/scripts/libredis.sh ]; then
  # shellcheck disable=SC1091
  . /nicesoft/niceos/scripts/libredis.sh
fi
if [ -r /nicesoft/niceos/scripts/redis-env.sh ]; then
  # shellcheck disable=SC1091
  . /nicesoft/niceos/scripts/redis-env.sh
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
# Welcome banner (if NiceOS helper is present)
# -----------------------------------------------------------------------------
if command -v niceos_print_welcome_page >/dev/null 2>&1; then
  niceos_print_welcome_page || true
else
  printf 'NiceOS Redis Entrypoint: base libraries not found, continuing.\n' 1>&2
fi

# A blank line for readability before handing control to the app
printf '\n'

# --------------------------- Banner ------------------------------------------
_redis_banner() {
  local ver=""
  if command -v redis-server >/dev/null 2>&1; then
    ver="$(redis-server -v 2>/dev/null || true)"
  fi
  info  "🚀 Starting NiceOS Redis entrypoint"
  info "Paths:
$(indent "BASE=${REDIS_BASE_DIR}
CONF_DIR=${REDIS_CONF_DIR}
CONF_FILE=${REDIS_CONF_FILE}
DEFAULT_CONF_DIR=${REDIS_DEFAULT_CONF_DIR}
DATA_DIR=${REDIS_DATA_DIR}
LOG_DIR=${REDIS_LOG_DIR}" 2)"
  [[ -n "$ver" ]] && info "Redis: ${ver}"
}
_redis_banner

# --------------------------- Copy default configs (no overwrite) --------------
# Intent: avoid breaking users that bypass setup; if the file already exists,
# do NOT overwrite it.
debug "Copying defaults from '${REDIS_DEFAULT_CONF_DIR}' -> '${REDIS_CONF_DIR}' (no overwrite)"
if command -v rsync >/dev/null 2>&1; then
  rsync -a --ignore-existing "${REDIS_DEFAULT_CONF_DIR}/" "${REDIS_CONF_DIR}/" 2>/dev/null || true
else
  cp -rnp "${REDIS_DEFAULT_CONF_DIR}/." "${REDIS_CONF_DIR}/" 2>/dev/null || true
fi

# After the rsync/cp -rnp block that copies ${REDIS_DEFAULT_CONF_DIR} -> ${REDIS_CONF_DIR}
# Ensure the active redis.conf exists by seeding from system config once (non-overwriting)
if [[ ! -f "${REDIS_CONF_FILE}" ]]; then
  if [[ -f "${REDIS_DEFAULT_CONF_DIR}/redis.conf" ]]; then
    cp -a "${REDIS_DEFAULT_CONF_DIR}/redis.conf" "${REDIS_CONF_FILE}" || true
  elif [[ -r "/etc/redis.conf" ]]; then
    # last resort: seed directly from system file, but into /app
    cp -a "/etc/redis.conf" "${REDIS_CONF_FILE}" || true
  fi
fi


# --------------------------- Optional setup phase -----------------------------
_should_run_setup() {
  # Return 0 (true) if we should run the setup phase.
  local full="$*"
  case "${NICEOS_REDIS_RUN_SETUP:-}" in
    1|true|yes|TRUE|YES) return 0 ;;
  esac
  case "$full" in
    *"/nicesoft/niceos/scripts/run-redis.sh"*|*"/run.sh"*) return 0 ;;
  esac
  return 1
}

if _should_run_setup "$*"; then
  info "** Starting Redis setup **"
  # Canonical NiceOS setup path
  local_setup="/nicesoft/niceos/scripts/setup-redis.sh"
  if [[ -x "$local_setup" ]]; then
    "$local_setup"
  else
    error "Setup script not found or not executable: ${local_setup}"
    exit 1
  fi
  info "** Redis setup finished! **"
fi

# --------------------------- Exec handoff -------------------------------------
echo
exec "$@"
