#!/usr/bin/env bash
# Checks Poker Tour on the local cluster from this host, on
# http://127.0.0.1:19810 (k8s/deploy.sh runs it last): the app, the API
# and its settings, the tour read from Floci's bucket and table and the
# same there, the signed-in calls refusing a caller without a Google
# token, and the relay reaching aityx staging. One line per check; exits
# 1 when one fails. Prints no secret: the keys are only said to be set.
#
#   bash PokerTour/k8s/verify.sh
#   TOURNAMENT=1 bash PokerTour/k8s/verify.sh
#
# TOURNAMENT=1 also plays a tournament, as the schedule would, and waits
# for its result (a minute or two, up to TOURNAMENT_TIMEOUT seconds,
# 900 by default; a few hundred aityx calls on the leaderboard's key).
# Nothing in the API starts one without an admin's Google sign-in, which
# needs a browser, so it is queued in Floci's table, as the API would
# queue it, and the server is restarted: a server plays what it finds
# queued at its start.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../../k8s/lib.sh
source "$here/../../k8s/lib.sh"

ns="$(k8s_namespace PokerTour)"
base="http://127.0.0.1:19810"
floci_pod=pokertour-floci-0
store=pokertour-local
failed=0
ok() { echo "✅ $*"; }
bad() {
  echo "✗ $*"
  failed=1
}

# fetch <curl arguments...>: the answer's status in $code and its body in
# $body (status 000 when nothing answered).
fetch() {
  local out
  out="$(curl -s -m 15 -w $'\n%{http_code}' "$@" 2>/dev/null)"
  code="${out##*$'\n'}"
  body="${out%$'\n'*}"
  [[ -n "$code" ]] || code=000
}
# field <jq filter>: the filter on $body, empty when it isn't JSON.
field() {
  jq -r "$1" <<<"$body" 2>/dev/null
}
# aws_in_floci <aws arguments...>: the AWS CLI in Floci's pod, on Floci
# itself (the image's AWS_ENDPOINT_URL and dummy credentials).
aws_in_floci() {
  kc -n "$ns" exec "$floci_pod" -c floci -- aws "$@"
}

# The server, after a restart: up to a minute for /api/health.
for _ in $(seq 30); do
  fetch "$base/api/health"
  [[ "$code" == 200 ]] && break
  sleep 2
done

# /api/health reads the leaderboard's file and the strategies, from
# Floci's bucket and table: a 200 is the server reading its store.
if [[ "$code" == 200 && "$(field .ok)" == true ]]; then
  ok "/api/health: ok, the tour read from Floci ($(field .entries) strategies)"
  [[ "$(field .aityx)" == true ]] && ok "the leaderboard's key is set on the server (never served)" ||
    bad "the leaderboard's key isn't set: POKERTOUR_LEADERBOARD_KEY or AITYX_API_KEY in demo-env (k8s/secrets.sh)"
  [[ "$(field .auth)" == true ]] && ok "the Google sign-in is set up (a client id)" ||
    bad "the sign-in isn't set up: POKERTOUR_OIDC_CLIENT_ID in demo-env (k8s/secrets.sh)"
  [[ "$(field .runner.enabled)" == true ]] && ok "the leaderboard plays (next on the schedule: $(field .runner.nextRunAt))" ||
    bad "the leaderboard doesn't play (POKERTOUR_RUN, or no key)"
else
  bad "/api/health: HTTP $code"
fi

# The app: the release web build, served under /pokertour/ (its base
# href), and its compiled code; / sends there.
fetch "$base/pokertour/"
if [[ "$code" == 200 && "$body" == *'<base href="/pokertour/">'* ]]; then
  fetch -o /dev/null "$base/pokertour/main.dart.js"
  if [[ "$code" == 200 ]]; then
    ok "/pokertour/: the app (base href /pokertour/, main.dart.js)"
  else
    bad "/pokertour/main.dart.js: HTTP $code"
  fi
