#!/usr/bin/env bash
# Builds what the index serves at /mortgagehub/: the app's release web
# build, mortgagehub_app/build/web/, through scripts/make.sh web, with the
# base href /mortgagehub/ and no CDN (`--no-web-resources-cdn`: CanvasKit
# comes from the build itself, so no third-party script runs on the origin
# that holds the user's aityx key). There's no API: the app calls aityx
# from the browser. Only when something changed since the last build.
# Run by the repository's build-all.sh and start-all.sh, or by hand:
# `bash scripts/build.sh` (or `devbox run build`). Takes no target, or
# `web` (`all` means the same).
#
# The build is redone when it's missing or older than any of its sources:
# the app, the shared package (packages/aityx_web) and the version files,
# so a start after no change builds nothing. It also records the settings
# it was built with (mortgagehub_app/build/web/.aityx-services), and a
# build without them, or made since by hand, for instance `make web` with
# another base href, is rebuilt. A web build is CPU-heavy, so the demos
# take turns: one Flutter web build at a time across the whole
# repository, through a lock in the system's temp folder. The checks run
# inside the lock, so two starts that overlap build once, not twice.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/mortgagehub_app"
shared="$root/../packages/aityx_web"

for target in "$@"; do
  case "$target" in
    web | all) ;;
    *)
      echo "error: unknown target '$target' (web, all)" >&2
      exit 2
      ;;
  esac
done

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

# The settings the index needs the web build made with; recorded beside
# the build once it succeeds, and required before it is reused. The record
# must also be newer than the build itself: `flutter build web` keeps
# other files in build/web, so a later build by hand, with other
# settings, would otherwise keep the record.
web_settings='base_href=/mortgagehub/ web_resources_cdn=no'

# Inside the web lock: build the web app if its build is missing, was made
# with other settings (or by hand since), or is older than its sources.
build_web_if_stale() {
  local out="$app/build/web" stamp="$app/build/web/.aityx-services"
  if [[ "$(cat "$stamp" 2>/dev/null)" != "$web_settings" ]] ||
    stale "$stamp" "$out/main.dart.js" ||
    stale "$out/main.dart.js" "$app/lib" "$app/web" "$app/assets" \
      "$app/pubspec.yaml" "$app/pubspec.lock" \
      "$shared/lib" "$shared/pubspec.yaml" \
      "$root/version.X.txt" "$root/version.Y.txt"; then
    echo "build: web (mortgagehub_app/build/web is missing, has other settings, or is older than the app)"
    env MODE=release WEB_BASE_HREF=/mortgagehub/ bash "$root/scripts/make.sh" web
    echo "$web_settings" >"$stamp"
  else
    echo "build: web is up to date"
  fi
}

with_lock flutter-web-build build_web_if_stale
