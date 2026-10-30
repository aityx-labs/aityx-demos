#!/usr/bin/env bash
# Runs the mortgage rules (mortgagehub_app/assets/models/proposal-check.json)
# on aityx.ai and checks the verdicts: the app's tests tagged `aityx`, which
# `flutter test` skips. Run it after changing the model.
#
#   bash scripts/model-test.sh            # test/model_scenarios_test.dart
#   bash scripts/model-test.sh <args>...  # flutter test's own, for instance
#                                         # test/targeted_proposal_live_test.dart
#                                         # (Fill random's targets, 90 calls)
#
# AITYX_API_KEY and AITYX_URL come from the environment, else the
# repository's .env (see ../.env.example). The key is only exported to the
# test: never on a command line, never printed.
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

[[ $# -gt 0 ]] || set -- test/model_scenarios_test.dart
cd "$root/mortgagehub_app"
flutter pub get >/dev/null
exec flutter test --run-skipped --tags aityx "$@"
