# Sourced by on-create.sh, update-content.sh, post-create.sh, post-start.sh
# and public-port.sh: everything they print, and what build-all.sh,
# start-all.sh and the services do as they come up,
# goes to startup.log at the root of the repository (git-ignored, like
# every *.log) with a UTC time on each line, as well as to the terminal.
# It's in the workspace, so it can be opened from the Explorer and
# downloaded to send along when a demo doesn't start. It never holds a
# secret: keys and tokens are reported only as set or not set.

startup_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
startup_log="$startup_root/startup.log"
# index_serves: which demos the index serves itself (the aityx demos).
# shellcheck source=../demos-toolchain.sh
source "$startup_root/demos-toolchain.sh"

# slog <message...>: one timestamped line in the log only.
slog() {
  printf '%s %s\n' "$(date -u '+%Y-%m-%d %H:%M:%S')" "$*" >>"$startup_log"
}

# startup_capture <tag>: from here on, the calling script's output goes to
# the terminal and, timestamped and tagged, to the log.
startup_capture() {
  local tag=$1
  export STARTUP_LOG_CAPTURED=1 # children already reach the log
  exec > >(while IFS= read -r line; do
    printf '%s [%s] %s\n' "$(date -u '+%Y-%m-%d %H:%M:%S')" "$tag" "$line"
  done | tee -a "$startup_log") 2>&1
}

# startup_demos: the folders whose services the dev container starts, one
# per line: each with a devbox.json and a process-compose.yaml, in the
# container's group (DEMOS_GROUP, set by its devcontainer.json: the folders
# whose group.id.txt names it), its index page among them (Index/ for
# aityx, datyx-index/ for datyx). Not the demos the index serves itself
# (startup_served).
startup_demos() {
  local config dir
  for config in "$startup_root"/*/devbox.json; do
    dir="$(dirname "$config")"
    [[ -f "$dir/process-compose.yaml" ]] || continue
    index_serves "$dir" && continue
    startup_in_group "$dir" || continue
    basename "$dir"
  done
}

# startup_served: the demos of the container's group that the index
# serves (the six aityx demos: web builds, no services), one per line.
startup_served() {
  local dir
  for dir in "$startup_root"/*/; do
    dir="${dir%/}"
    index_serves "$dir" && startup_in_group "$dir" && basename "$dir"
  done
  return 0
}

# startup_in_group <dir>: whether the folder is in the container's group
# (every folder when DEMOS_GROUP isn't set).
startup_in_group() {
  [[ -z "${DEMOS_GROUP:-}" || ! -f "$1/group.id.txt" ||
    "$(tr -d '[:space:]' <"$1/group.id.txt")" == "$DEMOS_GROUP" ]]
}

# startup_facts: what a failed start usually comes down to.
startup_facts() {
  local set name demo
  echo "user $(id -un), $(uname -sm), in $(pwd)"
  echo "codespace: ${CODESPACE_NAME:-none (not a codespace)}"
  for name in AITYX_API_KEY GITHUB_TOKEN; do
    if [[ -n "${!name:-}" ]]; then set=set; else set="not set"; fi
    echo "$name: $set"
  done
  if [[ -n "${AITYX_URL:-}" ]]; then
    echo "AITYX_URL: set"
  else
    echo "AITYX_URL: default"
  fi
  # The toolchain (see demos-toolchain.sh): the image's own tools, or
  # devbox, with each demo's install.
  echo "group: ${DEMOS_GROUP:-every demo}"
  echo "toolchain: ${DEMOS_TOOLCHAIN:-devbox}"
  if [[ "${DEMOS_TOOLCHAIN:-devbox}" == image ]]; then
    echo "flutter: $(command -v flutter || echo missing)"
    echo "process-compose: $(command -v process-compose || echo missing) $(process-compose version 2>/dev/null | head -1)"
    echo "java: $(command -v java || echo none)"
    echo "builds in the image: $(ls /opt/demos 2>/dev/null | grep -v manifest | tr '\n' ' ')"
  else
    echo "devbox: $(command -v devbox || echo missing) $(devbox version 2>/dev/null)"
    echo "nix: $(nix --version 2>/dev/null || echo missing)"
    for demo in $(startup_demos) $(startup_served); do
      [[ -f "$startup_root/$demo/devbox.json" ]] || continue
      echo "$demo/.devbox: $([[ -d "$startup_root/$demo/.devbox" ]] && echo present || echo missing)"
    done
  fi
  df -h / 2>/dev/null | tail -1 | awk '{print "disk /: " $4 " free of " $2}'
}
