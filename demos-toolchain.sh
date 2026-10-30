# Sourced by start-all.sh, stop-all.sh, build-all.sh and the dev container
# scripts: which demos the index serves itself (index_serves), and how a
# demo's services and builds are run, by DEMOS_TOOLCHAIN:
#   devbox  (the default, a laptop) each demo's devbox.json: `devbox
#           services up`, `devbox services stop`, `devbox run`
#   image   (a codespace, set by devcontainer.json) the dev container
#           image's Flutter and process-compose, on the PATH, with no devbox:
#           `process-compose up` per demo, detached, reached through a unix
#           socket in the temp folder (so the demos don't fight over
#           process-compose's port), its log in <demo>/process-compose.log
# Every function takes the demo's folder.

DEMOS_TOOLCHAIN="${DEMOS_TOOLCHAIN:-devbox}"
case "$DEMOS_TOOLCHAIN" in
  devbox | image) ;;
  *) echo "error: DEMOS_TOOLCHAIN must be devbox or image (got '$DEMOS_TOOLCHAIN')" >&2; exit 2 ;;
esac
demos_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# index_serves <dir>: whether the folder is a demo the index (Index/)
# serves itself, at /<slug>/ on its port, from the app's release web
# build: a folder of the index's group (Index/group.id.txt: aityx), other
# than Index/, with a scripts/build.sh. Such a demo runs in the browser
# and has no services of its own: start-all.sh builds it and starts the
# index, stop-all.sh stops the index.
index_serves() {
  local dir="${1%/}" group
  [[ "$(basename "$dir")" != Index && -f "$dir/scripts/build.sh" ]] || return 1
  group="$(tr -d '[:space:]' <"$demos_root/Index/group.id.txt" 2>/dev/null)"
  [[ -n "$group" && "$(tr -d '[:space:]' <"$dir/group.id.txt" 2>/dev/null)" == "$group" ]]
}

# index_slug <dir>: the demo's path on the index, its folder's name in
# lower case (MortgageHub: /mortgagehub/), as Index/bin/server.dart names it.
index_slug() {
  basename "${1%/}" | tr '[:upper:]' '[:lower:]'
}

# toolchain_missing <dir>: what the demo's toolchain still lacks to start
# its services, one item per line; nothing when it is ready. The dev
# container's post-start scripts check this before starting anything.
toolchain_missing() {
  local dir="$1"
  if [[ "$DEMOS_TOOLCHAIN" == image ]]; then
    command -v process-compose >/dev/null || echo "process-compose on the PATH"
    command -v flutter >/dev/null || echo "flutter on the PATH"
  else
    command -v devbox >/dev/null || echo "devbox on the PATH"
    [[ -d "$dir/.devbox" ]] || echo "$(basename "$dir")/.devbox (devbox install)"
  fi
}

# image_lacks <dir>: under the image, what the demo needs that the image
# doesn't carry (a JDK, for datyx's API); nothing otherwise. start-all.sh
# and build-all.sh skip such a demo instead of failing on it.
image_lacks() {
  [[ "$DEMOS_TOOLCHAIN" == image ]] || return 0
  if grep -qE '"(graalvm|jdk)' "$1/devbox.json" 2>/dev/null && ! command -v java >/dev/null; then
    echo "a JDK (java on the PATH)"
  fi
  return 0
}

# services_socket <dir>: the socket of a demo's detached process-compose.
services_socket() {
  printf '%s/aityx-demos-%s.sock\n' "${TMPDIR:-/tmp}" "$(basename "$1")"
}

# services_up <dir>: starts the demo's services, detached.
services_up() {
  local dir="$1"
  if [[ "$DEMOS_TOOLCHAIN" == image ]]; then
    (cd "$dir" && process-compose up -f process-compose.yaml -t=false -D \
      -U -u "$(services_socket "$dir")" --disable-dotenv -L "$dir/process-compose.log")
  else
    (cd "$dir" && devbox services up -b --pcflags "--tui=false" >/dev/null)
  fi
}

# services_running <dir>: whether the demo's services are up.
services_running() {
  local dir="$1" status
  if [[ "$DEMOS_TOOLCHAIN" == image ]]; then
    [[ -S "$(services_socket "$dir")" ]] &&
      process-compose list -U -u "$(services_socket "$dir")" >/dev/null 2>&1
  else
    # `devbox services ls` lists running processes with a PID and a status
    # (on stderr). Read whole: grep -q would close the pipe on devbox.
    status="$(cd "$dir" && devbox services ls 2>&1)" || return 2
    grep -q 'Running\|Pending\|Restarting' <<<"$status"
  fi
}

# services_down <dir>: stops the demo's services.
services_down() {
  local dir="$1"
  if [[ "$DEMOS_TOOLCHAIN" == image ]]; then
    process-compose down -U -u "$(services_socket "$dir")" >/dev/null 2>&1
  else
    (cd "$dir" && devbox services stop >/dev/null 2>&1)
  fi
}

# services_attach_hint <dir>: the command that shows a demo's services.
services_attach_hint() {
  if [[ "$DEMOS_TOOLCHAIN" == image ]]; then
    printf 'process-compose attach -U -u %s\n' "$(services_socket "$1")"
  else
    printf 'devbox services attach -c %s\n' "$(basename "$1")"
  fi
}

# run_build <dir>: the demo's scripts/build.sh, under its toolchain (a
# folder without a devbox.json: the Flutter on the PATH).
run_build() {
  local dir="$1"
  if [[ "$DEMOS_TOOLCHAIN" == image || ! -f "$dir/devbox.json" ]]; then
    (cd "$dir" && bash scripts/build.sh)
  else
    (cd "$dir" && devbox run -- bash scripts/build.sh)
  fi
}
