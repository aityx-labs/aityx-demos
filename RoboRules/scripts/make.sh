#!/usr/bin/env bash
# Builds the app. Run through the Makefile (`make`, `make web`, ...)
# or directly: `bash scripts/make.sh <target>...`.
#
# Targets: web (the only platform: RoboRules is a web app), all (the
# same), clean. Settings, from the environment or `make VAR=value`:
#   MODE          release (default), profile or debug
#   WEB_BASE_HREF the web build's base href; /roborules/ by default, where
#                 the index server (Index/bin/server.dart) serves it
#
# The web build keeps CanvasKit on our own origin (--no-web-resources-cdn):
# the origin holds the user's aityx key, so no third-party script runs on
# it. The app calls aityx itself, on the key the index page saved, or the
# index server's dev key through its /aityx/ proxy; served anywhere else
# (a static host, or `flutter run`) there is no dev proxy, and no key
# until one is saved on that origin's index page.
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
  --dart-define="ROBORULES_VERSION=$VERSION")

build_web() {
  local base="${WEB_BASE_HREF:-/roborules/}"
  echo "==> web ($MODE, version $VERSION, build $BUILD_NUMBER, under $base)"
  flutter build web "--$MODE" --base-href "$base" --no-web-resources-cdn \
    "${BUILD_ARGS[@]}"
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
