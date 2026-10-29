# Sourced by post-create.sh, post-start.sh and public-port.sh: everything
# they print, and what the services do as they come up, goes to
# MortgageHub/startup.log (git-ignored, like every *.log) with a UTC time
# on each line, as well as to the terminal. It's in the workspace, so it
# can be opened from the Explorer and downloaded to send along when the
# app doesn't start. It never holds a secret: keys and tokens are reported
# only as set or not set.

startup_log="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/MortgageHub/startup.log"

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

# startup_facts: what a failed start usually comes down to.
startup_facts() {
  local set
  echo "user $(id -un), $(uname -sm), in $(pwd)"
  echo "codespace: ${CODESPACE_NAME:-none (not a codespace)}"
  for name in AITYX_API_KEY GITHUB_TOKEN; do
    if [[ -n "${!name:-}" ]]; then set=set; else set="not set"; fi
    echo "$name: $set"
  done
  echo "AITYX_URL: ${AITYX_URL:-default}"
  echo "devbox: $(command -v devbox || echo missing) $(devbox version 2>/dev/null)"
  echo "nix: $(nix --version 2>/dev/null || echo missing)"
  echo "MortgageHub/.devbox: $([[ -d "$(dirname "$startup_log")/.devbox" ]] && echo present || echo missing)"
  df -h / 2>/dev/null | tail -1 | awk '{print "disk /: " $4 " free of " $2}'
}
