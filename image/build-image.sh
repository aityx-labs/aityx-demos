#!/usr/bin/env bash
# Builds a demo group's dev container image (Containerfile), with the
# release web build of every demo in the group inside, and pushes it to
# Docker Hub (public, so anyone can create a codespace from it; the
# organization's GHCR packages can't be made public), tagged with the
# commit and as latest. One image per group, each used by its own dev
# container (.devcontainer/<group>/):
#   aityx  docker.io/aletyxcode/samples-and-demos-aityx: Flutter and the
#          six aityx demos' release web builds, which the index serves
#          at /<slug>/ (the demos have no APIs)
#   datyx  docker.io/aletyxcode/samples-and-demos-datyx: Flutter, GraalVM
#          and the datyx API's Maven dependencies, and the builds of the
#          datyx dashboard and HealthHub
# A group is the folders whose group.id.txt names it. Run from a laptop
# with Docker and devbox, on a clean checkout of the commit the image is
# for (usually main):
#
#   docker login -u aletyxcode                   # once; a Read & Write access token
#   bash image/build-image.sh aityx              # ./build-all.sh, then build and push
#   PUSH=0 bash image/build-image.sh datyx       # build only, loaded locally
#
# The web builds are platform-independent, so they are made here natively
# with ./build-all.sh (devbox) and copied into the image, which is built
# for linux/amd64, the Codespaces machines, through Docker's emulation
# (its Flutter steps take a few minutes). No API binaries are in the
# image: the aityx demos have none, and the datyx group's compile in a
# codespace in seconds.
#
# The staging folder image/context/<group>/ (git-ignored) holds what the
# Containerfile copies: the pubspecs (the shared packages/ ones too), the
# Maven projects' poms (for their
# dependencies), the builds and the manifest, which records each demo's
# build key (build-key.sh: the git ids of what the web build is made
# from); restore-builds.sh reuses a build only for a demo whose key is
# unchanged, so those paths must be committed.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
group="${1:-}"
case "$group" in
  aityx | datyx) ;;
  *) echo "usage: bash image/build-image.sh aityx|datyx" >&2; exit 2 ;;
esac
image="${IMAGE:-docker.io/aletyxcode/samples-and-demos-$group}"
cd "$root"
# shellcheck source=build-key.sh
source "$root/image/build-key.sh"
# shellcheck source=../demos-toolchain.sh
source "$root/demos-toolchain.sh"

sha="$(git rev-parse --short HEAD)"
# The group's demos with a web build to carry: a committed app package and
# a scripts/build.sh. A folder without one (new, or not a Flutter demo) is
# left out; its codespace builds it.
demos=()
for build in */scripts/build.sh; do
  dir="${build%%/*}"
  [[ "$(tr -d '[:space:]' <"$dir/group.id.txt" 2>/dev/null)" == "$group" ]] || continue
  if [[ -z "$(build_key "$dir")" ]]; then
    echo "· $dir: no Flutter app committed: no web build for the image to carry"
    continue
  fi
  demos+=("$dir")
done

for demo in "${demos[@]}"; do
  dirty="$(build_key_paths "$demo" | xargs git status --porcelain --)"
  if [[ -n "$dirty" ]]; then
    echo "error: uncommitted changes in what $demo's web build is made from:" >&2
    echo "$dirty" >&2
    echo "error: the image records their committed git ids, so commit or stash first" >&2
    exit 1
  fi
done

echo "==> building the demos (./build-all.sh ${demos[*]})"
./build-all.sh "${demos[@]}"

context="$root/image/context/$group"
rm -rf "$context"
mkdir -p "$context/builds" "$context/pubspecs" "$context/maven"
: >"$context/builds/manifest"
for demo in "${demos[@]}"; do
  app="$(app_package "$demo")"
  if index_serves "$demo"; then
    # A demo the index serves: built for its own path there.
    slug="$(index_slug "$demo")"
    if ! grep -q "<base href=\"/$slug/\">" "$app/build/web/index.html" 2>/dev/null; then
      echo "error: $app/build/web isn't built for /$slug/ (its index.html's base href)" >&2
      exit 1
    fi
  # The record of the settings scripts/build.sh made the build with
  # (.datyx-services for the datyx dashboard, ...).
  elif ! compgen -G "$app/build/web/.*-services" >/dev/null; then
    echo "error: $app/build/web isn't a services build" >&2
    exit 1
  fi
  mkdir -p "$context/builds/$demo"
  cp -a "$app/build/web" "$context/builds/$demo/web"
  printf '%s %s\n' "$demo" "$(build_key "$demo")" >>"$context/builds/manifest"
done
# Every Dart and Flutter package of the group's folders (apps and APIs),
# and every Maven project (datyx's API): only what fetching their
# dependencies needs. Then the shared packages (packages/<name>) the
# group's apps depend on by path, at the same place relative to them.
for dir in */; do
  dir="${dir%/}"
  [[ "$(tr -d '[:space:]' <"$dir/group.id.txt" 2>/dev/null)" == "$group" ]] || continue
  for pkg in "$dir"/*/; do
    pkg="${pkg%/}"
    if [[ -f "$pkg/pubspec.yaml" && -f "$pkg/pubspec.lock" ]]; then
      mkdir -p "$context/pubspecs/$pkg"
      cp "$pkg/pubspec.yaml" "$pkg/pubspec.lock" "$context/pubspecs/$pkg/"
    fi
    if [[ -f "$pkg/pom.xml" && -f "$pkg/mvnw" ]]; then
      mkdir -p "$context/maven/$pkg"
      cp -a "$pkg/pom.xml" "$pkg/mvnw" "$pkg/.mvn" "$context/maven/$pkg/"
    fi
  done
done
if grep -rqs --include=pubspec.yaml 'packages/' "$context/pubspecs"; then
  for pkg in packages/*/; do
    pkg="${pkg%/}"
    [[ -f "$pkg/pubspec.yaml" ]] || continue
    mkdir -p "$context/pubspecs/$pkg"
    cp "$pkg/pubspec.yaml" "$context/pubspecs/$pkg/"
    [[ -f "$pkg/pubspec.lock" ]] && cp "$pkg/pubspec.lock" "$context/pubspecs/$pkg/"
  done
fi
echo "==> manifest:"
cat "$context/builds/manifest"
echo "==> packages: $(cd "$context" && find pubspecs maven -name pubspec.yaml -o -name pom.xml | sort | tr '\n' ' ')"

push=(--push)
[[ "${PUSH:-1}" == 0 ]] && push=(--load)
echo "==> docker buildx build $image:$sha ($image:latest)"
docker buildx build --platform linux/amd64 -f "$root/image/Containerfile" \
  --build-arg GROUP="$group" -t "$image:$sha" -t "$image:latest" "${push[@]}" "$context"
echo "==> done: $image:$sha and $image:latest"
