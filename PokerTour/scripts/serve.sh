#!/usr/bin/env bash
# Serves Poker Tour on http://localhost:${FLUTTER_WEB_PORT:-9810}/pokertour/: the
# server (pokertour_api/bin/server.dart, compiled to a native executable
# by scripts/build.sh, only when it changed) serves the app's release web
# build under /pokertour/, its API under /api/, and plays the leaderboard's
# tournaments. Runs via `devbox services up` (see process-compose.yaml) or
# `devbox run serve`. The settings come from the environment, else the
# repo's .env (scripts/env.sh): the aityx key reaches the server's
# environment only, never a command line, and never the web app.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=env.sh
source "$root/scripts/env.sh"
bash "$root/scripts/build.sh"
export WEB_ROOT="$root/pokertour_app/build/web"
export POKERTOUR_MODELS="$root/pokertour_app/assets/models"
cd "$root/pokertour_api"
exec "$root/pokertour_api/build/server"
