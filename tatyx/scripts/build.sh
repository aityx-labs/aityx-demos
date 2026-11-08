#!/usr/bin/env bash
# Builds what the server serves, and only what changed since the last
# build: the app's release build, tatyx_app/dist/, under /app/, and the
# leaderboard's runner, tatyx_app/dist-runner/runner.mjs, with Vite (`npm
# run build`: a type check, the bundle, the runner), after `npm ci`
# when the packages are missing or the lock file is newer than them.
# The server itself (tatyx_server/server.mjs) needs no build.
#
# Run by scripts/serve.sh before it serves, by the repository's
# build-all.sh and start-all.sh, or by hand: `bash scripts/build.sh` (or
# `devbox run build`).
#
# The build is rebuilt when it is missing or older than any of its
# sources (the app, the shared package aityx-js, the version files), and
# it records the settings it was built with (dist/.tatyx-services), so
# a build made by hand with other settings is rebuilt too.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/tatyx_app"
shared="$root/../packages/aityx_js"

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

# The settings the server needs the build made with; recorded beside the
# build once it succeeds, and required before it is reused.
web_settings='base=/app/'

install_if_stale() {
  if stale "$app/node_modules/.package-lock.json" "$app/package.json" "$app/package-lock.json" "$shared/package.json"; then
    echo "build: npm ci (tatyx_app/node_modules is missing or older than the lock file)"
    (cd "$app" && if [[ -f package-lock.json ]]; then npm ci --no-audit --no-fund; else npm install --no-audit --no-fund; fi)
  fi
}

build_if_stale() {
  local out="$app/dist" stamp="$app/dist/.tatyx-services"
  if [[ "$(cat "$stamp" 2>/dev/null)" != "$web_settings" ]] ||
    [[ ! -f "$app/dist-runner/runner.mjs" ]] ||
    stale "$stamp" "$out/index.html" ||
    stale "$out/index.html" "$app/src" "$app/public" "$app/index.html" \
      "$app/package.json" "$app/package-lock.json" "$app/vite.config.ts" "$app/tsconfig.json" \
      "$shared/src" "$shared/package.json" \
      "$root/version.X.txt" "$root/version.Y.txt"; then
    echo "build: web (tatyx_app/dist is missing, has other settings, or is older than the app)"
    (cd "$app" && npm run build)
    echo "$web_settings" >"$stamp"
  else
    echo "build: web is up to date"
  fi
}

install_if_stale
build_if_stale
