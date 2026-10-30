#!/usr/bin/env bash
# Starts every demo: the six aityx demos, which the aityx index (Index/)
# serves itself on one origin, and the demos that run as services, each
# folder with a devbox.json and a process-compose.yaml (datyx, the datyx
# dashboard, HealthHub, and the two index pages, Index/ for the aityx
# group and datyx-index/ for the datyx group), detached, with `devbox
# services up -b` (or, in a codespace, the image's process-compose: see
# demos-toolchain.sh), then waits until each one answers and prints where
# to open it.
#
# An aityx demo (index_serves in demos-toolchain.sh: a folder of Index/'s
# group with a scripts/build.sh) is a Flutter web app that calls aityx
# from the browser: it has no services. Its scripts/build.sh builds its
# release web build, only when it is missing or older than its sources (a
# minute or two, one demo at a time), and the index serves it at
# http://localhost:8800/<slug>/ (/mortgagehub/, ...), so starting one is
# building what's stale, then starting the index; it is up when its
# /<slug>/ answers on the index's port. ./build-all.sh builds them ahead.
#
# A service demo whose web port already answers (started by hand, or with
# Docker Compose) is left as it is. A folder without a web app (datyx, API
# only: no FLUTTER_WEB_PORT in its process-compose.yaml) is checked on its
# API's /api/health instead.
#
#   ./start-all.sh              # every demo
#   ./start-all.sh ContactHub   # only these (an aityx demo starts the index too)
#   ./start-aityx.sh            # the aityx group: the six aityx demos and their index
#   ./start-datyx.sh            # the datyx group: the API, the dashboard, HealthHub and their index
#   WAIT=0 ./start-all.sh       # start, don't wait
# The groups come from each folder's group.id.txt (aityx or datyx); the
# group scripts run this one with DEMOS_GROUP set.
#
# The aityx key: each user sets their own on the index page, kept in their
# browser. Optionally, AITYX_API_KEY in the environment (a Codespaces
# secret) or in the .env at the root (see .env.example) is a dev key: the
# index server reads it itself and lends it, through its own proxy, to
# whoever opens the demos without a key of their own. The datyx group's
# services that read a key (HealthHub) get a link to the root .env,
# <demo>/.env -> ../.env, and AITYX_API_KEY and AITYX_URL from the
# environment. Watch a service with `devbox services attach -c <demo>`.
# Stop them with ./stop-all.sh.
set -uo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
# How services run: devbox (a laptop) or the dev container image's own
# Flutter and process-compose (DEMOS_TOOLCHAIN=image, a codespace).
# shellcheck source=demos-toolchain.sh
source "$root/demos-toolchain.sh"
# These Codespaces secrets are inherited by each service (HealthHub's API,
# and the index server, which falls back to the root .env itself). Empty
# values leave the .env fallback available for local development.
export AITYX_API_KEY="${AITYX_API_KEY:-}"
export AITYX_URL="${AITYX_URL:-}"

# The root .env, linked from each service folder that reads an aityx key
# (its .env.example names AITYX_API_KEY): the datyx group's. The demos the
# index serves get none: the index server reads the root .env itself. A
# folder's own .env that isn't a link is left as it is.
if [[ -f "$root/.env" ]]; then
  for example in "$root"/*/.env.example; do
    dir="$(dirname "$example")"
    index_serves "$dir" && continue
    grep -q '^AITYX_API_KEY=' "$example" || continue
    [[ -e "$dir/.env" || -L "$dir/.env" ]] || ln -s ../.env "$dir/.env"
  done
fi

# How long to wait for the demos to answer, in seconds (0: don't wait).
WAIT="${WAIT:-600}"

# demos [names...]: the demos to act on, as folder names: the ones named,
# else every folder the index serves and every folder with a devbox.json
# and a process-compose.yaml. With DEMOS_GROUP set (start-aityx.sh,
# start-datyx.sh and the stop scripts), only the folders whose
# group.id.txt is that group, and a name outside it is an error: the
# demos start and stop by group.
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
  for dir in "$root"/*/; do
    dir="${dir%/}"
    index_serves "$dir" ||
      [[ -f "$dir/devbox.json" && -f "$dir/process-compose.yaml" ]] || continue
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

