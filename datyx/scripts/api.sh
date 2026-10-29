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
