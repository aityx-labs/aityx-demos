#!/usr/bin/env bash
# Puts the release web builds a group's dev container image carries
# (/opt/demos, see Containerfile and build-image.sh) into the workspace,
# for every demo
# whose build key (build-key.sh: the git ids of what the web build is made
# from) is still the one the build was made with; a demo whose app changed
# since is left to build itself (its scripts/build.sh, run by
# ./build-all.sh and before the services start). Run by on-create.sh in a
# codespace; harmless elsewhere (no /opt/demos: nothing to restore).
#
#   bash image/restore-builds.sh            # every demo
#   bash image/restore-builds.sh Cellfie    # only these
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
store=/opt/demos
manifest="$store/manifest"
if [[ ! -f "$manifest" ]]; then
  echo "restore-builds: no $manifest: nothing to restore"
  exit 0
fi
cd "$root"
# shellcheck source=build-key.sh
source "$root/image/build-key.sh"

wanted=("$@")
restored=()
while read -r demo hash; do
  [[ -n "$demo" ]] || continue
  if [[ ${#wanted[@]} -gt 0 ]]; then
    keep=0
    for w in "${wanted[@]}"; do [[ "$w" == "$demo" ]] && keep=1; done
    [[ $keep -eq 1 ]] || continue
  fi
  app="$(app_package "$demo")"
  if [[ -z "$app" || ! -d "$store/$demo/web" ]]; then
    echo "· $demo: no build in the image"
    continue
  fi
  now="$(build_key "$demo" 2>/dev/null)"
  if [[ -z "$now" || "$now" != "$hash" ]]; then
    echo "· $demo's app changed since the image was made (${hash:0:7} → ${now:0:7}): it builds itself"
    continue
  fi
  # The key is HEAD's: a local dev container opened on an edited checkout
  # would get the image's build, made newer than the edits, and serve it.
  dirty="$(build_key_paths "$demo" | xargs git status --porcelain -- 2>/dev/null)"
  if [[ -n "$dirty" ]]; then
    echo "· $demo's app has uncommitted changes: it builds itself"
    continue
  fi
  rm -rf "$app/build/web"
  mkdir -p "$app/build"
  cp -a "$store/$demo/web" "$app/build/web"
  # Writable, so a later rebuild can replace it: the canvaskit files come
  # read-only from the Flutter SDK, and flutter build fails on them.
  chmod -R u+w "$app/build/web"
  # Newer than the checkout, so scripts/build.sh sees the build as current
  # (it compares the build with the sources' times), and the record of the
  # settings it was made with newest of all (see scripts/build.sh).
  find "$app/build/web" -exec touch {} +
  for stamp in "$app/build/web"/.*-services; do
    [[ -f "$stamp" ]] && touch "$stamp"
  done
  echo "✅ $demo: build restored from the image (${hash:0:7})"
  restored+=("$demo")
done <"$manifest"
echo "restore-builds: ${#restored[@]} restored${restored[*]:+: ${restored[*]}}"
