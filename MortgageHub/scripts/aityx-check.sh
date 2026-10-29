#!/usr/bin/env bash
# Checks the aityx.ai integration: runs the docs' cancellation example on
# System One (POST /v1/systemone, deterministic, the cheapest call) and
# checks its answers. Prints only the HTTP status and the answers; never the
# key.
#
# Settings, from the environment or the repo's .env (see .env.example):
#   AITYX_API_KEY  the API key (secret: never passed to the Flutter app)
#   AITYX_URL      the API's base URL; https://api.aityx.ai by default
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
# The demo's .env, else the repository's: a fresh checkout has no link
# until start-all.sh makes it.
env_file="$root/.env"
[[ -f "$env_file" ]] || env_file="$root/../.env"
setting() { # setting <name>: from the environment, else .env
  local value="${!1:-}"
  if [[ -z "$value" && -f "$env_file" ]]; then
    value="$(sed -n "s/^$1=//p" "$env_file" | tail -1)"
  fi
  printf '%s' "$value"
}
key="$(setting AITYX_API_KEY)"
url="$(setting AITYX_URL)"
url="${url:-https://api.aityx.ai}"
[[ -n "$key" ]] || { echo "error: AITYX_API_KEY isn't set (see .env.example)" >&2; exit 1; }
[[ "$url" =~ ^https://[A-Za-z0-9.-]+$ ]] || { echo "error: AITYX_URL must be an https origin, not '$url'" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

curl -fsS -o "$work/model.json" https://stage.aityx.ai/docs/examples/cancellation-model.json
jq -n --slurpfile model "$work/model.json" '{
  decision: $model[0],
  state: {customer_intent: "cancel_refund", plan_amount: 60, period_days: 30,
          unused_days: 10, accepted_on: "2026-10-21", refundable: true}
}' > "$work/request.json"

# The key goes to curl on stdin, so it's never on a command line (ps).
status="$(printf 'header = "Authorization: Bearer %s"\n' "$key" |
  curl -sS -K - -m 60 -H 'Content-Type: application/json' \
    -d @"$work/request.json" -o "$work/response.json" -w '%{http_code}' \
    "$url/v1/systemone")"
echo "POST $url/v1/systemone: HTTP $status"
if [[ "$status" != 200 ]]; then
  jq -c '.' "$work/response.json" 2>/dev/null || head -c 500 "$work/response.json"
  echo
  exit 1
fi

answers="$(jq -c '.answers | {
  request_type: .request_type.choice,
  refund_eligible: (if .refund_eligible.noul == 1 then 1 else 0 end),
  refund_amount: .refund_amount.number,
  processing_deadline: .processing_deadline.date
}' "$work/response.json")"
echo "answers: $answers"
expected='{"request_type":"cancel_refund","refund_eligible":1,"refund_amount":20,"processing_deadline":"2026-10-28"}'
if [[ "$answers" == "$expected" ]]; then
  echo "aityx ✅ the answers match the docs' example"
else
  echo "aityx ❌ expected $expected" >&2
  exit 1
fi
