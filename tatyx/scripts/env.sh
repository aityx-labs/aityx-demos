# Sourced by the scripts: the settings from the environment, else from
# the repo's .env (see .env.example), else their defaults. Secrets are
# exported to the server's environment only: never put on a command line.

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
load_env AITYX_API_KEY AITYX_URL FLUTTER_WEB_PORT TATYX_BIND_HOST
# _env_file stays: deploy/deploy.sh calls load_env for its own settings.
unset _root
# One port: the app, its API and the aityx relay share it. FLUTTER_WEB_PORT
# is the name every demo's start-all.sh reads, Flutter or not.
export FLUTTER_WEB_PORT="${FLUTTER_WEB_PORT:-9710}"
export API_PORT="${API_PORT:-$FLUTTER_WEB_PORT}"
export TATYX_PORT="$FLUTTER_WEB_PORT"
export TATYX_BIND_HOST="${TATYX_BIND_HOST:-127.0.0.1}"
export AITYX_API_KEY="${AITYX_API_KEY:-}" AITYX_URL="${AITYX_URL:-}"
