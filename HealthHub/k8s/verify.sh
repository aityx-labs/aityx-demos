#!/usr/bin/env bash
# Checks HealthHub on the local cluster, from this host: the app at
# http://127.0.0.1:19801/app/ and its compiled script; the API through the
# web app's proxy, with its database and Kafka; the simulation's moves
# flowing through Kafka and back (GET /api/events, read twice); Flink's
# healthhub-admissions-hourly job RUNNING (its web UI on :19806) and its
# counts of the live run in admissions_hourly, read back by the API; an
# admission triaged by aityx, through datyx's aityx gateway; and
# /api/datyx/*, which needs a Google sign-in, refusing cleanly without one.
# One line per check; exits 1 if any fails. Never prints a secret.
#
#   bash HealthHub/k8s/verify.sh
set -uo pipefail

web="http://127.0.0.1:19801"
flink="http://127.0.0.1:19806"
failed=0
ok() { echo "✅ $*"; }
bad() {
  echo "✗ $*"
  failed=1
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# more <a> <b>: whether a is a number greater than b (anything else, such
# as an empty answer or jq's null, is not).
more() {
  [[ "$1" =~ ^[0-9]+$ && "$2" =~ ^[0-9]+$ && "$1" -gt "$2" ]]
}

# get <path> [file]: the API (or the app) through the web app, its body in
# file (or $tmp/body); prints the HTTP status.
get() {
  curl -s --max-time 10 -o "${2:-$tmp/body}" -w '%{http_code}' "$web$1"
}

# The app: its page under /app/, and the compiled app it loads.
code="$(get /app/ "$tmp/page.html")"
if [[ "$code" == 200 ]] && grep -q '<base href="/app/">' "$tmp/page.html"; then
  ok "the app's page answers on $web/app/"
else
  bad "the app's page on $web/app/: HTTP $code"
fi
code="$(get /app/main.dart.js "$tmp/main.dart.js")"
size="$(wc -c <"$tmp/main.dart.js" 2>/dev/null | tr -d ' ')"
if [[ "$code" == 200 ]] && more "${size:-}" 100000; then
  ok "/app/main.dart.js, the compiled app, answers ($((size / 1024)) KB)"
else
  bad "/app/main.dart.js: HTTP $code, ${size:-0} bytes"
fi

# The API through the web app's proxy: /api/health answers ok, with the
# database and Kafka's REST proxy up. Just after a deploy they may still
# be connecting, so ask again for up to 15 s.
deadline=$((SECONDS + 15))
while :; do
  code="$(get /api/health)"
  health="$(jq -c . "$tmp/body" 2>/dev/null)"
  [[ "$code" == 200 && "$(jq -r '.ok and .db and .kafka and .simulation' <<<"$health" 2>/dev/null)" == true ]] && break
  [[ $SECONDS -ge $deadline ]] && break
  sleep 3
done
if [[ "$(jq -r '.ok and .db and .kafka and .simulation' <<<"$health" 2>/dev/null)" == true ]]; then
  ok "/api/health through the web proxy: ok, database, Kafka and the simulation up (aityx: $(jq -r .aityx <<<"$health"), triage: $(jq -r .triage <<<"$health"))"
else
  bad "/api/health through the web proxy: HTTP $code ${health:-no answer}"
fi

# The simulation's moves through Kafka: the API publishes every person's
# move, every turn (2.5 s), to healthhub.people.moves through the REST
# proxy, and its feed reads them back; GET /api/events counts what the feed
# read ("total") and says the simulated clock of the newest ("now"). Both
# must move on between two reads a few turns apart, and GET /api/people,
# the map's people as read back, must hold them.
read_feed() {
  [[ "$(get '/api/events?limit=1')" == 200 ]] || return 1
  jq -er 'select(.enabled) | "\(.total) \(.now.day // 0):\(.now.simTime // "") \(.perSecond)"' "$tmp/body" 2>/dev/null
}
first="$(read_feed)"
sleep 6
second="$(read_feed)"
people="$( [[ "$(get /api/people)" == 200 ]] && jq -r '.people | length' "$tmp/body" 2>/dev/null)"
read -r total1 clock1 _ <<<"${first:-0 none 0}"
read -r total2 clock2 rate <<<"${second:-0 none 0}"
if more "$total2" "${total1:-0}" && [[ "$clock2" != "$clock1" ]] && more "${people:-}" 0; then
  ok "moves flow through Kafka: $((total2 - total1)) records read back in 6 s (${rate}/s), the simulated clock from day $clock1 to $clock2, $people people on the map"
else
  bad "moves through Kafka: records read back ${total1} then ${total2}, clock $clock1 then $clock2, ${people:-no} people on the map"
fi

# Flink's job, on its web UI.
state="$(curl -s --max-time 5 "$flink/jobs/overview" |
  jq -r '[.jobs[] | select(.name == "healthhub-admissions-hourly") | .state] | if index("RUNNING") then "RUNNING" else (join(",") | if . == "" then "absent" else . end) end' 2>/dev/null)"
