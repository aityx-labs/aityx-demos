#!/usr/bin/env bash
# Builds the dashboard's image for the local cluster and pushes it to the
# local registry (k8s/lib.sh): the release web build under nginx, from
# docker/web.Dockerfile, the same image `docker compose up` runs. Built
# from the datyx-dashboard/ folder, as compose.yaml builds it, so the
# folder's .dockerignore picks what goes in. k8s/deploy.sh runs it.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../../k8s/lib.sh
source "$here/../../k8s/lib.sh"

demo="$(dirname "$here")"
k8s_build datyx-dashboard -f "$demo/docker/web.Dockerfile" "$demo"
