#!/usr/bin/env bash
# Runs the triage decision's rules (healthhub_api/data/triage/triage.json)
# on aityx.ai with fixed facts and checks the outcomes at each rule and
# threshold (healthhub_api/test/triage_model_test.dart, tagged aityx, which
# skips without a key). Run it after changing the triage model. The aityx
# settings come from the environment, else .env (scripts/env.sh); the key
# is only exported to the test, never printed or put on a command line.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=env.sh
source "$root/scripts/env.sh"
[[ -n "${AITYX_API_KEY:-}" ]] || { echo "error: AITYX_API_KEY isn't set (see .env.example)" >&2; exit 1; }

cd "$root/healthhub_api"
dart pub get >/dev/null
exec dart test --tags aityx "$@"
