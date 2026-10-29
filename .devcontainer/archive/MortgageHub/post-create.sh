#!/usr/bin/env bash
# Runs once when the dev container is created (postCreateCommand).
#
# This repository holds several samples. This container is for the Mortgage
# Hub demo app, so everything below runs in MortgageHub/, where devbox.json
# and devbox.lock live.
#
# Devbox has Nix resolve flakes through api.github.com: its own on
# `devbox install`, and nixpkgs when `devbox services up` first installs
# process-compose. Unauthenticated, that API allows 60 requests an hour per
# IP, and Codespaces share IPs, so it often answers 403. Codespaces provide
# a GITHUB_TOKEN; every shell hands it to Nix through NIX_CONFIG. The line
# added below reads the token from the environment, so it's never written
# to disk. Elsewhere, export GITHUB_TOKEN (e.g. `gh auth token`) if you hit
# the limit.
set -euo pipefail

# Everything below also goes to MortgageHub/startup.log (see startup-log.sh).
# shellcheck source=startup-log.sh
source "$(dirname "${BASH_SOURCE[0]}")/startup-log.sh"
startup_capture post-create
echo "===== post-create: $(date -u '+%Y-%m-%d %H:%M:%S') UTC"

line='[ -n "${GITHUB_TOKEN:-}" ] && export NIX_CONFIG="access-tokens = github.com=${GITHUB_TOKEN}"'
# ~/.profile for login shells; the top of ~/.bashrc, before its guard for
# non-interactive shells, for VS Code's terminals.
for rc in "$HOME/.profile" "$HOME/.bashrc"; do
  touch "$rc"
  if ! grep -qxF "$line" "$rc"; then
    printf '%s\n%s\n' "$line" "$(cat "$rc")" > "$rc"
  fi
done

if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  export NIX_CONFIG="access-tokens = github.com=${GITHUB_TOKEN}"
fi
export PATH="$HOME/.nix-profile/bin:$PATH"

# The app, two levels up from .devcontainer/MortgageHub/ and then into
# MortgageHub/. Resolved from this script rather than the caller's
# directory, so it does not matter where it is run from.
app="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/MortgageHub"
cd "$app" || { echo "post-create: cannot find $app" >&2; exit 1; }

# The aityx key is the user's own, passed in as a Codespaces secret (see
# devcontainer.json) or put in .env. Report only whether it arrived: the
# value must never be printed.
if [[ -n "${AITYX_API_KEY:-}" ]]; then
  echo "post-create: AITYX_API_KEY is set, the regulatory check can run"
else
  echo "post-create: AITYX_API_KEY is not set. Everything but the regulatory"
  echo "post-create: check works without it. To set it, add a Codespaces"
  echo "post-create: secret at https://github.com/settings/codespaces, or"
  echo "post-create: copy MortgageHub/.env.example to .env and fill it in."
fi

# A failure says which step failed and how much disk is left, the likeliest
# cause on a small machine.
fail() {
  echo "post-create: $1 failed" >&2
  df -h / /nix 2>/dev/null >&2 || true
  exit 1
}

# devbox.lock records each package's store path, so `devbox install`
# copies them from cache.nixos.org itself; only nixpkgs comes from GitHub.
startup_facts
echo "post-create: devbox install..."
started=$SECONDS
devbox install || fail "devbox install"
echo "post-create: devbox install took $((SECONDS - started)) s"

echo "post-create: done"
df -h /
