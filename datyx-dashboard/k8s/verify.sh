#!/usr/bin/env bash
# Checks the dashboard on the local cluster, from this host: the app at
# http://localhost:19906/app/ (the page, its compiled code, a tab's
# address), and the datyx API through the dashboard's proxy, as the app
# calls it: /api/health, /api/health/ready and /q/openapi answer what the
# API itself answers on its own port (19900), and the data the tabs show
# comes through it. One line per check; exits 1 if any fails.
# k8s/deploy.sh runs it after a deploy, k8s/verify.sh with the others.
#
#   bash datyx-dashboard/k8s/verify.sh
#
# The cluster's API signs its users in with Google when the root .env has
# an OIDC_CLIENT_ID (datyx/k8s/api.yaml): the paths that need a signed-in
# user are then checked to refuse a caller without one, and the sign-in
# itself can't be checked without a browser (a user's profile is made
# with HealthHub's sources: datyx/k8s/verify.sh checks every profile has
# them). Without a client id sign-in is off, as a local run without a
# datyx/.env: what the tabs ask for is checked to answer, with HealthHub's
# sources in the Data sources tab's list.
set -uo pipefail

PORT="${DASHBOARD_PORT:-19906}"
API_PORT="${DATYX_API_PORT:-19900}"
base="http://127.0.0.1:$PORT"
api="http://127.0.0.1:$API_PORT"
# How long to wait for the app and the API to answer at first (a deploy
# just restarted them), in seconds.
WAIT="${VERIFY_WAIT:-60}"

failed=0
ok() { echo "✅ $1"; }
bad() { echo "✗ $1: $2"; failed=1; }

body="$(mktemp)"
trap 'rm -f "$body"' EXIT

# get <url> [curl args...]: fetches into $body, prints the status code
# (000 when nothing answered).
get() {
  local url="$1"
  shift
  curl -s -o "$body" -w '%{http_code}' --max-time 10 "$@" "$url" 2>/dev/null || true
}

# wait_for <url> <status>: polls until the URL answers that status, for up
# to WAIT seconds; prints the last status.
wait_for() {
  local url="$1" want="$2" code deadline=$((SECONDS + WAIT))
  while :; do
    code="$(get "$url")"
    [[ "$code" == "$want" || $SECONDS -ge $deadline ]] && break
    sleep 3
  done
  echo "$code"
}

# The app: index.html under /app/, built for that base, and / sends there.
code="$(wait_for "$base/app/" 200)"
if [[ "$code" != 200 ]]; then
  bad "the dashboard at $base/app/" "HTTP $code"
elif ! grep -q '<title>datyx</title>' "$body" || ! grep -q '<base href="/app/">' "$body"; then
  bad "the dashboard at $base/app/" "the page isn't the dashboard's release build under /app/"
else
  ok "the dashboard at $base/app/"
fi

code="$(get "$base/app/main.dart.js")"
size="$(wc -c <"$body" | tr -d ' ')"
if [[ "$code" == 200 && "$size" -gt 100000 ]] && head -c 2000 "$body" | grep -q 'dart'; then
  ok "its compiled code, /app/main.dart.js ($((size / 1024)) KB)"
else
  bad "its compiled code, /app/main.dart.js" "HTTP $code, $size bytes"
fi

code="$(get "$base/app/flutter_bootstrap.js")"
if [[ "$code" == 200 ]] && grep -q 'main.dart.js' "$body"; then
  ok "its loader, /app/flutter_bootstrap.js"
else
  bad "its loader, /app/flutter_bootstrap.js" "HTTP $code"
fi

# A tab's address, as a reload or a shared link opens it: the app's page,
# which then opens the tab named in ?tab=.
code="$(get "$base/app/?tab=training")"
if [[ "$code" == 200 ]] && grep -q '<title>datyx</title>' "$body"; then
  ok "a tab's address, /app/?tab=training"
else
  bad "a tab's address, /app/?tab=training" "HTTP $code"
fi

location="$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' --max-time 10 "$base/" 2>/dev/null)"
if [[ "$location" == "302 http://127.0.0.1:$PORT/app/" ]]; then
  ok "/ sends to /app/, on the published port"
else
  bad "/ sends to /app/" "answered $location"
fi

# why_not <code>: why the API's answer through the proxy isn't the one
# wanted: nothing behind the proxy, or the checks that are down.
why_not() {
  case "$1" in
    502 | 503 | 504 | 000)
      if jq -e .checks "$body" >/dev/null 2>&1; then
        echo "HTTP $1, down: $(jq -r '[.checks[] | select(.status != "UP") | .name] | join(", ")' "$body")"
      else
        echo "HTTP $1: the datyx API (Service datyx-api:9900) doesn't answer"
      fi ;;
    *) echo "HTTP $1" ;;
  esac
}

# The API through the proxy. Its health: UP, with each check's status (the
# database's and OpenMetadata's), never their data.
code="$(wait_for "$base/api/health" 200)"
if [[ "$code" == 200 ]] && [[ "$(jq -r .status "$body" 2>/dev/null)" == UP ]]; then
  ok "the API's health through the proxy, /api/health: UP ($(jq -r '[.checks[] | "\(.name) \(.status)"] | join(", ")' "$body"))"
