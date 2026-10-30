#!/usr/bin/env bash
# Stops the demos ./start-all.sh starts: `devbox services stop` (or, in a
# codespace, `process-compose down`: see demos-toolchain.sh) in each
# folder with a devbox.json and a process-compose.yaml, or only in the
# ones named. A demo that isn't running is skipped. The six aityx demos
# have no services of their own: the index (Index/) serves them, so
# stopping it stops them all, and one of them named alone is left to it.
# Demos started with Docker Compose are not touched (docker compose -f
# <demo>/compose.yaml down).
#
#   ./stop-all.sh               # every demo
#   ./stop-all.sh ContactHub    # only these
#   ./stop-aityx.sh             # the aityx group: the index, which serves the six aityx demos
#   ./stop-datyx.sh             # the datyx group: the API, the dashboard, HealthHub and their index
# The groups come from each folder's group.id.txt (aityx or datyx); the
# group scripts run this one with DEMOS_GROUP set.
set -uo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=demos-toolchain.sh
source "$root/demos-toolchain.sh"

# demos [names...]: the demos to act on, as folder names: the ones named,
# else every folder with a devbox.json and a process-compose.yaml, other
# than the demos the index serves (index_serves in demos-toolchain.sh). With
# DEMOS_GROUP set (start-aityx.sh, start-datyx.sh and the stop scripts),
# only the folders whose group.id.txt is that group, and a name outside
# it is an error: the demos start and stop by group.
demos() {
  local name dir
  if [[ $# -gt 0 ]]; then
    for name in "$@"; do
      if [[ -n "${DEMOS_GROUP:-}" && "$(group "$name")" != "$DEMOS_GROUP" ]]; then
        echo "✗ $name is not in the $DEMOS_GROUP group (its group.id.txt says '$(group "$name")')" >&2
        return 1
      fi
      printf '%s\n' "$name"
    done
    return
  fi
  for config in "$root"/*/devbox.json; do
    dir="$(dirname "$config")"
    [[ -f "$dir/process-compose.yaml" ]] || continue
    index_serves "$dir" && continue
    [[ -z "${DEMOS_GROUP:-}" || "$(group "$(basename "$dir")")" == "$DEMOS_GROUP" ]] && basename "$dir"
  done
  return 0
}

# group <demo>: the demo's group, from its group.id.txt (empty without one).
group() {
  [[ -f "$root/$1/group.id.txt" ]] && tr -d '[:space:]' < "$root/$1/group.id.txt"
  return 0
}

failed=0
selected="$(demos "$@")" || exit 1
for demo in $selected; do
  dir="$root/$demo"
  if index_serves "$dir"; then
    echo "· $demo runs no services: the index serves it (stop Index, or ./stop-aityx.sh, for all six)"
    continue
  fi
  if [[ ! -f "$dir/devbox.json" ]]; then
    echo "✗ $demo: no devbox.json in $dir" >&2
    failed=1
    continue
  fi
  services_running "$dir"
  case $? in
    0) ;;
    1) echo "· $demo is not running"; continue ;;
    *) echo "✗ $demo: could not read service status" >&2; failed=1; continue ;;
  esac
  echo "■ $demo: stopping ($DEMOS_TOOLCHAIN services, in $dir)"
  if services_down "$dir"; then
    echo "✅ $demo stopped"
  else
    echo "✗ $demo: stopping its services failed" >&2
    failed=1
  fi
done
exit $failed
