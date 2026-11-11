# Sourced by the k8s/ scripts and each demo's k8s/build.sh: the cluster,
# the registry, the namespaces, and how an image is built and pushed.
#
#   K8S_CONTEXT       the kubectl context (kind-aityx-demos); every
#                     command names it, so nothing reaches another cluster
#   K8S_REGISTRY      where the demos' images go (localhost:5001, the
#                     kind-registry container)
#   K8S_BUILD_SLOTS   how many image builds run at once (2): a Flutter
#                     web build takes a gigabyte or two, and several at
#                     once run Docker out of memory

K8S_CLUSTER="${K8S_CLUSTER:-aityx-demos}"
K8S_CONTEXT="${K8S_CONTEXT:-kind-$K8S_CLUSTER}"
K8S_REGISTRY="${K8S_REGISTRY:-localhost:5001}"
K8S_REGISTRY_NAME="${K8S_REGISTRY_NAME:-kind-registry}"
K8S_BUILD_SLOTS="${K8S_BUILD_SLOTS:-2}"
k8s_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# kc <args>: kubectl on the demos' cluster, whatever the current context.
kc() {
  kubectl --context "$K8S_CONTEXT" "$@"
}

# k8s_namespace <demo folder>: the demo's namespace, its group
# (group.id.txt): aityx, multyx or datyx.
k8s_namespace() {
  tr -d '[:space:]' <"$k8s_root/$(basename "${1%/}")/group.id.txt"
}

# k8s_image <name>: an image's reference in the local registry.
k8s_image() {
  printf '%s/aityx-demos/%s:dev\n' "$K8S_REGISTRY" "$1"
}

# k8s_build <name> <docker build arguments...>: builds the image named
# <name> (k8s_image) with the arguments given (context, -f, --build-arg,
# --build-context...), then pushes it to the registry. At most
# K8S_BUILD_SLOTS builds run at once, across every shell: a build waits
# for a free slot.
k8s_build() {
  local name="$1" ref slot
  shift
  ref="$(k8s_image "$name")"
  slot="$(k8s_slot_take)" || return 1
  echo "▶ building $ref (slot $(basename "$slot"))"
  if ! docker build -t "$ref" "$@"; then
    k8s_slot_release "$slot"
    echo "✗ building $ref failed" >&2
    return 1
  fi
  k8s_slot_release "$slot"
  docker push -q "$ref" >/dev/null || {
    echo "✗ pushing $ref failed: is the registry up (k8s/up.sh)?" >&2
    return 1
  }
  echo "✅ $ref pushed"
}

# The build slots: one folder per running build, holding its shell's PID;
# a slot whose shell has died is free again. The slots are looked at and
# taken under a short lock (a folder, which mkdir makes atomically), so
# two waiters never both take over the same dead slot.
k8s_slots_dir="${TMPDIR:-/tmp}/aityx-demos-k8s-build-slots"
k8s_slot_take() {
  local i slot pid lock="$k8s_slots_dir/.lock"
  mkdir -p "$k8s_slots_dir"
  while :; do
    # The lock is held for milliseconds: one older than a minute is a
    # killed shell's.
    until mkdir "$lock" 2>/dev/null; do
      [[ -n "$(find "$lock" -maxdepth 0 -mmin +1 2>/dev/null)" ]] && rmdir "$lock" 2>/dev/null
      sleep 0.2
    done
    for ((i = 1; i <= K8S_BUILD_SLOTS; i++)); do
      slot="$k8s_slots_dir/$i"
      if [[ -d "$slot" ]]; then
        pid="$(cat "$slot/pid" 2>/dev/null)"
        [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null && continue
        rm -rf "$slot"
      fi
      mkdir "$slot" 2>/dev/null || continue
      echo $$ >"$slot/pid"
      rmdir "$lock"
      echo "$slot"
      return 0
    done
    rmdir "$lock"
    sleep 3
  done
}
k8s_slot_release() {
  rm -rf "$1"
}
