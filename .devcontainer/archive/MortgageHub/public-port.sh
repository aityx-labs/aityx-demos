#!/usr/bin/env bash
# Run by post-start.sh each time the codespace starts, and again each time
# VS Code attaches (postAttachCommand), since a visibility set at start
# does not always stick: makes the web app's forwarded port public, so its
# URL opens without a GitHub sign-in and can be shared for a demo.
#
# devcontainer.json cannot declare a port public; Codespaces only accept it
# through the API, so this asks `gh`, authenticated by the codespace's own
# GITHUB_TOKEN. Only 8880 is made public: the API (8881) is not forwarded,
# and the app reaches it through the web server's /api/ proxy. Anyone with
# the URL can use the app, and so run regulatory checks on your aityx key.
#
# The port is forwarded only once something listens on it, so this retries
# in the background for a while rather than holding up the start. An
# organization can forbid public ports; then the port stays private and
# the reason is in the log.
set -uo pipefail

port="${FLUTTER_WEB_PORT:-8880}"
# Its progress goes to MortgageHub/startup.log (see startup-log.sh).
# shellcheck source=startup-log.sh
source "$(dirname "${BASH_SOURCE[0]}")/startup-log.sh"
log=$startup_log
# Run on its own (postAttachCommand), not from post-start.sh: log it too.
[[ "${1:-}" == --wait || -n "${STARTUP_LOG_CAPTURED:-}" ]] ||
  startup_capture public-port
pidfile=/tmp/public-port.pid

if [[ -z "${CODESPACE_NAME:-}" ]]; then
  exit 0 # not a codespace: nothing to make public
fi
if ! command -v gh >/dev/null; then
  echo "public-port: gh not found; port $port stays private" >&2
  exit 0
fi

if [[ "${1:-}" != --wait ]]; then
  if [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
    echo "public-port: already making port $port public (log: MortgageHub/startup.log)"
    exit 0
  fi
  # Detached, so it outlives postStartCommand.
  setsid nohup bash -c 'bash "$1" --wait 2>&1 | while IFS= read -r line; do
    printf "%s [public-port] %s\n" "$(date -u "+%Y-%m-%d %H:%M:%S")" "$line"
  done >>"$0"' "$log" "$0" </dev/null >/dev/null 2>&1 &
  echo $! >"$pidfile"
  echo "public-port: making port $port public in the background (log: MortgageHub/startup.log)"
  exit 0
fi

for _ in $(seq 1 120); do
  if gh codespace ports visibility "$port:public" -c "$CODESPACE_NAME"; then
    echo "public-port: port $port is public"
    exit 0
  fi
  sleep 10
done
echo "public-port: could not make port $port public; set it in the Ports panel"
