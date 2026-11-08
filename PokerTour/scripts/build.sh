#!/usr/bin/env bash
# Builds what the server serves, and only what changed since the last
# build:
#   web      the app's release web build, pokertour_app/build/web/, through
#            scripts/make.sh web: under /app/, calling /api/ on its own
#            origin and aityx with the key it fetched
#   server   the server (pokertour_api/bin/server.dart), compiled to
#            pokertour_api/build/server
#   all      both (the default)
# Run by scripts/serve.sh before it serves, by the repository's
# build-all.sh and start-all.sh, or by hand: `bash scripts/build.sh` (or
# `devbox run build`).
#
# A target is rebuilt when its output is missing or older than any of its
# sources (the app, the shared packages aityx_web, poker_core and aws_lite, the
# version files), so a start after no change builds nothing. The web
# build also records the settings it was built with
# (pokertour_app/build/web/.pokertour-services), and a build without
# them, or made since by hand, is rebuilt. A web build is CPU-heavy, so
# the demos take turns: one Flutter web build at a time across the whole
# repository, through a lock in the system's temp folder. The checks run
# inside the lock, so two starts that overlap build once, not twice.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/pokertour_app"
api="$root/pokertour_api"
core="$root/poker_core"
aws="$root/aws_lite"
shared="$root/../packages/aityx_web"

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
  _lock="$lock"
  trap 'rm -rf "$_lock"' EXIT
  "$@"
  rm -rf "$lock"
  trap - EXIT
}

# The settings the server needs the web build made with; recorded beside
# the build once it succeeds, and required before it is reused.
web_settings='base_href=/app/ web_resources_cdn=no'

build_web_if_stale() {
  local out="$app/build/web" stamp="$app/build/web/.pokertour-services"
  if [[ "$(cat "$stamp" 2>/dev/null)" != "$web_settings" ]] ||
    stale "$stamp" "$out/main.dart.js" ||
    stale "$out/main.dart.js" "$app/lib" "$app/web" "$app/assets" \
      "$app/pubspec.yaml" "$app/pubspec.lock" \
      "$core/lib" "$core/pubspec.yaml" "$aws/lib" "$aws/pubspec.yaml" \
      "$shared/lib" "$shared/pubspec.yaml" \
      "$root/version.X.txt" "$root/version.Y.txt"; then
    echo "build: web (pokertour_app/build/web is missing, has other settings, or is older than the app)"
    env WEB_BASE_HREF=/app/ bash "$root/scripts/make.sh" web
    echo "$web_settings" >"$stamp"
  else
    echo "build: web is up to date"
  fi
}

compile_if_stale() {
  if stale "$api/build/server" "$api/bin/server.dart" "$api/lib" \
    "$api/pubspec.yaml" "$api/pubspec.lock" "$core/lib" "$core/pubspec.yaml" "$aws/lib" "$aws/pubspec.yaml"; then
    echo "build: server (dart compile exe, to pokertour_api/build/server)"
    (cd "$api" && dart pub get >/dev/null && mkdir -p build &&
      dart compile exe bin/server.dart -o build/server >/dev/null)
  else
    echo "build: server is up to date"
  fi
}

build_web() { with_lock flutter-web-build build_web_if_stale; }
compile() { with_lock pokertour-api-compile compile_if_stale; }

[[ $# -gt 0 ]] || set -- all
for target in "$@"; do
  case "$target" in
    web) build_web ;;
    server | api) compile ;;
    all)
      build_web
      compile
      ;;
    *)
      echo "error: unknown target '$target' (web, server, all)" >&2
      exit 2
      ;;
  esac
done
