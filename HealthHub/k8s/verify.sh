#!/usr/bin/env bash
# Checks HealthHub on the local cluster, from this host: the app at
# http://127.0.0.1:19801/app/ and its compiled script; the API through the
# web app's proxy, with its database and Kafka; the simulation's moves
# flowing through Kafka and back (GET /api/events, read twice); Flink's
# healthhub-admissions-hourly job RUNNING (its web UI on :19806) and its
# counts of the live run in admissions_hourly, read back by the API; the
# initial data the API writes at start for datyx's models, read from the
# database (the simulated history, a year of visits behind patient_days
# and occupancy_hourly, and the hourly history of admissions_hourly); an
# admission triaged by aityx, through datyx's aityx gateway; and
# /api/datyx/*, which needs a Google sign-in, refusing cleanly without one.
# One line per check; exits 1 if any fails. Never prints a secret.
#
#   bash HealthHub/k8s/verify.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../../k8s/lib.sh
source "$here/../../k8s/lib.sh"

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

# The initial data, what datyx trains on from the first start: the
# simulated history (run 00000001: HEALTHHUB_SIM_HISTORY_DAYS days of the
# people's visits in admissions, so patient_days has each person's days
# over several of XGBoost's 30-day horizons and occupancy_hourly each care
# center's hours, for DeepAR), with its hourly counts, and the hourly
# history drawn from rates (run 00000000 of admissions_hourly,
# HEALTHHUB_HISTORY_DAYS days). Read from the database, as its superuser
# on the server's own socket. The API writes the first before its live
# run starts and the second in the background, well under a minute on an
# empty database: asked again for up to 90 s.
hsql() { kc -n datyx exec healthhub-postgres-0 -- psql -U postgres -d healthhub -tAc "$1" 2>/dev/null; }
setting() {
  kc -n datyx get deploy healthhub-api -o jsonpath="{.spec.template.spec.containers[0].env[?(@.name==\"$1\")].value}" 2>/dev/null
}
sim_days="$(setting HEALTHHUB_SIM_HISTORY_DAYS)"
sim_days="${sim_days:-365}"
hour_days="$(setting HEALTHHUB_HISTORY_DAYS)"
hour_days="${hour_days:-90}"
deadline=$((SECONDS + 90))
while :; do
  IFS='|' read -r sim_admissions sim_people sim_last <<<"$(hsql "select count(*), count(distinct person_id), coalesce(max(sim_day), 0)
    from admissions where split_part(event_id, '-', 1) = '00000001'")"
  IFS='|' read -r hist_rows hist_centers hist_hours <<<"$(hsql "select count(*), count(distinct hospital_id),
    coalesce(extract(epoch from max(hour_start) - min(hour_start)) / 3600, 0)::int from admissions_hourly where run_id = '00000000'")"
  { [[ "$sim_days" == 0 ]] || more "${sim_admissions:-}" 0; } && { [[ "$hour_days" == 0 ]] || more "${hist_hours:-}" $(((hour_days - 1) * 24 - 24)); } && break
  [[ $SECONDS -ge $deadline ]] && break
  sleep 5
done
if [[ "$sim_days" == 0 ]]; then
  ok "no simulated history asked for (HEALTHHUB_SIM_HISTORY_DAYS=0)"
else
  if more "${sim_admissions:-}" 0 && more "${sim_last:-}" $((sim_days - 8)); then
    ok "the simulated history is in admissions: $sim_admissions admissions of $sim_people people over $sim_last days (run 00000001, $sim_days days asked)"
  else
    bad "the simulated history in admissions: ${sim_admissions:-0} admissions up to day ${sim_last:-0} of $sim_days (run 00000001)"
  fi
  IFS='|' read -r pd_rows pd_series pd_span <<<"$(hsql "select count(*), count(distinct person_id), coalesce(max(day) - min(day), 0)
    from patient_days where run_id = '00000001'")"
  # XGBoost's group has a 30-day horizon and wants several of them.
  if more "${pd_rows:-}" 0 && more "${pd_span:-}" 119; then
    ok "patient_days has it: $pd_rows days of care of $pd_series people over $pd_span days, several of XGBoost's 30-day horizons"
  else
    bad "patient_days: ${pd_rows:-0} rows of the simulated history over ${pd_span:-0} days: too short for XGBoost's 30-day horizon"
  fi
  IFS='|' read -r occ_rows occ_centers occ_span <<<"$(hsql "select count(*), count(distinct hospital_id),
    coalesce(extract(epoch from max(hour_start) - min(hour_start)) / 3600, 0)::int from occupancy_hourly where run_id = '00000001'")"
  if more "${occ_rows:-}" 0 && more "${occ_span:-}" 48; then
    ok "occupancy_hourly has it: $occ_rows hours with people in care at $occ_centers care centers over $occ_span hours, for DeepAR"
  else
    bad "occupancy_hourly: ${occ_rows:-0} hours of the simulated history over ${occ_span:-0} hours"
  fi
  counted="$(hsql "select coalesce(sum(admissions), 0) from admissions_hourly where run_id = '00000001'")"
  if [[ -n "$counted" && "$counted" == "${sim_admissions:-}" ]]; then
    ok "admissions_hourly counts the simulated history's admissions: $counted, as many as admissions holds"
  else
    bad "admissions_hourly counts ${counted:-no} admissions of the simulated history, admissions holds ${sim_admissions:-0}"
  fi
fi
if [[ "$hour_days" == 0 ]]; then
  ok "no hourly history asked for (HEALTHHUB_HISTORY_DAYS=0)"
elif more "${hist_hours:-}" $(((hour_days - 1) * 24 - 24)); then
  ok "the hourly history is in admissions_hourly: $hist_rows rows of $hist_centers care centers over $hist_hours hours (run 00000000, $hour_days days asked)"
else
  bad "the hourly history in admissions_hourly: ${hist_rows:-0} rows over ${hist_hours:-0} hours of $((hour_days * 24)) (run 00000000)"
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