if [[ "$state" == RUNNING ]]; then
  ok "Flink's healthhub-admissions-hourly job is RUNNING ($flink/jobs/overview)"
else
  bad "Flink's healthhub-admissions-hourly job: ${state:-no answer from $flink}"
fi

# The job's counts in admissions_hourly: the series of the current run
# (not the history run the API writes at start) at the hospitals of the
# latest admissions, read back by the API, hold admissions. Right after a
# deploy the job was just resubmitted and recounts the topic from its
# start before it reaches this run (Flink flushes every second), so ask
# again for up to 50 s.
deadline=$((SECONDS + 50))
counted=""
while :; do
  if [[ "$(get '/api/admissions?limit=20')" == 200 ]]; then
    for hospital in $(jq -r '[.admissions[].hospitalId] | unique | .[:5] | .[]' "$tmp/body" 2>/dev/null); do
      [[ "$(get "/api/care-centers/$hospital/admissions?hours=72")" == 200 ]] || continue
      counted="$(jq -r 'select(.current) | "\([.hours[].admissions] | add) \(.run)"' "$tmp/body" 2>/dev/null)"
      more "${counted%% *}" 0 && break 2
    done
  fi
  [[ $SECONDS -ge $deadline ]] && break
  sleep 3
done
if more "${counted%% *}" 0; then
  ok "admissions_hourly has the live run's counts from Flink: ${counted%% *} admissions in 72 h at hospital $hospital (run ${counted#* })"
else
  bad "admissions_hourly: no counts of the current run at the latest admissions' hospitals (${counted:-no current run})"
fi

# A triage decided by aityx: an admission with its level, and the latest
# through datyx's aityx gateway (via datyx), which HealthHub uses with
# datyx's service token; it falls back to aityx directly when datyx can't
# pass it on. Admissions arrive every few seconds, so ask again for up to
# 20 s.
deadline=$((SECONDS + 20))
while :; do
  code="$(get '/api/triage?limit=50')"
  decided="$(jq -r '[.triaged[] | select(.level != null and .error == null)] | length' "$tmp/body" 2>/dev/null)"
  via_datyx="$(jq -r '[.triaged[] | select(.level != null and .via == "datyx")] | length' "$tmp/body" 2>/dev/null)"
  more "${decided:-}" 0 && more "${via_datyx:-}" 0 && break
  [[ $SECONDS -ge $deadline ]] && break
  sleep 5
done
if more "${decided:-}" 0; then
  ok "aityx triaged admissions: $decided of the latest decided ($(jq -r '[.triaged[] | select(.level != null)][0] | "\(.level), \(.area), wait \(.waitMinutes) min, via \(.via)"' "$tmp/body"))"
else
  bad "aityx triaged no admission: HTTP $code, enabled $(jq -r .enabled "$tmp/body" 2>/dev/null), latest error: $(jq -r '[.triaged[] | .error // empty][0] // "none"' "$tmp/body" 2>/dev/null)"
fi
if more "${via_datyx:-}" 0; then
  ok "the triage reaches aityx through datyx's gateway: $via_datyx of the latest via datyx"
else
  bad "no triage went through datyx's gateway (is datyx-api up, and DATYX_SERVICE_TOKEN set?); vias: $(jq -r '[.triaged[].via] | group_by(.) | map("\(.[0])=\(length)") | join(" ")' "$tmp/body" 2>/dev/null)"
fi

# /api/datyx/*: with sign-in on (OIDC_CLIENT_ID set) it needs a Google
# user, whose token goes on to datyx; Google's sign-in can't happen from
# here, so it must refuse cleanly. Without sign-in it reaches datyx.
auth="$(curl -s --max-time 5 "$web/api/auth/config" | jq -r .enabled 2>/dev/null)"
code="$(get /api/datyx/me)"
if [[ "$auth" == true ]]; then
  if [[ "$code" == 401 ]]; then
    ok "/api/datyx/me refuses without a Google sign-in (401), as sign-in is on"
  else
    bad "/api/datyx/me without a sign-in: HTTP $code, want 401"
  fi
elif [[ "$code" == 200 ]]; then
  ok "/api/datyx/me reaches the datyx API (sign-in is off)"
else
  bad "/api/datyx/me: HTTP $code (sign-in is ${auth:-unknown})"
fi

exit $failed
