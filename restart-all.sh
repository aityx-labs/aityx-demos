#!/usr/bin/env bash
# Syncs git, then restarts every demo's services from this checkout:
#
# 1. git (unless SYNC=0): fetches origin, pruning gone branches; fast-
#    forwards this checkout's branch to its upstream when it is clean and
#    has one; and fast-forwards main to origin/main, in whichever worktree
#    has it checked out (when that worktree is clean), else as a ref.
#    Nothing is merged, rebased, discarded or pushed: what can't be fast-
#    forwarded is said and left as it is.
# 2. stops them: ./stop-all.sh, then any demo's services still running
#    from another checkout or worktree of this repository (a devbox
#    process-compose whose config is <worktree>/<demo>/process-compose.yaml),
#    so their ports are free for this checkout's. Nothing else is stopped.
# 3. starts them: ./start-all.sh, which waits until each one answers.
#
#   ./restart-all.sh             # sync, then restart every demo
#   SYNC=0 ./restart-all.sh      # restart only
#   ./restart-all.sh HealthHub   # sync, then restart only these
set -uo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=demos-toolchain.sh
source "$root/demos-toolchain.sh"

if [[ "${SYNC:-1}" != 0 ]]; then
  echo "▶ git: fetching origin"
  git -C "$root" fetch --prune origin || echo "✗ git fetch failed: restarting what is here" >&2
  branch="$(git -C "$root" branch --show-current)"
  if [[ -n "$(git -C "$root" status --porcelain --untracked-files=no)" ]]; then
    echo "· $branch has uncommitted changes: not fast-forwarded"
  elif git -C "$root" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
    git -C "$root" merge --ff-only --quiet '@{upstream}' && echo "✅ $branch is at $(git -C "$root" rev-parse --short HEAD)" \
      || echo "· $branch can't be fast-forwarded to its upstream: left as it is"
  else
    echo "· $branch has no upstream: left as it is"
  fi
  if [[ "$branch" != main ]]; then
    main_tree="$(git -C "$root" worktree list --porcelain | awk '/^worktree /{w=$2} /^branch refs\/heads\/main$/{print w}')"
    if [[ -n "$main_tree" ]]; then
      if [[ -n "$(git -C "$main_tree" status --porcelain --untracked-files=no)" ]]; then
        echo "· main ($main_tree) has uncommitted changes: not fast-forwarded"
      else
        git -C "$main_tree" merge --ff-only --quiet origin/main && echo "✅ main is at $(git -C "$main_tree" rev-parse --short HEAD) ($main_tree)" \
          || echo "· main can't be fast-forwarded to origin/main: left as it is"
      fi
    elif git -C "$root" show-ref --verify --quiet refs/heads/main; then
      git -C "$root" fetch --quiet origin main:main && echo "✅ main is at $(git -C "$root" rev-parse --short main)" \
        || echo "· main can't be fast-forwarded to origin/main: left as it is"
    fi
  fi
fi

echo "▶ stopping"
"$root/stop-all.sh" "$@"

# The demos' services started from other worktrees of this repository:
# their process-compose's port, for those whose folder is one of ours.
if [[ "$DEMOS_TOOLCHAIN" == devbox ]]; then
  worktrees="$(git -C "$root" worktree list --porcelain | awk '/^worktree /{print $2}')"
  while read -r pid; do
    args="$(ps -o args= -p "$pid" 2>/dev/null)" || continue
    config="$(sed -n 's/.* -f \([^ ]*\/process-compose\.yaml\).*/\1/p' <<<"$args")"
    port="$(sed -n 's/.* -p \([0-9][0-9]*\).*/\1/p' <<<"$args")"
    [[ -n "$config" && -n "$port" ]] || continue
    demo_dir="$(dirname "$config")"
    demo="$(basename "$demo_dir")"
    [[ "$demo_dir" == "$root/$demo" ]] && continue  # this checkout's: stop-all.sh's
    grep -qxF "$(dirname "$demo_dir")" <<<"$worktrees" || continue
    [[ -f "$root/$demo/process-compose.yaml" ]] || continue
    if [[ $# -gt 0 ]] && ! printf '%s\n' "$@" | grep -qxF "$demo"; then
      continue
    fi
    echo "■ $demo: stopping its services from $(dirname "$demo_dir")"
    "${args%% *}" down -p "$port" >/dev/null 2>&1 && echo "✅ $demo stopped" || echo "✗ $demo: could not stop (port $port)" >&2
  done < <(pgrep -f 'process-compose' || true)
fi

echo "▶ starting"
exec "$root/start-all.sh" "$@"
