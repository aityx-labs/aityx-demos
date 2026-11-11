#!/usr/bin/env bash
# Checks datyx on the local cluster from this host, one line per check:
# the API (http://localhost:19900) ready with PostgreSQL and OpenMetadata,
# its description, sign-in, the data in PostgreSQL (HealthHub's sources in
# every profile, the training runs, the aityx calls), HealthHub's
# PostgreSQL and Kafka at the addresses the API is given, HealthHub's
# catalogue in OpenMetadata, its topics and its search index,
# OpenMetadata's UI and API (http://localhost:19902), and the aityx
# gateway passing a service's call on to aityx with datyx's key. Exits 1
# if any check fails.
#
# The cluster's API signs its users in with Google when the root .env has
# an OIDC_CLIENT_ID (api.yaml): the data paths then want a Google user,
# which a script can't be, so they are checked to refuse an anonymous
# call, and the data is read from the stores: the Local profile's, which
# the API seeds, catalogues and trains at every start, as it does each
# user's from their first sign-in. Without a client id sign-in is off,
# every call is the Local profile, and its data sources are read through
# the API too, as the dashboard reads them. No secret is printed: the
# service token stays in the API's container, where the gateway's checks
# run.
#
#   bash datyx/k8s/verify.sh     # (bash k8s/deploy.sh datyx runs it)
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../../k8s/lib.sh
source "$here/../../k8s/lib.sh"

