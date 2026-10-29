# Sourced by the scripts: the settings from the environment, else from this
# folder's .env (see .env.example), else their defaults.

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
load_env DATYX_BIND_HOST FLUTTER_WEB_PORT API_PORT DATYX_API_URL WEB_MODE
unset _root
export DATYX_BIND_HOST="${DATYX_BIND_HOST:-127.0.0.1}"
export FLUTTER_WEB_PORT="${FLUTTER_WEB_PORT:-9906}"
export API_PORT="${API_PORT:-9900}"
# 127.0.0.1, not localhost: Dart binds "localhost" to IPv6 [::1] only.
export DATYX_API_URL="${DATYX_API_URL:-http://127.0.0.1:${API_PORT}}"
export WEB_MODE="${WEB_MODE:-release}"
