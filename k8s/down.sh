#!/usr/bin/env bash
# Deletes the demos' local cluster, and with it every demo deployed there
# and their data. The registry (kind-registry) and its images stay, so a
# new cluster (k8s/up.sh) deploys without building again; REGISTRY=1
# removes it too.
#
#   bash k8s/down.sh
#   REGISTRY=1 bash k8s/down.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$here/lib.sh"

kind delete cluster --name "$K8S_CLUSTER"
if [[ "${REGISTRY:-0}" == 1 ]]; then
  docker rm -f "$K8S_REGISTRY_NAME" >/dev/null 2>&1 && echo "✅ registry $K8S_REGISTRY_NAME removed"
fi