else
  bad "/pokertour/: HTTP $code, or not the app's page"
fi
location="$(curl -s -m 10 -o /dev/null -w '%{http_code} %{redirect_url}' "$base/")"
[[ "$location" == "301 $base/pokertour/" ]] && ok "/ sends to /pokertour/" || bad "/: $location"

# What the app is told: aityx staging (never production, which the
# cluster's staging keys aren't for), through the relay on this origin,
# and the Google client to sign in with.
fetch "$base/api/config"
url="$(field .aityxUrl)"
if [[ "$code" == 200 && -n "$url" && "$url" != https://api.aityx.ai* && "$(field .aityxRelay)" == /aityx/ ]]; then
  ok "/api/config: aityx at $url, through the relay /aityx/"
else
  bad "/api/config: HTTP $code, aityx at '${url:-?}' (production, or no relay)"
fi
if [[ "$(field '.auth.enabled')" == true && -n "$(field '.auth.clientId // empty')" ]]; then
  ok "/api/config: the Google client id, issuer $(field .auth.issuer)"
else
  bad "/api/config: no Google client id"
fi

# The leaderboard: the five presets (from the models) with their records
# and the history (leaderboard.json in Floci's bucket), the queue (Floci's
# table) and the runner's state.
fetch "$base/api/leaderboard"
presets="$(field '[.standings[] | select(.preset)] | length')"
latest="$(field '.history[0].number // "none"')"
state="$(field .runner.state)"
detail="$(field .runner.detail)"
if [[ "$code" == 200 && "$presets" == 5 ]]; then
  ok "/api/leaderboard: the 5 presets, $(field '.history | length') tournaments in the history (the latest: $latest), $(field '.runner.queue | length') queued, the runner $state"
else
  bad "/api/leaderboard: HTTP $code, ${presets:-no} presets"
fi
# The runner's last word: aityx refusing the leaderboard's key is a
# failure here; anything else (staging's other troubles) is reported.
if [[ "$state" == error && "$detail" =~ HTTP\ (401|403) ]]; then
  bad "the runner: aityx refused the leaderboard's key ($detail)"
else
  ok "the runner: $state ($detail)"
fi

# Floci holds the tour: the bucket and the table, and the history the API
# answered is the one in the bucket's leaderboard.json.
if aws_in_floci s3api head-bucket --bucket "$store" >/dev/null 2>&1; then
  ok "Floci: the bucket $store"
else
  bad "Floci: no bucket $store (pod $floci_pod)"
fi
table="$(aws_in_floci dynamodb describe-table --table-name "$store" --query Table.TableStatus --output text 2>/dev/null)"
[[ "$table" == ACTIVE ]] && ok "Floci: the table $store, $table" || bad "Floci: the table $store: ${table:-missing}"
stored="$(aws_in_floci s3 cp "s3://$store/leaderboard.json" - 2>/dev/null | jq -r '.history[0].number // "none"' 2>/dev/null)"
[[ -n "$stored" ]] || stored=none
if [[ "$stored" == "$latest" ]]; then
  ok "the API's history is Floci's: s3://$store/leaderboard.json's latest tournament is $stored too"
else
  bad "the API's latest tournament ($latest) isn't s3://$store/leaderboard.json's ($stored)"
fi

# Signed in: every call that reads or changes a player's strategies, and
# starting a tournament, wants a Google ID token for this client. None can
# be had without a browser (the client lists this origin, but a sign-in
# is Google's popup), so each must refuse cleanly: 401, not 503 (no
# sign-in set up) or 500.
refused=() other=()
for call in "GET /api/me" "PUT /api/me" "GET /api/strategies" "POST /api/strategies" \
  "DELETE /api/strategies/rock" "POST /api/tournaments"; do
  method="${call% *}" path="${call#* }"
  if [[ "$method" == GET ]]; then
    fetch "$base$path"
  else
    fetch -X "$method" -H 'Content-Type: application/json' -d '{}' "$base$path"
  fi
  [[ "$code" == 401 ]] && refused+=("$call") || other+=("$call: $code")
done
fetch -H 'Authorization: Bearer not-a-google-token' "$base/api/strategies"
[[ "$code" == 401 ]] && refused+=("a forged token") || other+=("a forged token: $code")
if [[ ${#other[@]} -eq 0 ]]; then
  ok "signed-in calls refuse a caller without a Google token, 401: ${#refused[@]} of them (a sign-in itself can't be checked without a browser; the client lists this origin)"
else
  bad "signed-in calls: ${other[*]}"
fi

# The relay to aityx staging (a browser can't call staging): it adds no
# key of its own, so without one the server refuses, and with a key aityx
# refuses, it is aityx's answer that comes back, from staging over https.
fetch -X POST -H 'Content-Type: application/json' -d '{}' "$base/aityx/v1/systemone"
if [[ "$code" == 401 && "$(field .detail)" == *"no aityx key"* ]]; then
  ok "the relay adds no key of its own: 401 without the player's"
else
  bad "the relay without a key: HTTP $code"
fi
fetch -X POST -H 'Content-Type: application/json' -H 'Authorization: Bearer k8s-verify-not-a-key' -d '{}' \
  "$base/aityx/v1/systemone"
if [[ "$code" == 401 && -n "$(field '.request_id // empty')" ]]; then
  ok "the relay reaches aityx staging: it refused a made-up key ($(field .detail))"
else
  bad "the relay to aityx: HTTP $code ($(field '.detail // empty'))"
fi

# A tournament, when asked for: one more in the history than above.
if [[ "${TOURNAMENT:-0}" == 1 && -z "$latest" ]]; then
  bad "a tournament: not tried, the leaderboard didn't answer"
elif [[ "${TOURNAMENT:-0}" == 1 ]]; then
  deadline=$((SECONDS + ${TOURNAMENT_TIMEOUT:-900}))
  if [[ "$state" != playing ]]; then
    at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    data="$(jq -cn --arg at "$at" '{source: "admin", at: $at, by: "verify.sh"}')"
    item="$(jq -cn --arg data "$data" '{pk: {S: "QUEUE"}, sk: {S: "admin"}, data: {S: $data}}')"
    # Queued unless an admin's is waiting already: that one is played.
    aws_in_floci dynamodb put-item --table-name "$store" --item "$item" \
      --condition-expression 'attribute_not_exists(pk)' >/dev/null 2>&1 || true
    kc -n "$ns" rollout restart deployment/pokertour >/dev/null
    kc -n "$ns" rollout status deployment/pokertour --timeout=180s >/dev/null ||
      bad "the server didn't come back after its restart"
  fi
  played=""
  while ((SECONDS < deadline)); do
    fetch "$base/api/leaderboard"
    now="$(field '.history[0].number // "none"')"
    if [[ "$code" == 200 && -n "$now" && "$now" != "$latest" ]]; then
      played="$now"
      break
    fi
    sleep 5
  done
  if [[ -n "$played" ]]; then
    calls="$(field '.history[0].calls')"
    seats="$(field '.history[0].places | length')"
    if [[ "$calls" =~ ^[0-9]+$ && "$calls" -gt 0 && "$seats" -ge 2 ]]; then
      ok "a tournament: #$played, $seats strategies, $(field '.history[0].hands') hands, $calls aityx calls on the leaderboard's key, won by $(field '[.history[0].places[] | select(.place == 1)][0].name')"
    else
      bad "a tournament: #$played, but $seats strategies and ${calls:-no} aityx calls"
    fi
  else
    fetch "$base/api/leaderboard"
    bad "a tournament: none finished in ${TOURNAMENT_TIMEOUT:-900} s (the runner: $(field .runner.state), $(field .runner.detail))"
  fi
fi

exit $failed
