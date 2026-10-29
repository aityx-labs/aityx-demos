#!/usr/bin/env bash
# Starts every demo that runs as services: each folder with a devbox.json
# and a process-compose.yaml (Mortgage Hub, Contact Hub, ..., datyx and
# the two index pages, Index/ for the aityx group and datyx-index/ for
# the datyx group), detached, with `devbox services up -b` (or, in a
# codespace, the image's process-compose: see demos-toolchain.sh), then
# waits until each one's web app and
# API answer and prints where to open them. A demo whose web port already
# answers (started by hand, or with Docker Compose) is left as it is. A
# folder without a web app (datyx, API only: no FLUTTER_WEB_PORT in its
# process-compose.yaml) is checked on its API's /api/health instead.
#
#   ./start-all.sh              # every demo
#   ./start-all.sh ContactHub   # only these
#   ./start-aityx.sh            # the aityx group: the six aityx demos and their index
#   ./start-datyx.sh            # the datyx group: the API, the dashboard, HealthHub and their index
#   WAIT=0 ./start-all.sh       # start, don't wait
# The groups come from each folder's group.id.txt (aityx or datyx); the
# group scripts run this one with DEMOS_GROUP set.
#
# The aityx settings go in the .env at the root (see .env.example):
# AITYX_API_KEY, the key, and AITYX_URL, the endpoint (https://api.aityx.ai
# unless set; a stage key needs https://api-stage.aityx.ai). Each demo that
# calls aityx, and the index, gets a link to it, <demo>/.env -> ../.env, so
# process-compose and the demo's scripts load it. Without a key the app
# runs, but it can't call aityx. Each demo serves its app's
# release build and a compiled API (see <demo>/scripts/build.sh); a demo
# whose build is missing or older than its sources builds it first, a
# minute or two, one demo at a time. ./build-all.sh does that ahead, with
# each build's output. Watch one with `devbox services attach -c <demo>`.
# Stop them with ./stop-all.sh.
set -uo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
# How services run: devbox (a laptop) or the dev container image's own
# Flutter and process-compose (DEMOS_TOOLCHAIN=image, a codespace).
# shellcheck source=demos-toolchain.sh
source "$root/demos-toolchain.sh"
# These Codespaces secrets are inherited by each API process. Empty values
# leave the .env fallback available for local development.
export AITYX_API_KEY="${AITYX_API_KEY:-}"
export AITYX_URL="${AITYX_URL:-}"

# The root .env, linked from each folder that reads an aityx key (its
# .env.example names AITYX_API_KEY) and from the index. A folder's own .env
# that isn't a link is left as it is.
if [[ -f "$root/.env" ]]; then
  for example in "$root"/*/.env.example; do
    dir="$(dirname "$example")"
    grep -q '^AITYX_API_KEY=' "$example" || continue
    [[ -e "$dir/.env" || -L "$dir/.env" ]] || ln -s ../.env "$dir/.env"
  done
  [[ -e "$root/Index/.env" || -L "$root/Index/.env" ]] || ln -s ../.env "$root/Index/.env"
fi

if [[ -z "$AITYX_API_KEY" ]] && ! grep -qs '^AITYX_API_KEY=.' "$root/.env"; then
  echo "AITYX_API_KEY is not set; apps will start, but aityx-backed features won't work." >&2
fi

# How long to wait for the demos to answer, in seconds (0: don't wait).
WAIT="${WAIT:-600}"

# demos [names...]: the demos to act on, as folder names: the ones named,
# else every folder with a devbox.json and a process-compose.yaml. With
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
    [[ -z "${DEMOS_GROUP:-}" || "$(group "$(basename "$dir")")" == "$DEMOS_GROUP" ]] && basename "$dir"
  done
  return 0
}

# group <demo>: the demo's group, from its group.id.txt (empty without one).
group() {
  [[ -f "$root/$1/group.id.txt" ]] && tr -d '[:space:]' < "$root/$1/group.id.txt"
  return 0
}

# port <demo> <VARIABLE>: the environment override, else the demo's
# process-compose.yaml default for FLUTTER_WEB_PORT or API_PORT.
port() {
  local variable="$2"
  local override="${!variable:-}"
  if [[ -n "$override" ]]; then
    printf '%s\n' "$override"
    return
  fi
  sed -n "s/.*\${$2:-\([0-9]*\)}.*/\1/p" "$root/$1/process-compose.yaml" | head -1
}

