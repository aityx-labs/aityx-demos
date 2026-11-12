#!/usr/bin/env bash
# Builds HealthHub's three images and pushes them to the local registry
# (k8s_build in k8s/lib.sh), from the Dockerfiles compose.yaml builds:
#
#   healthhub-api    healthhub_api/Dockerfile, the API as a native executable
#   healthhub-web    docker/web.Dockerfile, the app's web build under nginx
#   healthhub-flink  flink/Dockerfile, Flink with the connectors and the job
#
# The three start at once; k8s_build lets two builds run at a time across
# every demo, so the rest wait for a slot.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../../k8s/lib.sh
source "$here/../../k8s/lib.sh"
demo="$(cd "$here/.." && pwd)"

k8s_build healthhub-api "$demo/healthhub_api" &
api=$!
k8s_build healthhub-web -f "$demo/docker/web.Dockerfile" "$demo" &
web=$!
k8s_build healthhub-flink "$demo/flink" &
flink=$!

failed=0
for pid in $api $web $flink; do
  wait "$pid" || failed=1
done
exit $failed
