#!/usr/bin/env bash
# Builds the app binaries. Run through the Makefile (`make`, `make web`, ...)
# or directly: `bash scripts/make.sh <target>...`.
#
# Targets: web, android, ios, linux, all (every platform this host can
# build), clean. Settings, from the environment or `make VAR=value`:
#   MODE          release (default), profile or debug
#   IOS_CODESIGN  1 to sign the iOS build (needs a signing team in Xcode);
#                 unsigned by default
#   WEB_BASE_HREF the web build's base href; /pokerface/ by default, where
#                 the index server (Index/bin/server.dart) serves it
#
# The web build takes CanvasKit from our own origin (--no-web-resources-cdn),
# so no third-party script runs on the origin that holds the user's aityx
# key. The app calls aityx itself, on the key the user set on the index
# page, or through the index server's dev proxy. The native builds have
# neither: no dev proxy, and only an in-memory key store, empty at start,
# so their decisions answer "aityx is not set up" (see
# packages/aityx_web).
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

cd "$(dirname "$0")/../pokerface_app"
source ../scripts/version.sh
# POKERFACE_VERSION: X.Y.Z, shown at the bottom of the welcome screen.
BUILD_ARGS=(--build-name "$VERSION" --build-number "$BUILD_NUMBER"
  --dart-define="POKERFACE_VERSION=$VERSION")

# can_build <target>: whether this host's OS can build the target.
can_build() {
  case "$1" in
    ios) [[ "$(uname -s)" == Darwin ]] ;;
    linux) [[ "$(uname -s)" == Linux ]] ;;
    *) return 0 ;;
  esac
}

build() {
  local target="$1"
  if ! can_build "$target"; then
    echo "error: $target can't be built on $(uname -s)" >&2
    return 1
  fi
  echo "==> $target ($MODE, version $VERSION, build $BUILD_NUMBER)"
  case "$target" in
    web)
      flutter build web "--$MODE" --base-href "${WEB_BASE_HREF:-/pokerface/}" \
        --no-web-resources-cdn "${BUILD_ARGS[@]}"
      echo "==> web: pokerface_app/build/web/"
      ;;
    android)
      flutter build apk "--$MODE" "${BUILD_ARGS[@]}"
      echo "==> android: pokerface_app/build/app/outputs/flutter-apk/app-$MODE.apk"
      ;;
    ios)
      local sign=--no-codesign
      [[ "${IOS_CODESIGN:-}" == 1 ]] && sign=--codesign
      flutter build ios "--$MODE" "$sign" "${BUILD_ARGS[@]}"
      echo "==> ios: pokerface_app/build/ios/iphoneos/Runner.app"
      ;;
    linux)
      flutter build linux "--$MODE" "${BUILD_ARGS[@]}"
      echo "==> linux: pokerface_app/build/linux/*/$MODE/bundle/"
      ;;
  esac
}

[[ $# -gt 0 ]] || set -- all
for arg in "$@"; do
  case "$arg" in
    web | android | ios | linux) build "$arg" ;;
    all)
      for target in web android ios linux; do
        if can_build "$target"; then
          build "$target"
        else
          echo "==> skipping $target: can't be built on $(uname -s)"
        fi
      done
      ;;
    clean) flutter clean ;;
    *) echo "error: unknown target '$arg' (web, android, ios, linux, all, clean)" >&2; exit 2 ;;
  esac
done
