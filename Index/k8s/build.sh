#!/usr/bin/env bash
# Builds the aityx index's image, aityx-index, and pushes it to the local
# registry (k8s_build in k8s/lib.sh): docker/aityx-index.Dockerfile, from
# the root of the repository, since it builds the six aityx demos' web
# apps (one after another, in one build) and they depend on
# packages/aityx_web by path. Its ignore file,
# docker/aityx-index.Dockerfile.dockerignore, lets in only what that
# needs.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../../k8s/lib.sh
source "$here/../../k8s/lib.sh"

k8s_build aityx-index -f "$k8s_root/Index/docker/aityx-index.Dockerfile" "$k8s_root"
