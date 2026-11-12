#!/usr/bin/env bash
# Builds the datyx API's image for the local cluster and pushes it to its
# registry (k8s_build, ../../k8s/lib.sh): docker/api.jvm.Dockerfile, the
# packaged API on the GraalVM JDK (a native build wants more memory than
# the cluster's Docker has to spare). The dev profile, as compose.yaml
# builds it: HealthHub's development data and catalogue, Swagger UI.
# PostgreSQL, Elasticsearch and OpenMetadata run their published images.
#
#   bash datyx/k8s/build.sh       # or bash k8s/deploy.sh datyx
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
demo="$(dirname "$here")"
# shellcheck source=../../k8s/lib.sh
source "$here/../../k8s/lib.sh"

# The version X.Y.Z (scripts/version.sh), Z from the time of the folder's
# last commit rather than now, so a rebuild of the same sources reuses
# Docker's cached layers (the dependencies' download among them).
BUILD_NUMBER="$(git -C "$demo" log -1 --format=%ct -- . 2>/dev/null || true)"
[[ -n "$BUILD_NUMBER" ]] || unset BUILD_NUMBER
# shellcheck source=../scripts/version.sh
source "$demo/scripts/version.sh"

k8s_build datyx-api "$demo" -f "$demo/docker/api.jvm.Dockerfile" \
  --build-arg REVISION="$VERSION" --build-arg PROFILE=dev \
  --build-arg PACKAGE_ARGS=-Dquarkus.swagger-ui.always-include=true