else
  bad "the API's health through the proxy, /api/health" "$(why_not "$code")"
fi

code="$(get "$base/api/health/ready")"
if [[ "$code" == 200 ]] && [[ "$(jq -r .status "$body" 2>/dev/null)" == UP ]]; then
  ok "the API is ready, through the proxy, /api/health/ready"
else
  bad "the API is ready, through the proxy, /api/health/ready" "$(why_not "$code")"
fi

# The proxy answers what the API answers: the same description, and the
# same sign-in settings, through the dashboard as on the API's own port.
code="$(get "$base/q/openapi")"
through="$(shasum <"$body" | cut -d' ' -f1)"
if [[ "$code" != 200 ]] || ! grep -q 'title: datyx API' "$body" || ! grep -q '/api/datasources' "$body"; then
  bad "the API's description through the proxy, /q/openapi" "$(why_not "$code")"
elif [[ "$(get "$api/q/openapi")" != 200 ]]; then
  bad "the API's description through the proxy, /q/openapi" "the API's own port, $API_PORT, doesn't answer to compare"
elif [[ "$(shasum <"$body" | cut -d' ' -f1)" != "$through" ]]; then
  bad "the API's description through the proxy, /q/openapi" "not what the API answers on its own port"
else
  ok "the API's description through the proxy, /q/openapi: the API's own"
fi

code="$(get "$base/api/auth/config")"
config="$(cat "$body")"
direct="$(get "$api/api/auth/config"; echo; cat "$body")"
enabled="$(jq -r .enabled <<<"$config" 2>/dev/null)"
if [[ "$code" != 200 || -z "$enabled" || "$enabled" == null ]]; then
  bad "the sign-in settings through the proxy, /api/auth/config" "$(why_not "$code")"
elif [[ "$direct" != "200"$'\n'"$config" ]]; then
  bad "the sign-in settings through the proxy, /api/auth/config" "not what the API answers on its own port"
elif [[ "$enabled" == true && -z "$(jq -r '.clientId // empty' <<<"$config")" ]]; then
  bad "the sign-in settings through the proxy, /api/auth/config" "sign-in on without a client id"
elif [[ "$enabled" == true ]]; then
  ok "the sign-in settings through the proxy, /api/auth/config: Google sign-in on, the API's own answer"
else
  ok "the sign-in settings through the proxy, /api/auth/config: sign-in off, the API's own answer"
fi

if [[ "$enabled" == true ]]; then
  # What needs a signed-in user refuses, cleanly, a caller without one, or
  # with a token that isn't Google's: 401 from the API, through the proxy.
  # (Signing in can't be checked here: see the top of this file.)
  refused=() let_in=()
  for call in "GET /api/datasources" "POST /api/datasources" "GET /api/me" "GET /api/profile" \
    "GET /api/training" "GET /api/aityx" "GET /api/catalog/events"; do
    method="${call%% *}" path="${call#* }"
    args=(-X "$method")
    [[ "$method" == POST ]] && args+=(-H 'Content-Type: application/json' --data '{}')
    code="$(get "$base$path" "${args[@]}")"
    if [[ "$code" == 401 ]]; then refused+=("$call"); else let_in+=("$call: HTTP $code"); fi
  done
  code="$(get "$base/api/datasources" -H 'Authorization: Bearer not-a-google-token')"
  if [[ "$code" == 401 ]]; then refused+=("a made-up token"); else let_in+=("a made-up token: HTTP $code"); fi
  if [[ ${#let_in[@]} -eq 0 ]]; then
    ok "without a signed-in user the API refuses (401) through the proxy: ${#refused[@]} calls"
  else
    bad "without a signed-in user the API refuses through the proxy" "$(printf '%s; ' "${let_in[@]}" | sed 's/; $//')"
  fi
elif [[ "$enabled" == false ]]; then
  # Sign-in off: what the tabs ask for answers, through the proxy, and the
  # Data sources tab has HealthHub's two to show (the dev data, the Local
  # profile's, which every call is).
  answered=() refused=()
  for path in /api/datasources /api/me /api/profile /api/training /api/inference /api/aityx /api/catalog/events; do
    code="$(get "$base$path")"
    if [[ "$code" == 200 ]]; then answered+=("$path"); else refused+=("$path: HTTP $code"); fi
  done
  if [[ ${#refused[@]} -eq 0 ]]; then
    ok "what the tabs ask for answers through the proxy: ${#answered[@]} calls"
  else
    bad "what the tabs ask for, through the proxy" "$(printf '%s; ' "${refused[@]}" | sed 's/; $//')"
  fi
  code="$(get "$base/api/datasources?limit=100")"
  names="$(jq -r '[.. | objects | select(has("name") and has("type")) | .name] | sort | join(", ")' "$body" 2>/dev/null)"
  if [[ "$code" == 200 && ", $names, " == *", HealthHub, "* && ", $names, " == *", HealthHub Kafka, "* ]]; then
    ok "the Data sources tab's list, /api/datasources: $names"
  else
    bad "the Data sources tab's list, /api/datasources" "HealthHub's sources aren't in it (HTTP $code: ${names:-none})"
  fi
fi

exit $failed
