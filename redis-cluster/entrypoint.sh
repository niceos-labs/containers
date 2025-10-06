#!/usr/bin/env bash
# =============================================================================
#  NiceOS · Redis Entrypoint
#  File: entrypoint.sh
#
# =============================================================================
# shellcheck disable=SC1091

set -o errexit
set -o nounset
set -o pipefail
# set -o xtrace # Uncomment this line for debugging purposes

# --- tiny safe source helper --------------------------------------------------
_maybe_source() { [ -r "$1" ] && . "$1"; }

# --- load NiceOS libs ---------------------------------------------------------
_maybe_source "/nicesoft/niceos/scripts/libniceos.sh"
_maybe_source "/nicesoft/niceos/scripts/redis-cluster-env.sh"
_maybe_source "/nicesoft/niceos/scripts/librediscluster.sh"

# RU locale overlays (optional)
_lang=${LANG:-}
if printf '%s' "$_lang" | grep -Eq '^ru_RU\.(UTF-?8|utf-?8)$'; then
  _maybe_source "/nicesoft/niceos/scripts/locale/liblog.ru.sh"
  _maybe_source "/nicesoft/niceos/scripts/locale/libniceos.ru.sh"
fi

# --- banner -------------------------------------------------------------------
_redis_banner() {
  local ver=""
  command -v redis-server >/dev/null 2>&1 && ver="$(redis-server -v 2>/dev/null || true)"
  info "🚀 Starting NiceOS Redis entrypoint"
  info $'Paths:\n'"$(indent "BASE=${REDIS_BASE_DIR}
CONF_DIR=${REDIS_CONF_DIR}
CONF_FILE=${REDIS_CONF_FILE}
DEFAULT_CONF_DIR=${REDIS_DEFAULT_CONF_DIR}
DATA_DIR=${REDIS_DATA_DIR}
LOG_DIR=${REDIS_LOG_DIR}" 2)"
  [ -n "$ver" ] && info "Redis: ${ver}"
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

echo ""
exec "$@"