# answers <url>: whether the URL answers 2xx.
answers() {
  curl -fs -o /dev/null --max-time 3 "$1"
}

started=()
failed=0
selected="$(demos "$@")" || exit 1
for demo in $selected; do
  dir="$root/$demo"
  if [[ ! -f "$dir/devbox.json" || ! -f "$dir/process-compose.yaml" ]]; then
    echo "✗ $demo: no devbox.json and process-compose.yaml in $dir" >&2
    failed=1
    continue
  fi
  lacks="$(image_lacks "$dir")"
  if [[ -n "$lacks" ]]; then
    echo "· $demo: skipped, the image has no $lacks; run it with devbox"
    continue
  fi
  web="$(port "$demo" FLUTTER_WEB_PORT)"
  api="$(port "$demo" API_PORT)"
  if [[ -n "$web" ]] && answers "http://localhost:$web/app/"; then
    echo "· $demo already answers at http://localhost:$web/app/: left as it is"
    continue
  elif [[ -z "$web" && -n "$api" ]] && answers "http://localhost:$api/api/health"; then
    echo "· $demo already answers at http://localhost:$api/api/health: left as it is"
    continue
  fi
  echo "▶ $demo: starting ($DEMOS_TOOLCHAIN services, in $dir)"
  if services_up "$dir"; then
    started+=("$demo")
  else
    echo "✗ $demo: starting its services failed; see $(services_attach_hint "$dir")" >&2
    failed=1
  fi
done

if [[ ${#started[@]} -eq 0 ]]; then
  echo "Nothing started."
  exit $failed
fi

if [[ "$WAIT" -le 0 ]]; then
  echo "Started: ${started[*]}. Not waiting; check them with ./start-all.sh later."
  exit $failed
fi

echo "Waiting up to $WAIT s for ${started[*]} to answer (a first start builds the app)..."
deadline=$((SECONDS + WAIT))
pending=("${started[@]}")
while [[ ${#pending[@]} -gt 0 && $SECONDS -lt $deadline ]]; do
  sleep 5
  still=()
  for demo in "${pending[@]}"; do
    web="$(port "$demo" FLUTTER_WEB_PORT)"
    api="$(port "$demo" API_PORT)"
    if [[ -z "$web" ]]; then
      # No web app: the API itself.
      if answers "http://localhost:$api/api/health"; then
        echo "✅ $demo is up: http://localhost:$api/api/health (API only)"
      else
        still+=("$demo")
      fi
    # The API through the app's origin: the dev server proxies /api/ to it.
    elif answers "http://localhost:$web/app/" && answers "http://localhost:$web/api/health"; then
      echo "✅ $demo is up: http://localhost:$web/app/ (API: http://localhost:$api/api/health)"
    else
      still+=("$demo")
    fi
  done
  pending=("${still[@]+"${still[@]}"}")
done

for demo in "${pending[@]+"${pending[@]}"}"; do
  web="$(port "$demo" FLUTTER_WEB_PORT)"
  if [[ -n "$web" ]]; then
    where="http://localhost:$web/app/"
  else
    where="http://localhost:$(port "$demo" API_PORT)/api/health"
  fi
  echo "✗ $demo did not answer at $where within $WAIT s; see $(services_attach_hint "$root/$demo")" >&2
  failed=1
done

# Each group's index page, with a card per demo: Index/ for the aityx
# demos, datyx-index/ for the datyx group; printed when it answers.
for pair in "Index:The six aityx demos" "datyx-index:The datyx group"; do
  folder="${pair%%:*}"
  index="$(port "$folder" FLUTTER_WEB_PORT 2>/dev/null)"
  if [[ -n "$index" ]] && answers "http://localhost:$index/"; then
    echo "🏠 ${pair#*:}, on one page: http://localhost:$index/"
  fi
done
exit $failed