api=http://127.0.0.1:19900
om=http://127.0.0.1:19902
ns=datyx
failed=0
ok() { echo "✅ $1"; }
ko() { echo "✗ $1"; failed=1; }
# get <url> [curl args...]: the body, empty when the answer isn't a 2xx.
get() { curl -fsS --max-time 15 "$@" 2>/dev/null; }
# code <url> [curl args...]: the answer's HTTP status.
code() { curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$@" 2>/dev/null; }
# sql <query>: one value from the datyx database, as its superuser on the
# server's own socket.
sql() { kc -n "$ns" exec datyx-postgres-0 -c postgres -- psql -U postgres -d datyx -tAc "$1" 2>/dev/null; }
# in_api <script>: a shell script in the API's container, which has the
# service token in its environment.
in_api() { kc -n "$ns" exec deploy/datyx-api -c api -- sh -c "$1" 2>/dev/null; }

# The API, ready: its own check, PostgreSQL's and OpenMetadata's all UP.
# Right after a start this waits up to a minute.
health=""
for _ in $(seq 1 20); do
  health="$(get "$api/api/health/ready")" && [[ "$(jq -r .status <<<"$health")" == UP ]] && break
  sleep 3
done
db="$(jq -r '.checks[]? | select(.name=="Database connections health check") | .status' <<<"$health" 2>/dev/null)"
omv="$(jq -r '.checks[]? | select(.name=="OpenMetadata") | "\(.status) \(.data.version // "")"' <<<"$health" 2>/dev/null)"
if [[ "$db" == UP && "$omv" == UP* ]]; then
  ok "API ready on :19900: PostgreSQL UP, OpenMetadata UP (version ${omv#UP })"
else
  ko "API ready on :19900: PostgreSQL ${db:-no answer}, OpenMetadata ${omv:-no answer}"
fi
# The address the API reports for OpenMetadata is the one the dashboard's
# Health tab links to: it has to open from this host, not only in the
# cluster (api.yaml's DATYX_OPENMETADATA_PUBLIC_URL).
omurl="$(jq -r '.checks[]? | select(.name=="OpenMetadata") | .data.url // empty' <<<"$health" 2>/dev/null)"
if [[ -n "$omurl" ]] && get "$omurl/" | grep -qi '<title>OpenMetadata'; then
  ok "the API's address for OpenMetadata opens from this host: $omurl"
else
  ko "the API's address for OpenMetadata, ${omurl:-none}, doesn't open from this host: the dashboard's links to it are dead"
fi
live="$(get "$api/api/health/live")"
mode="$(jq -r '.checks[]? | select(.name=="datyx") | "the \(.data.profile) profile, \(.data.image), version \(.data.version)"' <<<"$live" 2>/dev/null)"
[[ -n "$mode" ]] && ok "API live: $mode" || ko "API live: no answer from /api/health/live"

# The API's description and Swagger UI.
openapi="$(get "$api/q/openapi" -H 'Accept: application/json')"
if [[ "$(jq -r '.info.title' <<<"$openapi" 2>/dev/null)" == "datyx API" ]] &&
  jq -e '.paths | has("/api/training")' <<<"$openapi" >/dev/null 2>&1; then
  ok "OpenAPI at /q/openapi: $(jq '.paths | length' <<<"$openapi") paths"
else
  ko "OpenAPI at /q/openapi: not the datyx API's description"
fi
if get -L "$api/q/swagger-ui/" | grep -qi swagger; then
  ok "Swagger UI at /q/swagger-ui"
else
  ko "Swagger UI at /q/swagger-ui: no page"
fi

# Sign-in. On: the paths of a user's data refuse an anonymous call and a
# token that isn't Google's, cleanly (401). Off: they answer, and are
# read below.
auth="$(get "$api/api/auth/config")"
if [[ "$(jq -r .enabled <<<"$auth" 2>/dev/null)" == true ]]; then
  refused=0 let_in=()
  for path in /api/me /api/datasources /api/training /api/inference /api/aityx; do
    c="$(code "$api$path")"
    [[ "$c" == 401 ]] && refused=$((refused + 1)) || let_in+=("$path: $c")
  done
  c="$(code "$api/api/datasources" -H 'Authorization: Bearer not.a.token')"
  [[ "$c" == 401 ]] && refused=$((refused + 1)) || let_in+=("a made-up token: $c")
  if [[ ${#let_in[@]} == 0 ]]; then
    ok "sign-in on ($(jq -r .issuer <<<"$auth")): a user's paths refuse an anonymous call and a made-up token (401, $refused calls); a user signs in on the dashboard (19906) or HealthHub (19801), which the OAuth client lists among its origins, and gets a profile with HealthHub's sources"
  else
    ko "sign-in on, but not refused: ${let_in[*]}"
  fi
elif [[ "$(jq -r .enabled <<<"$auth" 2>/dev/null)" == false ]]; then
  ok "sign-in off (no OIDC_CLIENT_ID in the root .env's demo-env): every path open, every call the Local profile"
  # What the dashboard lists: the caller's data sources, HealthHub's two
  # among them (the dev data is seeded into the Local profile).
  mine="$(get "$api/api/datasources?limit=100" | jq -r '[.. | objects | select(has("name") and has("type")) | .name] | sort | join(", ")' 2>/dev/null)"
  if [[ ", $mine, " == *", HealthHub, "* && ", $mine, " == *", HealthHub Kafka, "* ]]; then
    ok "GET /api/datasources: the caller's profile has $mine"
  else
    ko "GET /api/datasources: HealthHub's sources aren't the caller's (${mine:-none}), so the dashboard has nothing to show"
  fi
  training="$(get "$api/api/training")"
  [[ -n "$(jq '.models | length' <<<"$training" 2>/dev/null)" ]] &&
    ok "GET /api/training: $(jq '.models | length' <<<"$training") models, $(jq '.runs | length' <<<"$training") runs" ||
    ko "GET /api/training: no answer"
else
  ko "sign-in: no answer from /api/auth/config"
fi

# The data in PostgreSQL: the dev data's HealthHub sources (its database
# and Kafka) in every profile, the Local one from the start and each
# user's from their first sign-in.
names="$(sql "select string_agg(distinct name, ', ' order by name) from data_source")"
profiles="$(sql "select count(*) from profile")"
without="$(sql "select count(*) from profile p where (select count(*) from data_source d
  where d.profile_id = p.id and d.name in ('HealthHub', 'HealthHub Kafka')) < 2")"
if [[ "$names" == *"HealthHub Kafka"* && "$without" == 0 ]]; then
  ok "data sources in PostgreSQL: $names, in each of the $profiles profile(s)"
else
  ko "data sources in PostgreSQL: HealthHub's aren't in every profile (${names:-none}; ${without:-?} of ${profiles:-?} profiles without)"
fi
# HealthHub's PostgreSQL and Kafka at the addresses api.yaml gives the API
# for the dev data's sources (DATYX_HEALTHHUB_DB_HOST and _PORT,
# DATYX_HEALTHHUB_KAFKA), asked from the API's own container, so by its
# network and its names: pg_isready's question to the database (the
# start of a session, which only a running server answers) and a
# connection to the broker.
hh_up=0
hh_db="$(in_api 'printf "%s:%s" "${DATYX_HEALTHHUB_DB_HOST:-localhost}" "${DATYX_HEALTHHUB_DB_PORT:-9803}"')"
hh_kafka="$(in_api 'printf %s "${DATYX_HEALTHHUB_KAFKA:-localhost:9804}"')"
if [[ -z "$hh_db" ]]; then
  ko "HealthHub's PostgreSQL at the API's address for it: no running API container"
elif kc -n "$ns" exec datyx-postgres-0 -c postgres -- pg_isready -q -t 5 -h "${hh_db%:*}" -p "${hh_db##*:}" </dev/null 2>/dev/null; then
  hh_up=1
  ok "HealthHub's PostgreSQL answers at the API's address for it ($hh_db)"
else
  ko "HealthHub's PostgreSQL doesn't answer at the API's address for it ($hh_db): HealthHub up? (bash k8s/deploy.sh HealthHub)"
fi
if [[ -n "$hh_kafka" ]] && in_api 'first="${DATYX_HEALTHHUB_KAFKA:-localhost:9804}"; first="${first%%,*}"; timeout 5 bash -c "exec 3<>/dev/tcp/${first%:*}/${first##*:}"'; then
  ok "HealthHub's Kafka takes a connection at the API's address for it ($hh_kafka)"
else
  ko "HealthHub's Kafka takes no connection at the API's address for it (${hh_kafka:-none}): HealthHub up?"
fi

# HealthHub's catalogue in OpenMetadata (datyx writes it by itself once
# HealthHub's data is in) and in its search index: a sign-in as the
# built-in admin (compose.yaml's admin / admin), then the tables. On a new
# cluster datyx waits for HealthHub's first rows (up to 5 minutes,
# datyx.dev-catalog.rows-wait) before it writes the first table, so with
# HealthHub's database answering the first table is awaited up to 6
# minutes, and its indexing a minute more; without HealthHub, not at all.
if get "$om/" | grep -qi '<title>OpenMetadata'; then
  ok "OpenMetadata's UI on :19902"
else
  ko "OpenMetadata's UI on :19902: no page"
fi
version="$(get "$om/api/v1/system/version" | jq -r .version 2>/dev/null)"
[[ -n "$version" && "$version" != null ]] && ok "OpenMetadata's API on :19902: version $version" ||
  ko "OpenMetadata's API on :19902: no version"
token="$(curl -fsS --max-time 15 -H 'Content-Type: application/json' \
  -d "{\"email\":\"admin@open-metadata.org\",\"password\":\"$(printf admin | base64)\"}" \
  "$om/api/v1/users/login" 2>/dev/null | jq -r '.accessToken // empty')"
if [[ -n "$token" ]]; then
  hh="$(sql "select id from data_source where name = 'HealthHub' order by id limit 1")"
  tries=1
  [[ $hh_up == 1 ]] && tries=120
  for _ in $(seq 1 "$tries"); do
    tables="$(get "$om/api/v1/tables?database=datyx-ds-$hh.healthhub&limit=1" -H "Authorization: Bearer $token" | jq '.paging.total' 2>/dev/null)"
    [[ "${tables:-0}" -gt 0 ]] && break
    sleep 3
  done
  [[ "${tables:-0}" -gt 0 ]] && ok "HealthHub's catalogue in OpenMetadata: $tables tables (datyx-ds-$hh.healthhub)" ||
    ko "HealthHub's catalogue in OpenMetadata: no tables yet (HealthHub up? datyx waits for its data, then curates)"
  tries=1
  [[ "${tables:-0}" -gt 0 ]] && tries=20
  for _ in $(seq 1 "$tries"); do
    hits="$(get "$om/api/v1/search/query?q=*&index=table_search_index&size=0" -H "Authorization: Bearer $token" |
      jq '.hits.total.value // .hits.total' 2>/dev/null)"
    [[ "${hits:-0}" -gt 0 ]] && break
    sleep 3
  done
  [[ "${hits:-0}" -gt 0 ]] && ok "OpenMetadata's search (Elasticsearch): $hits tables indexed" ||
    ko "OpenMetadata's search (Elasticsearch): no tables indexed"
  # HealthHub's Kafka, read at the address above: its topics, catalogued
  # with the tables' pass, or, when Kafka was still starting then (a new
  # cluster), within half a minute of its answering (the API tries it
  # again every 30 s for 5 minutes): awaited up to 5 minutes with the
  # tables there.
  hk="$(sql "select id from data_source where name = 'HealthHub Kafka' order by id limit 1")"
  tries=1
  [[ "${tables:-0}" -gt 0 ]] && tries=100
  for _ in $(seq 1 "$tries"); do
    topics="$(get "$om/api/v1/topics?service=datyx-ds-$hk&limit=1" -H "Authorization: Bearer $token" | jq '.paging.total' 2>/dev/null)"
    [[ "${topics:-0}" -gt 0 ]] && break
    sleep 3
  done
  if [[ "${topics:-0}" -gt 0 ]]; then
    ok "HealthHub's topics in OpenMetadata: $topics (datyx-ds-$hk)"
  elif [[ "${tables:-0}" -gt 0 ]]; then
    ko "HealthHub's topics in OpenMetadata: none (datyx-ds-$hk), though its tables are there: Kafka unread at $hh_kafka?"
  else
    ko "HealthHub's topics in OpenMetadata: none yet"
  fi
else
  ko "OpenMetadata: the admin's sign-in failed"
fi

# The models: datyx trains the groups the catalogue tags as time series
# (XGBoost, DeepAR) on HealthHub's data; the runs are in PostgreSQL. The
# dev profile starts from an empty database, and the first runs come well
# after the catalogue's first table: the sync writes the tables, their
# profiles and checks run, the curation tags the groups (a minute or more
# after the first table), and only the trainer's next look, one a minute
# (datyx.training.check-every), queues them. With the catalogue there the
# first run is awaited up to 5 minutes; without it, a minute. The first
# runs may still be under way (a minute or more each): that passes. A
# group can fail on its data, too young for its horizon (a new
# HealthHub's patient_days); the line says why.
tries=20
[[ "${tables:-0}" -gt 0 ]] && tries=100
for _ in $(seq 1 "$tries"); do
  counts="$(sql "select count(*) filter (where status = 'SUCCEEDED') || ' ' ||
    count(*) filter (where status in ('QUEUED', 'RUNNING')) || ' ' || count(*) filter (where status = 'FAILED')
    from training_run")"
  read -r succeeded under_way failed_runs <<<"${counts:-0 0 0}"
  [[ "$((succeeded + under_way + failed_runs))" -gt 0 ]] && break
  sleep 3
done
models="$(sql "select string_agg(distinct split_part(table_fqn, '.', 4) || ' ' || group_name || ' (' || algorithm || ')', ', ')
  from training_run where status = 'SUCCEEDED'")"
error="$(sql "select left(error, 160) from training_run where status = 'FAILED' order by id desc limit 1")"
note=""
[[ "$failed_runs" -gt 0 ]] && note=" (the latest failure: $error)"
if [[ "$succeeded" -gt 0 ]]; then
  ok "training: $succeeded runs succeeded, $under_way under way, $failed_runs failed$note; models: $models"
elif [[ "$under_way" -gt 0 ]]; then
  ok "training: the first $under_way runs under way since the start, $failed_runs failed$note"
else
  ko "training: $succeeded succeeded, $under_way under way, $failed_runs failed${error:+: $error} (none come before HealthHub's catalogue)"
fi

# The aityx gateway, from inside the API's container: the status, then a
# real call. aityx answers an empty body with 400 when it takes the key
# (401 or 403 when it doesn't); nothing is asked, so nothing is spent.
status="$(in_api '[ -n "$DATYX_SERVICE_TOKEN" ] || { echo notoken; exit; }; curl -s --max-time 15 -H "X-Datyx-Service-Token: $DATYX_SERVICE_TOKEN" http://localhost:9900/api/aityx/v1/status')"
if [[ "$status" == notoken ]]; then
  ko "aityx gateway: no DATYX_SERVICE_TOKEN in demo-env (bash k8s/secrets.sh)"
elif [[ "$(jq -r .configured <<<"$status" 2>/dev/null)" == true ]]; then
  ok "aityx gateway: the service token is datyx's, and datyx has an aityx key"
  before="$(sql "select count(*) from aityx_call")"
  c="$(in_api 'curl -s -o /dev/null -w "%{http_code}" --max-time 60 -X POST -H "Content-Type: application/json" -H "X-Datyx-Service-Token: $DATYX_SERVICE_TOKEN" -H "X-Datyx-Caller: k8s-verify" -d "{}" http://localhost:9900/api/aityx/v1/systemone')"
  host="$(in_api 'printf %s "$DATYX_AITYX_URL"' | sed -E 's#^(https?://[^/]+).*#\1#')"
  if [[ "$c" == 400 ]]; then
    ok "aityx gateway: a service's call reached aityx ($host), which took datyx's key (400 to an empty request)"
  else
    ko "aityx gateway: a service's call answered ${c:-nothing}, not aityx's 400 to an empty request (401/403: key refused; 502/504: aityx unreached; 503: no key)"
  fi
  after="$(sql "select count(*) from aityx_call")"
  [[ "${after:-0}" -gt "${before:-0}" ]] && ok "aityx account in PostgreSQL: the call recorded ($after calls)" ||
    ko "aityx account in PostgreSQL: the call wasn't recorded"
else
  ko "aityx gateway: status ${status:-no answer}"
fi
# A wrong token is refused, signed in or not.
c="$(code "$api/api/aityx/v1/status" -H 'X-Datyx-Service-Token: not-the-token')"
[[ "$c" == 401 || "$c" == 403 ]] && ok "aityx gateway refuses a wrong service token ($c)" ||
  ko "aityx gateway answered $c to a wrong service token, not 401"

exit $failed
