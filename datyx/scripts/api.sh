#!/usr/bin/env bash
# Runs the datyx API (datyx-api/) on http://localhost:${DATYX_API_PORT:-9900},
# on the devbox's GraalVM, by API_MODE (dev unless set; see .env.example):
#   dev     ./mvnw quarkus:dev: live reload, the debugger on DATYX_DEBUG_PORT
#   jar     the packaged API (scripts/build.sh jar, only when it changed)
#   native  the native executable (scripts/build.sh native, when it changed)
# Runs via `devbox services up` (see process-compose.yaml) or `devbox run api`.
# The settings come from the environment, else .env (scripts/env.sh), and
# reach the API through its environment only: never on a command line.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=env.sh
source "$root/scripts/env.sh"
# shellcheck source=version.sh
source "$root/scripts/version.sh"

# What the API reads (datyx-api/src/main/resources/application.properties).
export DATYX_API_PORT DATYX_BIND_HOST DATYX_DB_PASSWORD
export OIDC_ISSUER OIDC_CLIENT_ID OIDC_EXTRA_AUDIENCES DATYX_MASTER_KEY
export DATYX_DB_USER="${DATYX_DB_USER:-datyx}"
export DATYX_DB_URL="${DATYX_DB_URL:-jdbc:postgresql://localhost:${DATYX_DB_PORT}/datyx}"
export DATYX_OPENMETADATA_URL="${DATYX_OPENMETADATA_URL:-http://localhost:${DATYX_OPENMETADATA_PORT}}"
# Set only where they differ from the API's defaults (see .env.example):
# where a browser opens OpenMetadata, when it isn't the URL above, which
# /api/health reports; and where the development data's HealthHub is,
# when it isn't on this host at the ports it publishes (localhost:9803
# its PostgreSQL, localhost:9804 its Kafka). Unset or empty, they stay
# out of the API's environment and its defaults hold.
for name in DATYX_OPENMETADATA_PUBLIC_URL DATYX_HEALTHHUB_DB_HOST DATYX_HEALTHHUB_DB_PORT \
  DATYX_HEALTHHUB_DB_PASSWORD DATYX_HEALTHHUB_KAFKA; do
  if [[ -n "${!name:-}" ]]; then export "${name?}"; else unset "$name"; fi
done
unset name
# The catalogue's sign-in to OpenMetadata: a bot token when set, else the
# stack's built-in admin (compose.yaml), in every mode.
export DATYX_OPENMETADATA_TOKEN="${DATYX_OPENMETADATA_TOKEN:-}"
export DATYX_OPENMETADATA_EMAIL="${DATYX_OPENMETADATA_EMAIL:-admin@open-metadata.org}"
export DATYX_OPENMETADATA_PASSWORD="${DATYX_OPENMETADATA_PASSWORD:-admin}"
# Where OpenMetadata (in Docker) posts tables' changes back to the API on
# this host, in every mode; and the secret it signs with (drawn at start
# when empty).
export DATYX_OPENMETADATA_CALLBACK_URL="${DATYX_OPENMETADATA_CALLBACK_URL:-http://host.docker.internal:${DATYX_API_PORT}/api/catalog/openmetadata-events}"
export DATYX_OPENMETADATA_WEBHOOK_SECRET="${DATYX_OPENMETADATA_WEBHOOK_SECRET:-}"
# aityx (specs/aityx.md): datyx's key and the services' token, both
# secrets, and aityx's URL when set (scripts/env.sh exports them).
export AITYX_API_KEY DATYX_SERVICE_TOKEN

case "$API_MODE" in
  dev)
    echo "api: quarkus:dev on $JAVA_HOME (version $VERSION, debugger on $DATYX_DEBUG_PORT)"
    cd "$root/datyx-api"
    # No interactive console and no analytics prompt: this runs under
    # process-compose, not a terminal.
    exec ./mvnw -B -q quarkus:dev -Drevision="$VERSION" \
      -Ddebug="$DATYX_DEBUG_PORT" -Dquarkus.console.enabled=false \
      -Dquarkus.analytics.disabled=true
    ;;
  jar)
    bash "$root/scripts/build.sh" jar
    echo "api: datyx-api/target/quarkus-app/quarkus-run.jar on $JAVA_HOME"
    exec java -jar "$root/datyx-api/target/quarkus-app/quarkus-run.jar"
    ;;
  native)
    bash "$root/scripts/build.sh" native
    echo "api: datyx-api/target/datyx-runner (native)"
    exec "$root/datyx-api/target/datyx-runner"
    ;;
  *)
    echo "error: API_MODE must be dev, jar or native (got '$API_MODE')" >&2
    exit 2
    ;;
esac
