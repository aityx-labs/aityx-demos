#!/usr/bin/env bash
# The infrastructure containers of compose.yaml (postgres, kafka and
# kafka-rest) from `devbox services up` (process-compose.yaml), `devbox run
# db`, `devbox run kafka` (kafka-rest, which starts kafka first), or by
# hand:
#   scripts/infra.sh up postgres         docker compose up, attached
#   scripts/infra.sh stop postgres       docker compose stop
#   scripts/infra.sh healthy postgres    exits 0 when its container is healthy
#   scripts/infra.sh down                stops and removes the containers;
#                                        -v drops the data volumes too
#   scripts/infra.sh psql                psql in the container, on the
#                                        healthhub database
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
    # Attached, so its log is this process's (an already running
    # container is left as it is).
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
  psql)
    shift
    exec docker compose -f "$root/compose.yaml" exec postgres psql -U healthhub -d healthhub "$@"
    ;;
  *)
    echo "usage: $0 up <service> | stop <service>... | healthy <service> | down [-v] | psql" >&2
    exit 2
    ;;
esac
