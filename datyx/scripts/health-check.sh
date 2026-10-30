#!/usr/bin/env bash
# Continuous health monitor. It first prints where to open the API and
# OpenMetadata and waits HEALTH_CHECK_DELAY seconds (5 by default). Then,
# every HEALTH_CHECK_INTERVAL seconds (15 by default), one line per run:
# the time, then each check as its emoji, a short label and ✅ (ok) / ❌
# (failed), separated by " · ":
#   🔌 API · 🐘 Postgres · 🗂 OpenMetadata · 🔎 Search
# API comes from /api/health/live (its own check), Postgres from the API's /api/health (its
# datasource check), OpenMetadata from its admin /healthcheck and Search
# from Elasticsearch's cluster health. The dashboard has its own monitor,
# in datyx-dashboard/.
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

check_api() { ok_if "🔌 API" get 5 "http://localhost:${DATYX_API_PORT}/api/health/live"; }

# The API's /api/health, pretty-printed: {"status": "UP", "checks": [{"name":
# "Database connections health check", "status": "UP", ...}]}. Compared
# without its whitespace.
check_postgres() {
    local body
    body="$(curl -s --max-time 5 "http://localhost:${DATYX_API_PORT}/api/health" | tr -d ' \n\r\t')"
    if [[ "$body" == *'"name":"Databaseconnectionshealthcheck","status":"UP"'* ]]; then
        report "🐘 Postgres" ✅
    else
        report "🐘 Postgres" ❌
    fi
}

check_openmetadata() { ok_if "🗂 OpenMetadata" get 5 "http://localhost:${DATYX_OPENMETADATA_ADMIN_PORT}/healthcheck"; }

check_search() {
    local body
    body="$(curl -fs --max-time 5 "http://localhost:${DATYX_SEARCH_PORT}/_cluster/health")"
    if [[ "$body" == *'"status":"green"'* || "$body" == *'"status":"yellow"'* ]]; then
        report "🔎 Search" ✅
    else
        report "🔎 Search" ❌
    fi
}

# run_checks: one pass over every check, printed as one line.
run_checks() {
    RESULTS=()
    # Add more services here, one check_* function each.
    check_api
    check_postgres
    check_openmetadata
    check_search
    local line
    printf -v line ' · %s' "${RESULTS[@]}"
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${line# · }"
}

# print_address: where to open things, before the first check.
print_address() {
    echo "datyx is up."
    echo "  API:          http://localhost:${DATYX_API_PORT}/api/health  (Swagger UI: /q/swagger-ui)"
    echo "  OpenMetadata: http://localhost:${DATYX_OPENMETADATA_PORT}/  (admin@open-metadata.org / admin)"
    echo "  PostgreSQL:   localhost:${DATYX_DB_PORT}  (datyx / openmetadata_db)"
    echo "  Search:       http://localhost:${DATYX_SEARCH_PORT}/"
    # A codespace forwards the ports to its own URLs; the Ports panel has them too.
    if [[ -n "${CODESPACE_NAME:-}" && -n "${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-}" ]]; then
        echo "  https://$CODESPACE_NAME-$DATYX_API_PORT.$GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN/api/health"
        echo "  https://$CODESPACE_NAME-$DATYX_OPENMETADATA_PORT.$GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN/"
    fi
    echo "  The dashboard is the datyx-dashboard/ folder's service (http://localhost:9906/app/ when up)."
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
