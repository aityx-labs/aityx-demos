#!/usr/bin/env bash
# Runs strategies (riverrace_app/lib/aityx/decision_request.dart,
# assets/models/river.json) on aityx.ai with fixed situations and checks
# which rule fires (riverrace_app/test/model_scenarios_test.dart, tagged
# aityx, which `flutter test` skips). Run it after changing the model. The
# aityx settings come from the environment, else the repository's .env;
# the key is only exported to the test, never put on a command line or
# printed.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
env_file="$root/../.env"
for name in AITYX_API_KEY AITYX_URL; do
  if [[ -z "${!name:-}" && -f "$env_file" ]]; then
    value="$(sed -n "s/^${name}=//p" "$env_file" | tail -1)"
    [[ -n "$value" ]] && export "$name=$value"
  fi
done
unset value
[[ -n "${AITYX_API_KEY:-}" ]] || { echo "error: AITYX_API_KEY isn't set (see ../.env.example)" >&2; exit 1; }

cd "$root/riverrace_app"
flutter pub get >/dev/null
exec flutter test --run-skipped --tags aityx "$@"
