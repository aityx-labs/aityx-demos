#!/usr/bin/env bash
# Triages every complaint template with aityx, as the API triages an
# admission, and writes the sample classifications to
# docs/aityx-triage-cases.md (healthhub_api/tool/triage_cases.dart). Run it
# after changing the triage model (healthhub_api/data/triage/triage.json)
# or the complaints; it makes one aityx call per template. The aityx
# settings come from the environment, else .env (scripts/env.sh); the key
# is only exported to the tool, never printed or put on a command line.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=env.sh
source "$root/scripts/env.sh"
[[ -n "${AITYX_API_KEY:-}" ]] || { echo "error: AITYX_API_KEY isn't set (see .env.example)" >&2; exit 1; }

cd "$root/healthhub_api"
dart pub get >/dev/null
exec dart run tool/triage_cases.dart "$@"
