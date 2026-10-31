#!/usr/bin/env bash
# Runs the API (healthhub_api/) on http://localhost:${API_PORT:-9802}:
# bin/server.dart compiled to a native executable (scripts/build.sh, only
# when the API changed), so it starts at once and stays small.
# Runs via `devbox services up` (see process-compose.yaml) or `devbox run api`.
# The settings come from the environment, else the repo's .env (see
# .env.example and scripts/env.sh): the aityx key and URL, the
# database's port and password, Kafka's REST proxy and the mode. They're
# exported to the server's own environment only: never on a command line,
# and never to the Flutter app.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=env.sh
source "$root/scripts/env.sh"
export ALLOWED_ORIGINS="${ALLOWED_ORIGINS:-http://localhost:${FLUTTER_WEB_PORT},http://127.0.0.1:${FLUTTER_WEB_PORT}}"
# PostgreSQL, the postgres service of compose.yaml, published on the host.
export HEALTHHUB_DB_HOST="${HEALTHHUB_DB_HOST:-127.0.0.1}"
export HEALTHHUB_DB_NAME="${HEALTHHUB_DB_NAME:-healthhub}"
export HEALTHHUB_DB_USER="${HEALTHHUB_DB_USER:-healthhub}"
export HEALTHHUB_DB_PORT HEALTHHUB_DB_PASSWORD
export OIDC_ISSUER OIDC_CLIENT_ID DATYX_API_URL
# Kafka's REST proxy, published on the host, and the people simulation
# (dev mode only).
export HEALTHHUB_MODE HEALTHHUB_KAFKA_REST_URL HEALTHHUB_SIM_PEOPLE \
  HEALTHHUB_SIM_TURN_MS HEALTHHUB_SIM_MINUTES_PER_TURN

bash "$root/scripts/build.sh" api
exec "$root/healthhub_api/build/server"
