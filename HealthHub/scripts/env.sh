# Sourced by the scripts: the settings from the environment, else from the
# repo's .env (see .env.example), else their defaults. Secrets are exported
# to the processes' environment only: never put on a command line.

_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# This folder's .env, else the repository's: a fresh checkout has no link
# until start-all.sh makes it.
_env_file="$_root/.env"
[[ -f "$_env_file" ]] || _env_file="$_root/../.env"
# load_env <NAME>...: exports each variable from .env when it isn't set.
load_env() {
  local name value
  for name in "$@"; do
    if [[ -z "${!name:-}" && -f "$_env_file" ]]; then
      value="$(sed -n "s/^${name}=//p" "$_env_file" | tail -1)"
      value="${value%%#*}"
      value="${value%"${value##*[![:space:]]}"}"
      [[ -n "$value" ]] && export "$name=$value"
    fi
  done
  return 0
}
load_env AITYX_API_KEY AITYX_URL FLUTTER_WEB_PORT API_PORT HEALTHHUB_BIND_HOST \
  HEALTHHUB_DB_PORT HEALTHHUB_DB_ADMIN_PASSWORD HEALTHHUB_DB_PASSWORD WEB_MODE \
  OIDC_ISSUER OIDC_CLIENT_ID DATYX_API_URL HEALTHHUB_KAFKA_PORT \
  HEALTHHUB_KAFKA_REST_PORT HEALTHHUB_KAFKA_REST_URL HEALTHHUB_MODE \
  HEALTHHUB_SIM_PEOPLE HEALTHHUB_SIM_TURN_MS HEALTHHUB_SIM_MINUTES_PER_TURN
unset _root _env_file
export FLUTTER_WEB_PORT="${FLUTTER_WEB_PORT:-9801}"
export API_PORT="${API_PORT:-9802}"
export HEALTHHUB_BIND_HOST="${HEALTHHUB_BIND_HOST:-127.0.0.1}"
export HEALTHHUB_DB_PORT="${HEALTHHUB_DB_PORT:-9803}"
export HEALTHHUB_DB_ADMIN_PASSWORD="${HEALTHHUB_DB_ADMIN_PASSWORD:-postgres}"
export HEALTHHUB_DB_PASSWORD="${HEALTHHUB_DB_PASSWORD:-healthhub}"
export WEB_MODE="${WEB_MODE:-release}"
# Authentication and the datyx API (see .env.example): an empty client id is off.
export OIDC_ISSUER="${OIDC_ISSUER:-}" OIDC_CLIENT_ID="${OIDC_CLIENT_ID:-}"
export DATYX_API_URL="${DATYX_API_URL:-http://127.0.0.1:9900}"
# Kafka and its REST proxy, published by compose.yaml, and the people
# simulation, which runs in dev mode only (see .env.example).
export HEALTHHUB_KAFKA_PORT="${HEALTHHUB_KAFKA_PORT:-9804}"
export HEALTHHUB_KAFKA_REST_PORT="${HEALTHHUB_KAFKA_REST_PORT:-9805}"
export HEALTHHUB_KAFKA_REST_URL="${HEALTHHUB_KAFKA_REST_URL:-http://127.0.0.1:${HEALTHHUB_KAFKA_REST_PORT}}"
export HEALTHHUB_MODE="${HEALTHHUB_MODE:-dev}"
export HEALTHHUB_SIM_PEOPLE="${HEALTHHUB_SIM_PEOPLE:-10}"
export HEALTHHUB_SIM_TURN_MS="${HEALTHHUB_SIM_TURN_MS:-1000}"
export HEALTHHUB_SIM_MINUTES_PER_TURN="${HEALTHHUB_SIM_MINUTES_PER_TURN:-60}"
