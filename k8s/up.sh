#!/usr/bin/env bash
# Creates the demos' local Kubernetes cluster, or brings it back: the
# local registry (kind-registry, localhost:5001), the kind cluster
# aityx-demos (k8s/kind/cluster.yaml) wired to it, a namespace per group
# (aityx, multyx, datyx) and each one's settings from the root .env
# (k8s/secrets.sh). Safe to run again: what exists is left as it is.
# Then deploy the demos with k8s/deploy.sh.
#
#   bash k8s/up.sh
#
# Needs Docker, kind and kubectl (brew install kind; Docker Desktop has
# kubectl). Running every demo takes about 7 GB of Docker's memory.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$here/lib.sh"

for tool in docker kind kubectl; do
  command -v "$tool" >/dev/null || { echo "✗ $tool is not on the PATH" >&2; exit 1; }
done

# The registry, on this host only.
if [[ "$(docker inspect -f '{{.State.Running}}' "$K8S_REGISTRY_NAME" 2>/dev/null)" != true ]]; then
  if docker inspect "$K8S_REGISTRY_NAME" >/dev/null 2>&1; then
    docker start "$K8S_REGISTRY_NAME" >/dev/null
  else
    docker run -d --restart=always --name "$K8S_REGISTRY_NAME" \
      -p "127.0.0.1:${K8S_REGISTRY##*:}:5000" registry:3 >/dev/null
  fi
  echo "✅ registry $K8S_REGISTRY_NAME on $K8S_REGISTRY"
fi

# The cluster.
if ! kind get clusters 2>/dev/null | grep -qx "$K8S_CLUSTER"; then
  kind create cluster --config "$here/kind/cluster.yaml" --wait 120s
fi

# The node pulls localhost:5001/... from the registry over kind's network.
for node in $(kind get nodes --name "$K8S_CLUSTER"); do
  dir="/etc/containerd/certs.d/$K8S_REGISTRY"
  docker exec "$node" mkdir -p "$dir"
  printf '[host."http://%s:5000"]\n' "$K8S_REGISTRY_NAME" |
    docker exec -i "$node" cp /dev/stdin "$dir/hosts.toml"
done
if [[ "$(docker inspect -f '{{json .NetworkSettings.Networks.kind}}' "$K8S_REGISTRY_NAME")" == null ]]; then
  docker network connect kind "$K8S_REGISTRY_NAME"
fi
# Where the registry is, for tools that ask the cluster (KEP-1755).
kc apply -f - >/dev/null <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "$K8S_REGISTRY"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF

# A namespace per group.
for group in aityx multyx datyx; do
  kc create namespace "$group" --dry-run=client -o yaml | kc apply -f - >/dev/null
done

bash "$here/secrets.sh"
echo "✅ cluster $K8S_CLUSTER is up (kubectl --context $K8S_CONTEXT); deploy with bash k8s/deploy.sh"
