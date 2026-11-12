#!/usr/bin/env bash
# Builds the app's release web build, holidaysplit_app/build/web/, the way
# the index server serves it, at http://localhost:8800/demos/holidaysplit/
# (see Index/bin/server.dart), and only when it changed since the last
# build: `npm run build` (Vite, base /demos/holidaysplit/), after `npm ci`
# when the packages are missing or older than the lock file. There is no
# API: the app calls aityx itself, on the key the index page set, or
# through the index server's dev proxy.
# Run by the repository's build-all.sh and start-all.sh, or by hand: `bash
# scripts/build.sh` (or `devbox run build`).
#
# The build is redone when it is missing or older than any of its sources
# (the app, the shared package packages/aityx_js, the version files), and
# it records the settings it was built with
# (holidaysplit_app/build/web/.aityx-services), so a build made by hand
# with other settings is redone too.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/holidaysplit_app"
shared="$root/../packages/aityx_js"

# Where the index server serves the app.
base_href=/demos/holidaysplit/

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

# The settings the index server needs the build made with; recorded beside
# the build once it succeeds, and required before it is reused.
web_settings="base_href=$base_href"

install_if_stale() {
  if stale "$app/node_modules/.package-lock.json" "$app/package.json" "$app/package-lock.json" "$shared/package.json"; then
    echo "build: npm ci (holidaysplit_app/node_modules is missing or older than the lock file)"
    (cd "$app" && npm ci --no-audit --no-fund)
  fi
}

build_if_stale() {
  local out="$app/build/web" stamp="$app/build/web/.aityx-services"
  if [[ "$(cat "$stamp" 2>/dev/null)" != "$web_settings" ]] ||
    stale "$stamp" "$out/index.html" ||
    stale "$out/index.html" "$app/src" "$app/public" "$app/index.html" \
      "$app/package.json" "$app/package-lock.json" "$app/vite.config.js" \
      "$shared/src" "$shared/package.json" \
      "$root/version.X.txt" "$root/version.Y.txt"; then
    echo "build: web (holidaysplit_app/build/web is missing, has other settings, or is older than the app)"
    (cd "$app" && npm run build)
    echo "$web_settings" >"$stamp"
  else
    echo "build: web is up to date"
  fi
}

[[ $# -gt 0 ]] || set -- web
for target in "$@"; do
  case "$target" in
    web | all)
      install_if_stale
      build_if_stale
      ;;
    *)
      echo "error: unknown target '$target' (web)" >&2
      exit 2
      ;;
  esac
done
