#!/usr/bin/env bash
# Continuous health monitor: every HEALTH_CHECK_INTERVAL seconds (15 by
# default), one line per run: the time, then each check as its emoji, a
# short label and ✅ (ok) / ❌ (failed), separated by " · ":
#   🌐 Web · 🔌 API · 🤖 aityx (the API's key: ✅ set, ⚪ not set)
# Runs via `devbox services up` (see process-compose.yaml) or standalone.
set -uo pipefail

INTERVAL="${HEALTH_CHECK_INTERVAL:-15}"

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

check_web() { ok_if "🌐 Web" get 5 "http://localhost:${FLUTTER_WEB_PORT:-8880}/app/"; }

# The API's /api/health: {"ok":true,"aityx":<whether its key is set>}.
check_api() {
    local body
    body="$(curl -fs --max-time 5 "http://localhost:${API_PORT:-8881}/api/health")"
    if [[ "$body" != *'"ok":true'* ]]; then
        report "🔌 API" ❌
        report "🤖 aityx" ❌
        return
    fi
    report "🔌 API" ✅
    if [[ "$body" == *'"aityx":true'* ]]; then report "🤖 aityx" ✅; else report "🤖 aityx" ⚪; fi
}

# run_checks: one pass over every check, printed as one line.
run_checks() {
    RESULTS=()
    # Add more services here, one check_* function each.
    check_web
    check_api
    local line
    printf -v line ' · %s' "${RESULTS[@]}"
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${line# · }"
}

# Sourced (e.g. to call run_checks once): define the functions only.
[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0

while true; do
    run_checks
    sleep "$INTERVAL"
done
