#!/usr/bin/env bash
# Serves the datyx index page on http://localhost:${INDEX_PORT:-9907}/ with
# bin/server.dart (Dart from the devbox's Flutter). Runs via
# `devbox services up` (see process-compose.yaml) or `devbox run serve`.
set -euo pipefail

cd "$(dirname "$0")/.."
export INDEX_PORT="${INDEX_PORT:-9907}"
exec dart bin/server.dart
