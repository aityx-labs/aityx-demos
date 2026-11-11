#!/usr/bin/env bash
# Builds the multyx index's image (docker/multyx-index.Dockerfile, with
# this demo's folder as the context) and pushes it to the local registry,
# as localhost:5001/aityx-demos/multyx-index:dev. k8s/deploy.sh runs it.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
demo="$(cd "$here/.." && pwd)"
# shellcheck source=../../k8s/lib.sh
source "$here/../../k8s/lib.sh"

k8s_build multyx-index -f "$demo/docker/multyx-index.Dockerfile" "$demo"
