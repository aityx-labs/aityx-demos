#!/usr/bin/env bash
# Builds what `devbox services up` serves, and only what changed since the
# last build:
#   web         the app's release web build, pokerface_app/build/web/,
#               through scripts/make.sh web: under /app/, calling /api/ on
#               its own origin
#   web_server  the web server that serves it (pokerface_api/bin/
#               web_server.dart), compiled to pokerface_api/build/web_server
#   api         the API (pokerface_api/bin/server.dart), compiled to
#               pokerface_api/build/server
#   all         the three (the default)
# Run by scripts/flutter-web.sh and scripts/api.sh before they serve, by the
# repository's build-all.sh, or by hand: `bash scripts/build.sh` (or
# `devbox run build`).
#
# A target is rebuilt when its output is missing or older than any of its
# sources, so a start after no change builds nothing. The web build also
# records the settings it was built with (pokerface_app/build/web/
# .aityx-services), and a build without them, or made since by hand, for
# instance `make web` with another API_BASE_URL, is rebuilt. A web build is CPU-heavy,
# so the demos take turns: one Flutter web build at a time across the
# whole repository, through a lock in the system's temp folder (the API's
# compiles take seconds and share a lock of their own). The checks run
# inside the lock, so two starts that overlap build once, not twice.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/pokerface_app"
api="$root/pokerface_api"

# stale <target> <source>...: whether the target is missing or older than a
# source (a file, or any file under a folder). Missing sources are skipped.
stale() {
  local target="$1" source
  shift
  [[ -e "$target" ]] || return 0
  for source in "$@"; do
    [[ -e "$source" ]] || continue
    [[ -n "$(find "$source" -newer "$target" -print 2>/dev/null | head -1)" ]] && return 0
  done
  return 1
}

# with_lock <name> <command...>: runs the command holding the lock named
# <name>, shared by every demo of the repository; waits for whoever holds
# it, unless that process is gone (a build killed half-way), or the lock
# never got its PID and is a minute old (its maker died before writing it).
with_lock() {
  local lock="${TMPDIR:-/tmp}/aityx-demos-$1.lock" holder
  shift
  while ! mkdir "$lock" 2>/dev/null; do
    holder="$(cat "$lock/pid" 2>/dev/null || true)"
    if [[ -n "$holder" ]]; then
      if ! kill -0 "$holder" 2>/dev/null; then
        rm -rf "$lock"
        continue
      fi
    elif [[ -n "$(find "$lock" -maxdepth 0 -mmin +1 2>/dev/null)" ]]; then
      rm -rf "$lock"
      continue
    fi
    sleep 3
  done
  echo $$ >"$lock/pid"
  # Released however the command ends.
  _lock="$lock"
  trap 'rm -rf "$_lock"' EXIT
  "$@"
  rm -rf "$lock"
  trap - EXIT
}

# The settings the services need the web build made with; recorded beside
# the build once it succeeds, and required before it is reused. The record
# must also be newer than the build itself: `flutter build web` keeps
# other files in build/web, so a later build by hand, with other
# settings, would otherwise keep the record.
web_settings='base_href=/app/ api_base_url='

# Inside the web lock: build the web app if its build is missing, was made
# with other settings (or by hand since), or is older than the app.
build_web_if_stale() {
  local out="$app/build/web" stamp="$app/build/web/.aityx-services"
  if [[ "$(cat "$stamp" 2>/dev/null)" != "$web_settings" ]] ||
    stale "$stamp" "$out/main.dart.js" ||
    stale "$out/main.dart.js" "$app/lib" "$app/web" "$app/assets" \
      "$app/pubspec.yaml" "$app/pubspec.lock" \
      "$root/version.X.txt" "$root/version.Y.txt"; then
    echo "build: web (pokerface_app/build/web is missing, has other settings, or is older than the app)"
    env WEB_BASE_HREF=/app/ API_BASE_URL= bash "$root/scripts/make.sh" web
    echo "$web_settings" >"$stamp"
  else
    echo "build: web is up to date"
  fi
}

# Inside the API lock: pokerface_api/bin/<name>.dart to build/<name>, if stale.
compile_if_stale() {
  local name="$1"
  if stale "$api/build/$name" "$api/bin/$name.dart" "$api/lib" \
    "$api/pubspec.yaml" "$api/pubspec.lock"; then
    echo "build: $name (dart compile exe, to pokerface_api/build/$name)"
    (cd "$api" && dart pub get >/dev/null && mkdir -p build &&
      dart compile exe "bin/$name.dart" -o "build/$name" >/dev/null)
  else
    echo "build: $name is up to date"
  fi
}

build_web() { with_lock flutter-web-build build_web_if_stale; }
compile() { with_lock pokerface-api-compile compile_if_stale "$1"; }

[[ $# -gt 0 ]] || set -- all
for target in "$@"; do
  case "$target" in
    web) build_web ;;
    web_server) compile web_server ;;
    api) compile server ;;
    all)
      build_web
      compile web_server
      compile server
      ;;
    *)
      echo "error: unknown target '$target' (web, web_server, api, all)" >&2
      exit 2
      ;;
  esac
done
