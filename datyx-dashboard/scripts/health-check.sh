#!/usr/bin/env bash
# Continuous health monitor. It first prints where to open the dashboard
# (the codespace's forwarded URL too, in a codespace) and waits
# HEALTH_CHECK_DELAY seconds (5 by default). Then, every
# HEALTH_CHECK_INTERVAL seconds (15 by default), one line per run: the time,
# then each check as its emoji, a short label and ✅ (ok) / ❌ (failed),
# separated by " · ":
#   🖥 Dash · 🔌 API · 🔀 Proxy
# Dash is the dashboard's /app/; API is the datyx API itself, /api/health/live at
# DATYX_API_URL (the datyx/ folder's services, started separately); Proxy
# is the API's /api/health through the dashboard's origin, the path the
# repository's start-all.sh checks.
# Runs via `devbox services up` (see process-compose.yaml) or standalone.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=env.sh
source "$root/scripts/env.sh"

INTERVAL="${HEALTH_CHECK_INTERVAL:-15}"
DELAY="${HEALTH_CHECK_DELAY:-5}"

# This run's results, one "<emoji> <label> <status emoji>" each.
RESULTS=()

# report "<emoji> <label>" <status emoji>: adds a check's result to this run's line.
report() {
    RESULTS+=("$1 $2")
}

# ok_if "<emoji> <label>" <command...>: ✅ when the command succeeds.
ok_if() {
    local emoji=$1
    shift
    if "$@"; then report "$emoji" ✅; else report "$emoji" ❌; fi
}

# get <timeout> <curl args...>: succeeds on a 2xx answer.
get() {
    local timeout=$1
    shift
    curl -fs -o /dev/null --max-time "$timeout" "$@"
}

check_dash() { ok_if "🖥 Dash" get 5 "http://localhost:${FLUTTER_WEB_PORT}/app/"; }

check_api() { ok_if "🔌 API" get 5 "${DATYX_API_URL}/api/health/live"; }

check_proxy() { ok_if "🔀 Proxy" get 5 "http://localhost:${FLUTTER_WEB_PORT}/api/health"; }

# run_checks: one pass over every check, printed as one line.
run_checks() {
    RESULTS=()
    # Add more services here, one check_* function each.
    check_dash
    check_api
    check_proxy
    local line
    printf -v line ' · %s' "${RESULTS[@]}"
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${line# · }"
}

# print_address: where to open the dashboard, before the first check.
print_address() {
    echo "The datyx dashboard is up. Open it at:"
    echo "  http://localhost:${FLUTTER_WEB_PORT}/app/"
    echo "  (the API it shows: ${DATYX_API_URL}/api/health, from the datyx/ folder's services)"
    # A codespace forwards the port to its own URL; the Ports panel has it too.
    if [[ -n "${CODESPACE_NAME:-}" && -n "${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-}" ]]; then
        echo "  https://$CODESPACE_NAME-$FLUTTER_WEB_PORT.$GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN/app/"
    fi
    echo "Health checks start in $DELAY s, then every $INTERVAL s."
}

# Sourced (e.g. to call run_checks once): define the functions only.
[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0

print_address
sleep "$DELAY"
while true; do
    run_checks
    sleep "$INTERVAL"
done
