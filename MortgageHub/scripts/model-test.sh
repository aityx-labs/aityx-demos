#!/usr/bin/env bash
# Runs the mortgage rules (mortgagehub_api/models/proposal-check.json) on
# aityx.ai and checks the verdicts (mortgagehub_api/test/model_scenarios_test.dart).
# Run it after changing the model. The aityx settings come from the
# environment, else the repo's .env; the key is only exported to the test.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
# The demo's .env, else the repository's: a fresh checkout has no link
# until start-all.sh makes it.
env_file="$root/.env"
[[ -f "$env_file" ]] || env_file="$root/../.env"
for name in AITYX_API_KEY AITYX_URL; do
  if [[ -z "${!name:-}" && -f "$env_file" ]]; then
    value="$(sed -n "s/^${name}=//p" "$env_file" | tail -1)"
    [[ -n "$value" ]] && export "$name=$value"
  fi
done
unset value
[[ -n "${AITYX_API_KEY:-}" ]] || { echo "error: AITYX_API_KEY isn't set (see .env.example)" >&2; exit 1; }

cd "$root/mortgagehub_api"
dart pub get >/dev/null
exec dart test --run-skipped --tags aityx "$@"
