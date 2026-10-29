#!/usr/bin/env bash
# Builds what `devbox services up` serves, and only what changed since the
# last build:
#   jar         the packaged API, datyx-api/target/quarkus-app/quarkus-run.jar
#   native      the API as a native executable, datyx-api/target/datyx-runner
#               (GraalVM native-image: minutes, and a few GB of memory)
#   test        the API's tests (./mvnw verify: a Postgres test container,
#               so Docker must be up)
#   image       the Docker image, `docker compose build api`
#   all         jar
# Run by scripts/api.sh before it serves (API_MODE=jar or native), by the
# repository's build-all.sh, or by hand: `bash scripts/build.sh jar` (or
# `devbox run build`, `make jar`). The version is X.Y.Z from the version
# files and the build time (scripts/version.sh): Maven gets it as
# -Drevision. The dashboard builds in its own folder, datyx-dashboard/.
#
# A target is rebuilt when its output is missing or older than any of its
# sources, so a start after no change builds nothing.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=version.sh
source "$root/scripts/version.sh"
cd "$root"
api="$root/datyx-api"

# stale <target> <source>...: whether the target is missing or older than a
# source (a file, or any file under a folder). Missing sources are skipped.
stale() {
  local target="$1" source
  shift
  [[ -e "$target" ]] || return 0
  for source in "$@"; do
    [[ -e "$source" ]] || continue
    [[ -n "$(find "$source" -newer "$target" -print 2>/dev/null | head -1)" ]] && return 0
  done
  return 1
}

api_sources=("$api/src" "$api/pom.xml" version.X.txt version.Y.txt)

build_jar() {
  if stale "$api/target/quarkus-app/quarkus-run.jar" "${api_sources[@]}"; then
    echo "build: jar (version $VERSION, datyx-api/target/quarkus-app/)"
    (cd "$api" && ./mvnw -B -q -DskipTests -Drevision="$VERSION" package)
  else
    echo "build: jar is up to date"
  fi
}

build_native() {
  if stale "$api/target/datyx-runner" "${api_sources[@]}"; then
    echo "build: native (version $VERSION, datyx-api/target/datyx-runner; minutes)"
    (cd "$api" && ./mvnw -B -q -DskipTests -Drevision="$VERSION" -Dnative package)
  else
    echo "build: native is up to date"
  fi
}

[[ $# -gt 0 ]] || set -- all
for target in "$@"; do
  case "$target" in
    jar) build_jar ;;
    native) build_native ;;
    test) (cd "$api" && ./mvnw -B -Drevision="$VERSION" verify) ;;
    image) REVISION="$VERSION" docker compose -f compose.yaml build api ;;
    all) build_jar ;;
    *)
      echo "error: unknown target '$target' (jar, native, test, image, all)" >&2
      exit 2
      ;;
  esac
done
