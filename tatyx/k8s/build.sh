#!/usr/bin/env bash
# Builds tatyx's image (docker/tatyx.Dockerfile, with this demo's folder
# as the context and the repository's shared packages as the context named
# `packages`, for aityx-js) and pushes it to the local registry, as
# localhost:5001/aityx-demos/tatyx:dev. k8s/deploy.sh runs it.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
demo="$(cd "$here/.." && pwd)"
# shellcheck source=../../k8s/lib.sh
source "$here/../../k8s/lib.sh"

k8s_build tatyx -f "$demo/docker/tatyx.Dockerfile" \
  --build-context packages="$k8s_root/packages" "$demo"
