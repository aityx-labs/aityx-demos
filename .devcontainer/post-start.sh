#!/usr/bin/env bash
# Runs each time the container starts (postStartCommand), after
# on-create.sh, update-content.sh and post-create.sh on the first start:
# starts the index page and the container's group of demos (DEMOS_GROUP,
# set by its devcontainer.json) with ./start-all.sh and, in a codespace,
# makes their ports public, so each app opens from the Ports panel (or
# from the index page's browser tab, which Codespaces opens) with nothing
# to run.
#
# start-all.sh starts each demo's services (`devbox services up -b`, or the
# image's process-compose: see demos-toolchain.sh). The aityx group: the
# index (Index/, 8800), which serves the release web builds of Mortgage
# Hub, Contact Hub, PokerFace, RoboRules, Cellfie and RiverRace itself, at
# /mortgagehub/, /contacthub/, ... on its port; each app calls aityx from
# the browser. The datyx group: the datyx API (9900, with PostgreSQL,
# Elasticsearch and OpenMetadata in containers), the datyx dashboard
# (9906), HealthHub (9801, with its PostgreSQL container on 9803) and
# its index, datyx-index/ (9800). The builds are made by update-content.sh
# when the codespace was created (or come from the image), so the demos
# are up in seconds; a demo whose build is missing or older than its
# sources builds first, a minute or two. Watch one with
# `process-compose attach -U -u /tmp/aityx-demos-<demo>.sock` (see
# demos-toolchain.sh); stop them with ./stop-all.sh, which, like
# ./start-all.sh, acts on the container's group only.
#
# Everything is logged to startup.log at the root (see startup-log.sh),
# including start-all.sh's own lines saying when each demo answers, or,
# if one doesn't within 15 minutes, that it didn't.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=startup-log.sh
source "$here/startup-log.sh"
# shellcheck source=../demos-toolchain.sh
source "$here/../demos-toolchain.sh"

startup_capture post-start
echo "===== post-start: $(date -u '+%Y-%m-%d %H:%M:%S') UTC"
startup_facts

cd "$startup_root" || { echo "post-start: cannot find $startup_root" >&2; exit 1; }

# What the toolchain (devbox, or the image's own tools) still lacks for
# any demo: with devbox, each demo's `devbox install` from on-create.sh.
missing=()
for demo in $(startup_demos); do
  while IFS= read -r item; do missing+=("$item"); done < <(toolchain_missing "$startup_root/$demo")
done
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "post-start: the $DEMOS_TOOLCHAIN toolchain isn't ready: missing $(printf '%s; ' "${missing[@]}" | sort -u | tr -d '\n')"
  echo "post-start: (did on-create.sh fail? see its lines above); start the"
  echo "post-start: demos with: ./start-all.sh"
else
  # Detached, so it outlives postStartCommand. start-all.sh's output, and
  # what it says when each demo answers, goes to the log too. The group's
  # index first (Index/ for aityx, datyx-index/ for datyx): it is up in
  # seconds and links the others while they come up.
  index=Index
  [[ "${DEMOS_GROUP:-}" == datyx ]] && index=datyx-index
  setsid nohup bash -c '{ WAIT=120 ./start-all.sh "$1"; WAIT=900 ./start-all.sh; } 2>&1 |
    while IFS= read -r line; do
      printf "%s [start-all] %s\n" "$(date -u "+%Y-%m-%d %H:%M:%S")" "$line"
    done >>"$0"' "$startup_log" "$index" </dev/null >/dev/null 2>&1 &
  echo "post-start: starting the index and the ${DEMOS_GROUP:-every} demo group in the background (./start-all.sh);"
  echo "post-start: progress in startup.log"
fi

bash "$here/public-port.sh"
