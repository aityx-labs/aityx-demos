# Sourced by the scripts: the settings from the environment, else from the
# repo's .env (see .env.example), else their defaults. Secrets are exported
# to the processes' environment only: never put on a command line.

_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# load_env <NAME>...: exports each variable from .env when it isn't set.
load_env() {
  local name value
  for name in "$@"; do
    if [[ -z "${!name:-}" && -f "$_root/.env" ]]; then
      value="$(sed -n "s/^${name}=//p" "$_root/.env" | tail -1)"
      value="${value%%#*}"
      value="${value%"${value##*[![:space:]]}"}"
      [[ -n "$value" ]] && export "$name=$value"
    fi
  done
  return 0
}
load_env API_PORT DATYX_BIND_HOST DATYX_API_PORT DATYX_DB_PORT DATYX_OPENMETADATA_PORT \
  DATYX_OPENMETADATA_ADMIN_PORT DATYX_SEARCH_PORT DATYX_DEBUG_PORT \
  DATYX_DB_ADMIN_PASSWORD DATYX_DB_PASSWORD OPENMETADATA_DB_PASSWORD API_MODE \
  OIDC_ISSUER OIDC_CLIENT_ID OIDC_EXTRA_AUDIENCES DATYX_MASTER_KEY
unset _root
export DATYX_BIND_HOST="${DATYX_BIND_HOST:-127.0.0.1}"
# API_PORT is the name the repository's start-all.sh and process-compose.yaml
# use for the same port; it wins when set.
export DATYX_API_PORT="${API_PORT:-${DATYX_API_PORT:-9900}}"
export DATYX_DB_PORT="${DATYX_DB_PORT:-9901}"
export DATYX_OPENMETADATA_PORT="${DATYX_OPENMETADATA_PORT:-9902}"
export DATYX_OPENMETADATA_ADMIN_PORT="${DATYX_OPENMETADATA_ADMIN_PORT:-9903}"
export DATYX_SEARCH_PORT="${DATYX_SEARCH_PORT:-9904}"
export DATYX_DEBUG_PORT="${DATYX_DEBUG_PORT:-9905}"
export DATYX_DB_ADMIN_PASSWORD="${DATYX_DB_ADMIN_PASSWORD:-postgres}"
export DATYX_DB_PASSWORD="${DATYX_DB_PASSWORD:-datyx}"
export OPENMETADATA_DB_PASSWORD="${OPENMETADATA_DB_PASSWORD:-openmetadata_password}"
export API_MODE="${API_MODE:-dev}"
# Authentication (see .env.example): off without OIDC_CLIENT_ID. The
# issuer defaults to Google's, as in application.properties: exported
# empty, it would override that default with nothing, and the API would
# not start (a fresh checkout, a codespace, has no .env).
export OIDC_ISSUER="${OIDC_ISSUER:-https://accounts.google.com}"
export OIDC_CLIENT_ID="${OIDC_CLIENT_ID:-}" OIDC_EXTRA_AUDIENCES="${OIDC_EXTRA_AUDIENCES:-}"
# Encryption at rest (see .env.example): empty, the API's development key in dev mode.
export DATYX_MASTER_KEY="${DATYX_MASTER_KEY:-}"
