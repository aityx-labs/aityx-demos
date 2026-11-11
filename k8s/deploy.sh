#!/usr/bin/env bash
# Deploys demos to the local cluster (k8s/up.sh makes it): for each, its
# images built and pushed (<demo>/k8s/build.sh), its manifests applied
# (kubectl apply -k <demo>/k8s, in its group's namespace), its own
# workloads restarted, and a wait until they're ready. Once every demo
# named is deployed, each one's <demo>/k8s/verify.sh checks it from this
# host: after the others, since some checks follow data across demos
# (datyx catalogues HealthHub's tables).
#
#   bash k8s/deploy.sh                 # every demo with a k8s/ folder
#   bash k8s/deploy.sh tatyx PokerTour # only these
#   BUILD=0 bash k8s/deploy.sh tatyx   # apply and restart, no build (after
#                                      # bash k8s/secrets.sh, for instance)
#   VERIFY=0 bash k8s/deploy.sh        # don't run the checks
#
# The six aityx demos (Mortgage Hub, Contact Hub, ...) deploy as one, the
# aityx index (Index), which serves them all.
#
# A demo's k8s/ folder holds:
#   kustomization.yaml  its manifests; the workloads that run an image
#                       built here carry the label aityx-demos/build=local
#                       and app.kubernetes.io/part-of=<its folder, lower case>
#   build.sh            builds and pushes its images (k8s_build in lib.sh)
#   verify.sh           checks it answers, from this host; exit 0 when it does
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$here/lib.sh"

BUILD="${BUILD:-1}"
VERIFY="${VERIFY:-1}"
TIMEOUT="${TIMEOUT:-900s}"

# Every demo with a k8s/ folder, in the order they depend on each other:
# the datyx API before the apps that call it, the demos before their
# group's index.
all=(datyx datyx-dashboard HealthHub datyx-index PokerTour tatyx multyx-index Index)
if [[ $# -gt 0 ]]; then
  demos=("$@")
else
  demos=()
  for demo in "${all[@]}"; do
    [[ -f "$k8s_root/$demo/k8s/kustomization.yaml" ]] && demos+=("$demo")
  done
fi

kc get --raw /readyz >/dev/null 2>&1 || { echo "✗ cluster $K8S_CLUSTER isn't up: bash k8s/up.sh" >&2; exit 1; }

failed=0
deployed=()
for demo in "${demos[@]}"; do
  # A folder's name, as the shell completes it too (tatyx/).
  demo="$(basename "${demo%/}")"
  dir="$k8s_root/$demo/k8s"
  [[ -f "$dir/kustomization.yaml" ]] || { echo "✗ $demo has no k8s/kustomization.yaml" >&2; failed=1; continue; }
  ns="$(k8s_namespace "$demo")"
  part="$(tr '[:upper:]' '[:lower:]' <<<"$demo")"
  if [[ "$BUILD" == 1 && -f "$dir/build.sh" ]]; then
    bash "$dir/build.sh" || { echo "✗ $demo: build failed" >&2; failed=1; continue; }
  fi
  # The workloads on images built here that exist already: a restart
  # makes them pull the image again (its tag stays :dev) and read the
  # Secret demo-env again. The ones the apply creates start on both
  # anyway, and restarting them too would only roll them out twice.
  selector="app.kubernetes.io/part-of=$part,aityx-demos/build=local"
  existing="$(kc -n "$ns" get deployment,statefulset -l "$selector" -o name)" ||
    { echo "✗ $demo: couldn't list its workloads" >&2; failed=1; continue; }
  echo "▶ $demo: applying $demo/k8s in namespace $ns"
  kc apply -k "$dir" || { echo "✗ $demo: apply failed" >&2; failed=1; continue; }
  if [[ -n "$existing" ]]; then
    # shellcheck disable=SC2086 # one TYPE/NAME per word
    kc -n "$ns" rollout restart $existing >/dev/null
  fi
  # Every workload of the demo, ours and its infrastructure's.
  workloads="$(kc -n "$ns" get deployment,statefulset -l "app.kubernetes.io/part-of=$part" -o name)" ||
    { echo "✗ $demo: couldn't list its workloads" >&2; failed=1; continue; }
  [[ -n "$workloads" ]] ||
    { echo "✗ $demo: no workload labelled app.kubernetes.io/part-of=$part" >&2; failed=1; continue; }
  ready=1
  for workload in $workloads; do
    kc -n "$ns" rollout status "$workload" --timeout="$TIMEOUT" ||
      { echo "✗ $demo: $workload isn't ready" >&2; failed=1; ready=0; }
  done
  if [[ $ready == 1 ]]; then
    deployed+=("$demo")
    echo "✅ $demo deployed"
  fi
done

if [[ "$VERIFY" == 1 ]]; then
  for demo in "${deployed[@]+"${deployed[@]}"}"; do
    script="$k8s_root/$demo/k8s/verify.sh"
    [[ -f "$script" ]] || continue
    echo "▶ $demo: checking it (k8s/verify.sh)"
    if bash "$script"; then
      echo "✅ $demo works"
    else
      echo "✗ $demo: verify.sh failed" >&2
      failed=1
    fi
  done
fi
exit $failed
