#!/usr/bin/env bash
# Builds the dashboard (datyx_dashboard/). Run through the Makefile (`make
# web`) or directly: `bash scripts/make.sh <target>...`.
#
# Targets: web, clean. (The dashboard is a web app so far; add a platform
# with `flutter create --platforms <name> .` in datyx_dashboard/ and a
# target here.) Settings, from the environment or `make VAR=value`:
#   MODE          release (default), profile or debug
#   API_BASE_URL  the API the app will call (default http://localhost:9900;
#                 empty: the app's origin, for a server that proxies /api/)
#   WEB_BASE_HREF the web build's base href, e.g. /app/ to serve it where the
#                 dev server does; / by default
#
# The version is X.Y.Z (scripts/version.sh), compiled in as DATYX_VERSION.
set -euo pipefail

MODE="${MODE:-release}"
case "$MODE" in
  release | profile | debug) ;;
  *) echo "error: MODE must be release, profile or debug (got '$MODE')" >&2; exit 2 ;;
esac

cd "$(dirname "$0")/../datyx_dashboard"
source ../scripts/version.sh
BUILD_ARGS=(--build-name "$VERSION" --build-number "$BUILD_NUMBER"
  --dart-define="DATYX_VERSION=$VERSION"
  --dart-define="API_BASE_URL=${API_BASE_URL-http://localhost:9900}")

build_web() {
  echo "==> web ($MODE, version $VERSION, build $BUILD_NUMBER)"
  local base=()
  [[ -n "${WEB_BASE_HREF:-}" ]] && base=(--base-href "$WEB_BASE_HREF")
  flutter build web "--$MODE" ${base[@]+"${base[@]}"} "${BUILD_ARGS[@]}"
  echo "==> web: datyx_dashboard/build/web/"
}

[[ $# -gt 0 ]] || set -- web
for arg in "$@"; do
  case "$arg" in
    web) build_web ;;
    clean) flutter clean ;;
    *) echo "error: unknown target '$arg' (web, clean)" >&2; exit 2 ;;
  esac
done
