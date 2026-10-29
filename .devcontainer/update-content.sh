#!/usr/bin/env bash
# Runs after on-create.sh when the container is created, and again whenever
# Codespaces refreshes a prebuild (updateContentCommand): builds what each
# demo of the container's group (DEMOS_GROUP) serves with ./build-all.sh (each demo's scripts/build.sh: the app's
# release web build, and the API and web server compiled to native
# executables), only what is missing or older than its sources. A prebuild's
# snapshot keeps the builds, so a codespace created from one starts every
# demo in seconds; without a prebuild this is the slow part of creating a
# codespace, a minute or two per demo on a 4-core machine, during which the
# editor is already usable (devcontainer.json's waitFor). It needs no
# secrets.
set -euo pipefail

# Everything below also goes to startup.log at the root (see startup-log.sh).
# shellcheck source=startup-log.sh
source "$(dirname "${BASH_SOURCE[0]}")/startup-log.sh"
startup_capture update-content
echo "===== update-content: $(date -u '+%Y-%m-%d %H:%M:%S') UTC"

if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  export NIX_CONFIG="access-tokens = github.com=${GITHUB_TOKEN}"
fi
export PATH="$HOME/.nix-profile/bin:$PATH"

cd "$startup_root" || { echo "update-content: cannot find $startup_root" >&2; exit 1; }

started=$SECONDS
if ./build-all.sh; then
  echo "update-content: the ${DEMOS_GROUP:-every} demo group built in $((SECONDS - started)) s"
else
  # Not fatal: a demo that failed to build here builds again when it
  # starts, and the others are unaffected.
  echo "update-content: build-all.sh reported a failure after $((SECONDS - started)) s;" >&2
  echo "update-content: that demo builds again when it starts (see above)" >&2
fi
df -h / 2>/dev/null | tail -1 | awk '{print "update-content: disk /: " $4 " free of " $2}'
