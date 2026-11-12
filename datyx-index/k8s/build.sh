#!/usr/bin/env bash
# Builds the datyx index's image (docker/datyx-index.Dockerfile, from this
# demo's folder) and pushes it to the cluster's registry. Run by
# k8s/deploy.sh at the repository's root before it applies k8s/.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../../k8s/lib.sh
source "$here/../../k8s/lib.sh"

demo="$(dirname "$here")"
k8s_build datyx-index -f "$demo/docker/datyx-index.Dockerfile" "$demo"
