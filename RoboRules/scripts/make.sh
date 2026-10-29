#!/usr/bin/env bash
# Builds the app binaries. Run through the Makefile (`make`, `make web`, ...)
# or directly: `bash scripts/make.sh <target>...`.
#
# Targets: web (the only platform: RoboRules is a web app), all (the
# same), clean. Settings, from the environment or `make VAR=value`:
#   MODE          release (default), profile or debug
#   API_BASE_URL  the API the app calls to play turns
#                 (default http://localhost:8921; empty: the app's origin)
#   WEB_BASE_HREF the web build's base href, e.g. /app/ to serve it where the
#                 dev server does; / by default
#
# The version is X.Y.Z: X and Y from version.X.txt and version.Y.txt, Z the
# build time as YYYYMMDDHHMM (UTC); the build number is the same time in
# Unix seconds. Set VERSION_Z and BUILD_NUMBER to override them (see
# scripts/version.sh).
set -euo pipefail

MODE="${MODE:-release}"
case "$MODE" in
  release | profile | debug) ;;
  *) echo "error: MODE must be release, profile or debug (got '$MODE')" >&2; exit 2 ;;
esac

cd "$(dirname "$0")/../roborules_app"
source ../scripts/version.sh
# ROBORULES_VERSION: X.Y.Z, shown at the bottom of the welcome screen.
BUILD_ARGS=(--build-name "$VERSION" --build-number "$BUILD_NUMBER"
  --dart-define="ROBORULES_VERSION=$VERSION"
  --dart-define="API_BASE_URL=${API_BASE_URL-http://localhost:8921}")

build_web() {
  local base=()
  [[ -n "${WEB_BASE_HREF:-}" ]] && base=(--base-href "$WEB_BASE_HREF")
  echo "==> web ($MODE, version $VERSION, build $BUILD_NUMBER)"
  flutter build web "--$MODE" ${base[@]+"${base[@]}"} "${BUILD_ARGS[@]}"
  echo "==> web: roborules_app/build/web/"
}

[[ $# -gt 0 ]] || set -- all
for arg in "$@"; do
  case "$arg" in
    web | all) build_web ;;
    clean) flutter clean ;;
    android | ios | linux)
      echo "error: $arg is not supported; RoboRules is a web-only app" >&2
      exit 2
      ;;
    *) echo "error: unknown target '$arg' (web, all, clean)" >&2; exit 2 ;;
  esac
done
