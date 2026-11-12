#!/usr/bin/env bash
# Serves tatyx on http://localhost:${FLUTTER_WEB_PORT:-9710}/tatyx/: the
# server (tatyx_server/server.mjs) serves the app's release build under
# /tatyx/, its health check under /api/, and aityx for the app under
# /aityx/ (the relay for the player's own key). Builds what's stale first
# (scripts/build.sh). Runs via `devbox services up` (see
# process-compose.yaml) or `devbox run serve`. The settings come from the
# environment, else the repo's .env (scripts/env.sh): the aityx key
# reaches the server's environment only, never a command line, and never
# the web app.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=env.sh
source "$root/scripts/env.sh"
bash "$root/scripts/build.sh"
export WEB_ROOT="$root/tatyx_app/dist"
exec node "$root/tatyx_server/server.mjs"
