#!/usr/bin/env bash
# Run by post-start.sh each time the codespace starts, and again each time
# VS Code attaches (postAttachCommand), since a visibility set at start
# does not always stick: makes the index page's and each web app's
# forwarded port public, so their URLs open without a GitHub sign-in and
# can be shared for a demo.
#
# devcontainer.json cannot declare a port public; Codespaces only accept it
# through the API, so this asks `gh`, authenticated by the codespace's own
# GITHUB_TOKEN. Only the web ports are made public: the APIs are not
# forwarded, and each app reaches its own through the web server's /api/
# proxy. Anyone with a URL can use that app, and so run its decisions on
# your aityx key.
#
# A port is forwarded only once something listens on it, and the demos
# come up one by one as they compile, so this retries each port in the
# background for a while rather than holding up the start. An organization
# can forbid public ports; then they stay private and the reason is in the
# log.
set -uo pipefail

# The index's port and each demo's web port (the FLUTTER_WEB_PORT default
# in its process-compose.yaml), the same way start-all.sh reads them.
# Its progress goes to startup.log at the root (see startup-log.sh).
# shellcheck source=startup-log.sh
source "$(dirname "${BASH_SOURCE[0]}")/startup-log.sh"
log=$startup_log
#
# The datyx dashboard stays private unless the datyx API requires a
# sign-in (OIDC_CLIENT_ID, in the environment or datyx/.env): without one
# the API lets every request through, and the dashboard's /api/ proxy
# would let anyone with its URL add or delete data sources.
datyx_oidc() {
  local id="${OIDC_CLIENT_ID:-}"
  if [[ -z "$id" && -f "$startup_root/datyx/.env" ]]; then
    id="$(sed -n 's/^OIDC_CLIENT_ID=\([^#[:space:]]*\).*/\1/p' "$startup_root/datyx/.env" | tail -1)"
  fi
  [[ -n "$id" ]]
}
ports=()
for demo in $(startup_demos); do
  if [[ "$demo" == datyx-dashboard ]] && ! datyx_oidc; then
    continue
  fi
  port="$(sed -n 's/.*\${FLUTTER_WEB_PORT:-\([0-9]*\)}.*/\1/p' "$startup_root/$demo/process-compose.yaml" | head -1)"
  [[ -n "$port" ]] && ports+=("$port")
done
# Run on its own (postAttachCommand), not from post-start.sh: log it too.
[[ "${1:-}" == --wait || -n "${STARTUP_LOG_CAPTURED:-}" ]] ||
  startup_capture public-port
pidfile=/tmp/public-port.pid

if [[ -z "${CODESPACE_NAME:-}" ]]; then
  exit 0 # not a codespace: nothing to make public
fi
if ! command -v gh >/dev/null; then
  echo "public-port: gh not found; ports ${ports[*]} stay private" >&2
  exit 0
fi

if [[ "${1:-}" != --wait ]]; then
  if [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
    echo "public-port: already making ports ${ports[*]} public (log: startup.log)"
    exit 0
  fi
  # Detached, so it outlives postStartCommand.
  setsid nohup bash -c 'bash "$1" --wait 2>&1 | while IFS= read -r line; do
    printf "%s [public-port] %s\n" "$(date -u "+%Y-%m-%d %H:%M:%S")" "$line"
  done >>"$0"' "$log" "$0" </dev/null >/dev/null 2>&1 &
  echo $! >"$pidfile"
  echo "public-port: making ports ${ports[*]} public in the background (log: startup.log)"
  exit 0
fi

# Each port on its own, as soon as it is forwarded: up to 20 minutes, the
# first start of six apps on a shared machine. A port made public can fall
# back to private, when the visibility is set before Codespaces forwards
# the port or when it is forwarded again as its app restarts (Mortgage
# Hub's did), so each pass reads what the codespace reports and sets again
# every port that is not public, and the work is done only once every port
# has been reported public on three passes in a row.
public_ports() {
  gh codespace ports -c "$CODESPACE_NAME" --json sourcePort,visibility \
    -q '.[] | select(.visibility == "public") | .sourcePort' 2>/dev/null
}
steady=0
for _ in $(seq 1 120); do
  public=" $(public_ports | tr '\n' ' ') "
  pending=()
  for port in "${ports[@]}"; do
    [[ "$public" == *" $port "* ]] || pending+=("$port")
  done
  if [[ ${#pending[@]} -eq 0 ]]; then
    steady=$((steady + 1))
    if [[ $steady -ge 3 ]]; then
      echo "public-port: ports ${ports[*]} are public"
      exit 0
    fi
  else
    steady=0
    for port in "${pending[@]}"; do
      if gh codespace ports visibility "$port:public" -c "$CODESPACE_NAME"; then
        echo "public-port: port $port set public"
      fi
    done
  fi
  sleep 10
done
echo "public-port: ports ${pending[*]:-} are still not public; set them in the Ports panel"
