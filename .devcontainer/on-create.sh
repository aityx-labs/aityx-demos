#!/usr/bin/env bash
# Runs once, right after the container is created (onCreateCommand), and in
# a Codespaces prebuild, whose snapshot keeps its results: makes the
# toolchain and the builds ready, so that update-content.sh builds only
# what changed and post-start.sh's ./start-all.sh only has to start the
# demos. From the published image (DEMOS_TOOLCHAIN=image), that is copying
# the image's release web builds into the workspace; on a laptop's dev
# container with devbox, installing each demo's toolchain. It runs before the
# codespace is assigned to a user, so it has no Codespaces secrets: anything
# that needs them is in post-create.sh.
#
# Every demo of the container's group (DEMOS_GROUP; see startup_demos in
# startup-log.sh), its index page among them, gets `devbox install` in its
# folder. The Flutter ones lock the same Flutter, so the Nix store is
# filled once and the later installs are quick.
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

# Everything below also goes to startup.log at the root (see startup-log.sh).
# shellcheck source=startup-log.sh
source "$(dirname "${BASH_SOURCE[0]}")/startup-log.sh"
startup_capture on-create
echo "===== on-create: $(date -u '+%Y-%m-%d %H:%M:%S') UTC"

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

cd "$startup_root" || { echo "on-create: cannot find $startup_root" >&2; exit 1; }

# A failure says which step failed and how much disk is left, the likeliest
# cause on a small machine.
fail() {
  echo "on-create: $1 failed" >&2
  df -h / /nix 2>/dev/null >&2 || true
  exit 1
}

startup_facts
# shellcheck source=../demos-toolchain.sh
source "$startup_root/demos-toolchain.sh"
if [[ "$DEMOS_TOOLCHAIN" == image ]]; then
  # The group's image carries its toolchain and each of its demos' release
  # web builds: put the builds of the demos that haven't changed since the
  # image was made into the workspace (see image/restore-builds.sh).
  started=$SECONDS
  bash image/restore-builds.sh || fail "image/restore-builds.sh"
  echo "on-create: builds restored in $((SECONDS - started)) s"
else
  # Each devbox.lock records its packages' store paths, so `devbox install`
  # copies them from cache.nixos.org itself; only nixpkgs comes from GitHub.
  for demo in $(startup_demos); do
    echo "on-create: devbox install in $demo/..."
    started=$SECONDS
    (cd "$demo" && devbox install) || fail "devbox install in $demo"
    echo "on-create: devbox install in $demo took $((SECONDS - started)) s"
  done
fi

echo "on-create: done"
df -h /
