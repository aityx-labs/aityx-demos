#!/usr/bin/env bash
# The containers of compose.yaml (PostgreSQL, Elasticsearch, OpenMetadata)
# from `devbox services up` (process-compose.yaml) or by hand:
#   scripts/infra.sh up <service>        docker compose up, attached, with
#                                        its dependencies (postgres, search,
#                                        openmetadata)
#   scripts/infra.sh stop <service>...   docker compose stop
#   scripts/infra.sh healthy <service>   exits 0 when its container is healthy
#   scripts/infra.sh down                stops and removes every container;
#                                        -v drops the data volumes too
# Settings come from the environment, else .env (scripts/env.sh).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=env.sh
source "$root/scripts/env.sh"
cd "$root"

compose() { docker compose -f "$root/compose.yaml" "$@"; }

case "${1:-}" in
  up)
    [[ $# -eq 2 ]] || { echo "usage: $0 up <service>" >&2; exit 2; }
    # Attached, so its log is this process's; dependencies start with it
    # (an already running one is left as it is).
    exec docker compose -f "$root/compose.yaml" up --no-color --attach "$2" "$2"
    ;;
  stop)
    shift
    compose stop "$@"
    ;;
  healthy)
    [[ $# -eq 2 ]] || { echo "usage: $0 healthy <service>" >&2; exit 2; }
    id="$(compose ps -q "$2" 2>/dev/null | head -1)"
    [[ -n "$id" ]] || exit 1
    [[ "$(docker inspect --format '{{.State.Health.Status}}' "$id" 2>/dev/null)" == healthy ]]
    ;;
  down)
    shift
    compose down "$@"
    ;;
  *)
    echo "usage: $0 up <service> | stop <service>... | healthy <service> | down [-v]" >&2
    exit 2
    ;;
esac
