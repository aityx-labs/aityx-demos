#!/usr/bin/env bash
# Runs each time the container starts (postStartCommand), after
# post-create.sh on the first start: starts Mortgage Hub's services and,
# in a codespace, makes the web app's port public, so the app opens from
# the Ports panel (or the browser tab Codespaces opens) with nothing to run.
#
# `devbox services up -b` runs process-compose in the background: the web
# app on 8880 and the API on 8881, as in MortgageHub/process-compose.yaml.
# Its first start compiles the app, which takes a minute or two. Watch it
# with `devbox services attach`, stop it with `devbox services stop`.
#
# Everything is logged to MortgageHub/startup.log (see startup-log.sh),
# including a watcher that records when the web app and the API answer,
# or, if they don't within 15 minutes, the services' state.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
app="$(cd "$here/../.." && pwd)/MortgageHub"
# shellcheck source=startup-log.sh
source "$here/startup-log.sh"

# --watch: the detached watcher started below.
if [[ "${1:-}" == --watch ]]; then
  cd "$app" || exit 1
  web="http://localhost:${FLUTTER_WEB_PORT:-8880}/app/"
  api="http://localhost:${API_PORT:-8881}/api/health"
  started=$SECONDS
  last=""
  while ((SECONDS - started < 900)); do
    state="web $(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$web")"
    state+=", api $(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$api")"
    pgrep -f process-compose >/dev/null && state+=", process-compose running" ||
      state+=", process-compose NOT running"
    [[ "$state" != "$last" ]] && slog "[watch] $state"
    last=$state
    if [[ "$state" == "web 200, api 200,"* ]]; then
      slog "[watch] ready after $((SECONDS - started)) s: open port 8880 at /app/"
      exit 0
    fi
    sleep 5
  done
  slog "[watch] not ready after 15 minutes; the services' state:"
  devbox services ls 2>&1 | while IFS= read -r line; do slog "[watch]   $line"; done
  for f in .devbox/compose.log /tmp/process-compose-"$(id -un)".log; do
    [[ -f "$f" ]] || continue
    slog "[watch] last lines of $f:"
    tail -n 60 "$f" | while IFS= read -r line; do slog "[watch]   $line"; done
  done
  exit 1
fi

startup_capture post-start
echo "===== post-start: $(date -u '+%Y-%m-%d %H:%M:%S') UTC"
startup_facts

cd "$app" || { echo "post-start: cannot find $app" >&2; exit 1; }

if ! command -v devbox >/dev/null || [[ ! -d .devbox ]]; then
  echo "post-start: devbox is not installed here yet (did post-create.sh"
  echo "post-start: fail? see its lines above); start the app with:"
  echo "post-start:   cd MortgageHub && devbox services up"
else
  # Detached, so they outlive postStartCommand. The services' own output
  # goes to the log too.
  setsid nohup bash -c 'devbox services up -b 2>&1 |
    while IFS= read -r line; do
      printf "%s [services] %s\n" "$(date -u "+%Y-%m-%d %H:%M:%S")" "$line"
    done >>"$0"' "$startup_log" </dev/null >/dev/null 2>&1 &
  setsid nohup bash "$here/post-start.sh" --watch </dev/null >/dev/null 2>&1 &
  echo "post-start: starting the services in the background; progress in"
  echo "post-start: MortgageHub/startup.log"
fi

bash "$here/public-port.sh"
