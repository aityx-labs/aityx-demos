# Sourced by the scripts: the settings from the environment, else from the
# repo's .env (see .env.example), else their defaults. Secrets are exported
# to the processes' environment only: never put on a command line.

_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# load_env <NAME>...: exports each variable from .env when it isn't set.
load_env() {
  load_env_from "$_root/.env" "$@"
}
# load_env_from <file> <NAME>...: the same, from another file.
load_env_from() {
  local file="$1" name value
  shift
  for name in "$@"; do
    if [[ -z "${!name:-}" && -f "$file" ]]; then
      value="$(sed -n "s/^${name}=//p" "$file" | tail -1)"
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
  OIDC_ISSUER OIDC_CLIENT_ID OIDC_EXTRA_AUDIENCES DATYX_MASTER_KEY \
  DATYX_OPENMETADATA_TOKEN DATYX_OPENMETADATA_EMAIL DATYX_OPENMETADATA_PASSWORD \
  DATYX_OPENMETADATA_CALLBACK_URL DATYX_OPENMETADATA_WEBHOOK_SECRET \
  DATYX_OPENMETADATA_PUBLIC_URL \
  DATYX_HEALTHHUB_DB_HOST DATYX_HEALTHHUB_DB_PORT DATYX_HEALTHHUB_DB_PASSWORD DATYX_HEALTHHUB_KAFKA \
  AITYX_API_KEY AITYX_URL DATYX_AITYX_URL DATYX_SERVICE_TOKEN DATYX_AITYX_SHARE_SERVICE_CALLS
# The aityx key and the service token, shared with HealthHub: else from the
# repository root's .env, the one HealthHub reads (see .env.example).
load_env_from "$_root/../.env" AITYX_API_KEY AITYX_URL DATYX_SERVICE_TOKEN
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
# aityx (see .env.example): datyx's key, empty for none (the gateway
# answers 503); its URL, else AITYX_URL, else the API's default; the token
# services present, empty to refuse them.
export AITYX_API_KEY="${AITYX_API_KEY:-}" DATYX_SERVICE_TOKEN="${DATYX_SERVICE_TOKEN:-}"
[[ -z "${DATYX_AITYX_URL:-}" && -n "${AITYX_URL:-}" ]] && export DATYX_AITYX_URL="$AITYX_URL"
[[ -n "${DATYX_AITYX_SHARE_SERVICE_CALLS:-}" ]] && export DATYX_AITYX_SHARE_SERVICE_CALLS
true
