# Sourced by build-image.sh and restore-builds.sh: what a demo's release
# web build is made from, as one git-derived key, so a build carried by
# the image is reused only while those inputs are unchanged, and a change
# anywhere else in the demo's folder (its README, its API) doesn't throw
# the build away. The inputs are what scripts/build.sh compares the build
# with, plus how it builds: the app package (lib/, web/, assets/,
# pubspec), version.X.txt and version.Y.txt, scripts/ (build.sh and the
# dart-defines) and devbox.lock (the Flutter version).

# app_package <demo>: the demo's Flutter app package in HEAD, relative to
# the repository (Cellfie/cellfie_app, datyx-dashboard/datyx_dashboard):
# its first folder whose pubspec.yaml depends on the Flutter SDK; nothing
# for a demo without one (datyx, a Java API).
app_package() {
  local dir
  while IFS= read -r dir; do
    if git show "HEAD:$dir/pubspec.yaml" 2>/dev/null | grep -q 'sdk: flutter'; then
      echo "$dir"
      return 0
    fi
  done < <(git ls-tree -d --name-only HEAD "$1/")
  return 0
}

# build_key_paths <demo>: the paths, relative to the repository, one per
# line, that exist in HEAD.
build_key_paths() {
  local demo="$1" app path
  app="$(app_package "$demo")"
  [[ -n "$app" ]] || return 0
  for path in "$app" "$demo/scripts" "$demo/version.X.txt" "$demo/version.Y.txt" "$demo/devbox.lock"; do
    git rev-parse --quiet --verify "HEAD:$path" >/dev/null 2>&1 && echo "$path"
  done
}

# sha256: the checksum of stdin, with what the system has (coreutils on
# Linux, perl's shasum on macOS).
sha256() {
  if command -v sha256sum >/dev/null; then sha256sum; else shasum -a 256; fi
}

# build_key <demo>: the key, 40 hex digits, from the git object ids of the
# paths above in HEAD; empty when the demo has no app package in HEAD.
build_key() {
  local demo="$1" paths
  paths="$(build_key_paths "$demo")"
  [[ -n "$paths" ]] || return 0
  while IFS= read -r path; do
    printf '%s %s\n' "$path" "$(git rev-parse "HEAD:$path")"
  done <<<"$paths" | sha256 | cut -c1-40
}
