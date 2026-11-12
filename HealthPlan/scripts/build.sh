#!/usr/bin/env bash
# Builds the app's web build, healthplan_app/build/web/, the way the index
# server serves it (Index/bin/server.dart, at /demos/healthplan/ on port 8800).
# Health Plan is a static page (HTML, CSS and plain JavaScript, no Flutter and no
# packages): the build is a copy of healthplan_app/web/, checked to be made for
# its path (<base href="/demos/healthplan/">), so a build is a second.
# Run by the repository's build-all.sh and start-all.sh, or by hand:
# `bash scripts/build.sh`. Targets: web (the default) and all, the same thing.
#
# The build is redone only when it's missing or older than its sources, so a
# start after no change copies nothing.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/healthplan_app"
src="$app/web"
out="$app/build/web"
base_href=/demos/healthplan/

# stale <target> <source>: whether the target is missing or older than any
# file under the source.
stale() {
  [[ -e "$1" ]] || return 0
  [[ -n "$(find "$2" -newer "$1" -print 2>/dev/null | head -1)" ]]
}

build_web() {
  if ! grep -q "<base href=\"$base_href\">" "$src/index.html"; then
    echo "error: $src/index.html has no <base href=\"$base_href\">" >&2
    exit 1
  fi
  if stale "$out/index.html" "$src"; then
    echo "build: web (healthplan_app/build/web is missing or older than healthplan_app/web)"
    rm -rf "$out"
    mkdir -p "$out"
    cp -R "$src/." "$out/"
    # Newer than every source, so the next start finds it up to date.
    touch "$out/index.html"
  else
    echo "build: web is up to date"
  fi
}

[[ $# -gt 0 ]] || set -- web
for target in "$@"; do
  case "$target" in
    web | all) build_web ;;
    *)
      echo "error: unknown target '$target' (web, all)" >&2
      exit 2
      ;;
  esac
done
