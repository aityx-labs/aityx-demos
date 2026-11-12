#!/usr/bin/env bash
# Checks the demos deployed on the local cluster, from this host: each
# demo's <demo>/k8s/verify.sh, which exits 0 when the demo answers and
# works. Prints one line per demo.
#
#   bash k8s/verify.sh            # every demo with a k8s/verify.sh
#   bash k8s/verify.sh tatyx      # only these
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$here/lib.sh"

all=(datyx datyx-dashboard HealthHub datyx-index PokerTour tatyx multyx-index Index)
demos=("$@")
[[ $# -gt 0 ]] || demos=("${all[@]}")

failed=0
for demo in "${demos[@]}"; do
  script="$k8s_root/$demo/k8s/verify.sh"
  [[ -f "$script" ]] || continue
  if bash "$script"; then
    echo "✅ $demo"
  else
    echo "✗ $demo" >&2
    failed=1
  fi
done
exit $failed
