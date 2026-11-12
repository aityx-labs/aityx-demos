#!/usr/bin/env bash
# Builds Poker Tour's image, the one compose.yaml builds (the Dockerfile in
# this demo's folder: the server with the app's release web build and the
# models), with the folder as the context and the repository's packages/
# as the second context named packages, where the app's aityx_web comes
# from. Pushes it to the local registry as
# localhost:5001/aityx-demos/pokertour:dev. k8s/deploy.sh runs it.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
demo="$(cd "$here/.." && pwd)"
# shellcheck source=../../k8s/lib.sh
source "$here/../../k8s/lib.sh"

k8s_build pokertour --build-context packages="$demo/../packages" -f "$demo/Dockerfile" "$demo"
