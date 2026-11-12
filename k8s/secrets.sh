#!/usr/bin/env bash
# Puts the root .env's settings in the cluster: the Secret demo-env in
# each group's namespace (aityx, multyx, datyx), which the demos read as
# environment variables (secretKeyRef, optional). Like a local run, the
# cluster runs on aityx staging: AITYX_API_KEY and AITYX_URL from the
# .env. The production settings (any *_PROD_* name) and empty values
# are left out, so nothing in the cluster reaches production. Run it
# again after changing the .env, then restart the demos that read it
# (BUILD=0 bash k8s/deploy.sh <demo>).
#
#   bash k8s/secrets.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$here/lib.sh"

env_file="$k8s_root/.env"
filtered="$(mktemp)"
chmod 600 "$filtered"
trap 'rm -f "$filtered"' EXIT
if [[ -f "$env_file" ]]; then
  # NAME=value lines with a value, but production's.
  grep -E '^[A-Za-z_][A-Za-z0-9_]*=.' "$env_file" | grep -vE '^[A-Za-z0-9_]*_PROD_' >"$filtered" || true
else
  echo "· no .env at the root: the demos get no aityx key (see .env.example)" >&2
fi
# The .env's aityx keys are staging's, and a server without AITYX_URL
# calls production, which refuses them: without the URL, the keys stay
# out too.
if ! grep -qE '^AITYX_URL=.' "$filtered"; then
  kept="$(grep -vE '^(AITYX_API_KEY|POKERTOUR_LEADERBOARD_KEY|TATYX_LEADERBOARD_KEY|TATYX_PLAYER_KEY)=' "$filtered" || true)"
  printf '%s\n' "$kept" >"$filtered"
  echo "· no AITYX_URL in .env: its aityx keys are left out of demo-env (they're staging's)" >&2
fi

for group in aityx multyx datyx; do
  kc -n "$group" create secret generic demo-env --from-env-file="$filtered" \
    --dry-run=client -o yaml | kc apply -f - >/dev/null
done
echo "✅ Secret demo-env in aityx, multyx and datyx: $(cut -d= -f1 "$filtered" | tr '\n' ' ')"
