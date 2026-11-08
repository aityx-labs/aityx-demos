#!/usr/bin/env bash
# Serves the multyx index page on http://localhost:${INDEX_PORT:-9700}/ with
# bin/server.mjs (Node from the devbox). Runs via `devbox services up`
# (see process-compose.yaml) or `devbox run serve`.
set -euo pipefail

cd "$(dirname "$0")/.."
export INDEX_PORT="${INDEX_PORT:-9700}"
exec node bin/server.mjs
