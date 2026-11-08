# Sourced by the scripts: the settings from the environment, else from the
# repo's .env (see .env.example), else their defaults. Secrets are exported
# to the server's environment only: never put on a command line.

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
load_env AITYX_API_KEY AITYX_URL AITYX_PROD_URL AITYX_PROD_API_KEY \
  POKERTOUR_LEADERBOARD_KEY POKERTOUR_PROD_LEADERBOARD_KEY FLUTTER_WEB_PORT API_PORT POKERTOUR_BIND_HOST \
  OIDC_ISSUER OIDC_CLIENT_ID POKERTOUR_OIDC_CLIENT_ID POKERTOUR_ALLOWED_DOMAINS POKERTOUR_ADMIN_DOMAINS \
  POKERTOUR_RUN POKERTOUR_SCHEDULE_HOURS POKERTOUR_MAX_HANDS POKERTOUR_MAX_ENTRIES POKERTOUR_AWS_ENDPOINT POKERTOUR_FLOCI_PORT \
  POKERTOUR_STACK POKERTOUR_EXTRA_ORIGINS LAMBDA_ARCH
unset _root _env_file
# Poker Tour's own Google client, when the shared .env has one: the
# repository's root .env also serves HealthHub, whose OIDC_CLIENT_ID is
# its own project's.
if [[ -n "${POKERTOUR_OIDC_CLIENT_ID:-}" ]]; then
  export OIDC_CLIENT_ID="$POKERTOUR_OIDC_CLIENT_ID"
fi
export FLUTTER_WEB_PORT="${FLUTTER_WEB_PORT:-9810}"
# One port: the app and its API share it.
export API_PORT="${API_PORT:-$FLUTTER_WEB_PORT}"
export POKERTOUR_BIND_HOST="${POKERTOUR_BIND_HOST:-127.0.0.1}"
export AITYX_API_KEY="${AITYX_API_KEY:-}" AITYX_URL="${AITYX_URL:-}"
export POKERTOUR_LEADERBOARD_KEY="${POKERTOUR_LEADERBOARD_KEY:-}"
export OIDC_ISSUER="${OIDC_ISSUER:-}" OIDC_CLIENT_ID="${OIDC_CLIENT_ID:-}"
export POKERTOUR_ALLOWED_DOMAINS="${POKERTOUR_ALLOWED_DOMAINS:-}" POKERTOUR_ADMIN_DOMAINS="${POKERTOUR_ADMIN_DOMAINS:-}"
export POKERTOUR_RUN="${POKERTOUR_RUN:-}" POKERTOUR_SCHEDULE_HOURS="${POKERTOUR_SCHEDULE_HOURS:-}"
export POKERTOUR_MAX_HANDS="${POKERTOUR_MAX_HANDS:-}" POKERTOUR_MAX_ENTRIES="${POKERTOUR_MAX_ENTRIES:-}"
export POKERTOUR_AWS_ENDPOINT="${POKERTOUR_AWS_ENDPOINT:-http://localhost:${POKERTOUR_FLOCI_PORT:-9811}}"
