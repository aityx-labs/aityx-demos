#!/usr/bin/env bash
# Runs once when the container is first assigned to a user
# (postCreateCommand), after on-create.sh (the toolchains) and
# update-content.sh (the builds), which a Codespaces prebuild runs ahead of
# time; this one never runs in a prebuild, so it is where the user's own
# Codespaces secrets can be seen. It only reports whether they arrived:
# secret values must never be printed.
set -euo pipefail

# Everything below also goes to startup.log at the root (see startup-log.sh).
# shellcheck source=startup-log.sh
source "$(dirname "${BASH_SOURCE[0]}")/startup-log.sh"
startup_capture post-create
echo "===== post-create: $(date -u '+%Y-%m-%d %H:%M:%S') UTC"

cd "$startup_root" || { echo "post-create: cannot find $startup_root" >&2; exit 1; }

# The aityx key and optional endpoint are the user's own Codespaces secrets
# (see devcontainer.json) or can be set in the root .env.
if [[ -n "${AITYX_API_KEY:-}" ]]; then
  echo "post-create: AITYX_API_KEY is set; the demos can call aityx"
else
  echo "post-create: AITYX_API_KEY is not set. The apps open without it, but"
  echo "post-create: nothing that runs on aityx works. To set it, add a"
  echo "post-create: Codespaces secret at https://github.com/settings/codespaces,"
  echo "post-create: or copy .env.example to .env at the root and fill it in."
fi
if [[ -n "${AITYX_URL:-}" ]]; then
  echo "post-create: AITYX_URL is set; the demos will use that endpoint"
else
  echo "post-create: AITYX_URL is not set; demos use https://api.aityx.ai"
fi

# Whether this codespace came from a prebuild, with the toolchains and the
# builds already in place (see on-create.sh and update-content.sh).
if [[ -n "${CODESPACE_NAME:-}" ]]; then
  action="$(jq -r '.ACTION_NAME // empty' /workspaces/.codespaces/shared/environment-variables.json 2>/dev/null || true)"
  case "$action" in
    createFromPrebuild) echo "post-create: created from a prebuild" ;;
    "") ;;
    *) echo "post-create: created without a prebuild ($action)" ;;
  esac
fi

startup_facts
echo "post-create: done"