selected="$(demos "$@")" || exit 1
# The demos the index serves, and the service folders; the index is one of
# the services whenever it serves a demo here.
served=()
services=()
for demo in $selected; do
  if index_serves "$root/$demo"; then
    served+=("$demo")
  else
    services+=("$demo")
  fi
done
if [[ ${#served[@]} -gt 0 && " ${services[*]-} " != *" Index "* ]]; then
  services=(Index "${services[@]+"${services[@]}"}")
fi
if [[ ${#served[@]} -gt 0 ]]; then
  echo "· the aityx key: each user sets their own on the index page, kept in their browser"
fi
# A service that reads the key itself (its .env.example names
# AITYX_API_KEY: HealthHub's API) still says when there's none.
for demo in "${services[@]+"${services[@]}"}"; do
  if grep -qs '^AITYX_API_KEY=' "$root/$demo/.env.example" &&
    [[ -z "$AITYX_API_KEY" ]] && ! grep -qs '^AITYX_API_KEY=.' "$root/.env"; then
    echo "AITYX_API_KEY is not set; apps will start, but aityx-backed features won't work." >&2
    break
  fi
done

started=()
failed=0

# The demos the index serves: what's stale built, one after another (a
# Flutter web build uses every core).
ready=()
for demo in "${served[@]+"${served[@]}"}"; do
  dir="$root/$demo"
  lacks="$(image_lacks "$dir")"
  if [[ -n "$lacks" ]]; then
    echo "· $demo: skipped, the image has no $lacks; run it with devbox"
    continue
  fi
  echo "▶ $demo: bash scripts/build.sh (under $DEMOS_TOOLCHAIN, in $dir; only what's stale)"
  if run_build "$dir"; then
    ready+=("$demo")
  else
    echo "✗ $demo: scripts/build.sh failed; see its output above (or ./build-all.sh $demo)" >&2
    failed=1
  fi
done

for demo in "${services[@]+"${services[@]}"}"; do
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

# The index's port, where every demo it serves answers.
index_port=""
[[ ${#ready[@]} -gt 0 ]] && index_port="$(port Index FLUTTER_WEB_PORT)"

# What to wait for: the services started, and the demos the index serves.
waiting=("${started[@]+"${started[@]}"}" "${ready[@]+"${ready[@]}"}")
if [[ ${#waiting[@]} -eq 0 ]]; then
  echo "Nothing started."
  exit $failed
fi

if [[ "$WAIT" -le 0 ]]; then
  echo "Started: ${waiting[*]}. Not waiting; check them with ./start-all.sh later."
  exit $failed
fi

echo "Waiting up to $WAIT s for ${waiting[*]} to answer (a first start builds the app)..."
deadline=$((SECONDS + WAIT))
pending=("${waiting[@]}")
first=1
while [[ ${#pending[@]} -gt 0 && $SECONDS -lt $deadline ]]; do
  # A demo the index already serves answers at once; services take a while.
  [[ $first -eq 1 && ${#ready[@]} -gt 0 ]] || sleep 5
  first=0
  still=()
  for demo in "${pending[@]}"; do
    if index_serves "$root/$demo"; then
      # Served by the index, at its own path.
      url="http://localhost:$index_port/$(index_slug "$demo")/"
      if answers "$url"; then
        echo "✅ $demo is up: $url"
      else
        still+=("$demo")
      fi
      continue
    fi
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
  if index_serves "$root/$demo"; then
    echo "✗ $demo did not answer at http://localhost:$index_port/$(index_slug "$demo")/ within $WAIT s;" \
      "is its build there (./build-all.sh $demo)? see $(services_attach_hint "$root/Index")" >&2
    failed=1
    continue
  fi
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
