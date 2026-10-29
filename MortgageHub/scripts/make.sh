#!/usr/bin/env bash
# Builds the app binaries. Run through the Makefile (`make`, `make web`, ...)
# or directly: `bash scripts/make.sh <target>...`.
#
# Targets: web, android, ios, linux, all (every platform this host can
# build), clean. Settings, from the environment or `make VAR=value`:
#   MODE          release (default), profile or debug
#   IOS_CODESIGN  1 to sign the iOS build (needs a signing team in Xcode);
#                 unsigned by default
#   API_BASE_URL  the API the app calls for the regulatory check
#                 (default http://localhost:8881; empty: the app's origin)
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

cd "$(dirname "$0")/../mortgagehub_app"
source ../scripts/version.sh
# MORTGAGEHUB_VERSION: X.Y.Z, shown at the bottom of the welcome screen.
BUILD_ARGS=(--build-name "$VERSION" --build-number "$BUILD_NUMBER"
  --dart-define="MORTGAGEHUB_VERSION=$VERSION"
  --dart-define="API_BASE_URL=${API_BASE_URL-http://localhost:8881}")

# can_build <target>: whether this host's OS can build the target.
can_build() {
  case "$1" in
    ios) [[ "$(uname -s)" == Darwin ]] ;;
    linux) [[ "$(uname -s)" == Linux ]] ;;
    *) return 0 ;;
  esac
}

# stamp_web <dir> <id>: gives the web build's scripts URLs of their own,
# flutter_bootstrap.js?b=<id> from index.html and main.dart.js?b=<id> from
# the bootstrap, so a browser that cached an earlier build's (a server
# without cache headers lets it keep them for hours, and a reload doesn't
# revalidate scripts) fetches this one. index.html itself is revalidated
# on every load.
stamp_web() {
  local dir="$1" id="$2"
  sed -i.bak "s|src=\"flutter_bootstrap.js\"|src=\"flutter_bootstrap.js?b=$id\"|" "$dir/index.html"
  sed -i.bak "s|\"mainJsPath\":\"main.dart.js\"|\"mainJsPath\":\"main.dart.js?b=$id\"|" "$dir/flutter_bootstrap.js"
  rm -f "$dir/index.html.bak" "$dir/flutter_bootstrap.js.bak"
  if ! grep -q "flutter_bootstrap.js?b=$id" "$dir/index.html" ||
    ! grep -q "main.dart.js?b=$id" "$dir/flutter_bootstrap.js"; then
    echo "error: couldn't stamp the web build's script URLs (did Flutter change index.html or flutter_bootstrap.js?)" >&2
    return 1
  fi
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
      local base=()
      [[ -n "${WEB_BASE_HREF:-}" ]] && base=(--base-href "$WEB_BASE_HREF")
      flutter build web "--$MODE" ${base[@]+"${base[@]}"} "${BUILD_ARGS[@]}"
      stamp_web build/web "$BUILD_NUMBER"
      echo "==> web: mortgagehub_app/build/web/"
      ;;
    android)
      flutter build apk "--$MODE" "${BUILD_ARGS[@]}"
      echo "==> android: mortgagehub_app/build/app/outputs/flutter-apk/app-$MODE.apk"
      ;;
    ios)
      local sign=--no-codesign
      [[ "${IOS_CODESIGN:-}" == 1 ]] && sign=--codesign
      flutter build ios "--$MODE" "$sign" "${BUILD_ARGS[@]}"
      echo "==> ios: mortgagehub_app/build/ios/iphoneos/Runner.app"
      ;;
    linux)
      flutter build linux "--$MODE" "${BUILD_ARGS[@]}"
      echo "==> linux: mortgagehub_app/build/linux/*/$MODE/bundle/"
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
