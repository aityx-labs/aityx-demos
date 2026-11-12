#!/usr/bin/env bash
# Checks tatyx on the local cluster from this host, at
# http://127.0.0.1:19710 (k8s/kind/cluster.yaml): the app and its assets,
# the health check and the config, a real decision on aityx staging
# through the server's relay with a player's key, the leaderboard with
# its own key (played in the pod, by the runner the server plays
# tournaments with), the tour's files on their volume, and the sign-in
# gated API refusing a caller who isn't signed in (a Google sign-in needs
# a browser). One line per check; exits 1 if any fails. Never
# prints a key.
#
# The player's key is what a player would set in Profile, staging's:
# TATYX_PLAYER_KEY, else AITYX_API_KEY (the first aityx takes), each from
# the environment, else the repository's .env. It goes to curl on its
# standard input, never on a command line.
#
#   bash tatyx/k8s/verify.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
demo="$(cd "$here/.." && pwd)"
# shellcheck source=../../k8s/lib.sh
source "$here/../../k8s/lib.sh"

base="http://127.0.0.1:19710"
# The page's own origin, as a browser on this host sends it.
origin="http://localhost:19710"
ns="$(k8s_namespace tatyx)"
failed=0
tmp="$(mktemp -d)"
chmod 700 "$tmp"
trap 'rm -rf "$tmp"' EXIT

pass() { echo "✅ $1"; }
fail() {
  echo "✗ $1: $2"
  failed=1
}

# http <curl arguments...>: the status code (000 when nothing answered);
# the body in $tmp/body, the headers in $tmp/headers.
http() {
  curl -sS -o "$tmp/body" -D "$tmp/headers" -w '%{http_code}' --max-time 40 "$@" 2>"$tmp/error" || true
}
# header <name>: a header of the last answer, lower case, without its CR.
header() {
  grep -i "^$1:" "$tmp/headers" | tail -1 | cut -d: -f2- | tr -d '\r' | sed 's/^ *//' | tr '[:upper:]' '[:lower:]'
}
# field <jq filter>: from the last answer's body.
field() {
  jq -r "$1" "$tmp/body" 2>/dev/null
}
# setting <NAME>: from the environment, else the repository's .env (the
# file k8s/secrets.sh makes the cluster's Secret from), as scripts/env.sh
# reads it; never printed.
setting() {
  local value="${!1:-}" file="$k8s_root/.env"
  if [[ -z "$value" && -f "$file" ]]; then
    value="$(sed -n "s/^$1=//p" "$file" | tail -1)"
    value="${value%%#*}"
    value="${value%"${value##*[![:space:]]}"}"
    value="${value#[\"\']}"
    value="${value%[\"\']}"
  fi
  printf '%s' "$value"
}

# The server first: up to a minute, for a pod that is still starting.
status=000
for _ in $(seq 1 30); do
  status="$(http "$base/api/health")"
  [[ "$status" == 200 ]] && break
  sleep 2
done
if [[ "$status" == 200 && "$(field .ok)" == true ]]; then
  pass "tatyx answers: /api/health is ok"
else
  fail "tatyx answers" "/api/health is HTTP $status ($(head -c 200 "$tmp/error" "$tmp/body" 2>/dev/null | tr '\n' ' '))"
  exit 1
fi

# The app: the page, then every bundle it loads, the portraits and the
# privacy page.
status="$(http "$base/")"
if [[ "$status" == 302 && "$(header location)" == /tatyx/ ]]; then
  pass "/ redirects to /tatyx/"
else
  fail "/ redirects to /tatyx/" "HTTP $status, Location $(header location)"
fi
status="$(http "$base/tatyx/")"
if [[ "$status" == 200 ]] && grep -q '<title>tatyx</title>' "$tmp/body"; then
  pass "the app's page at /tatyx/"
  assets=()
  while IFS= read -r asset; do assets+=("$asset"); done < <(grep -oE '/tatyx/assets/[A-Za-z0-9._-]+\.(js|css)' "$tmp/body" | sort -u)
  if [[ ${#assets[@]} -lt 2 ]]; then
    fail "the app's bundles" "the page names ${#assets[@]} (a script and a stylesheet expected)"
  else
    bad=""
    for asset in "${assets[@]}"; do
      status="$(http "$base$asset")"
      type="$(header content-type)"
      size="$(wc -c <"$tmp/body" | tr -d ' ')"
      case "$asset" in
        *.js) want=text/javascript ;;
        *) want=text/css ;;
      esac
      [[ "$status" == 200 && "$type" == "$want"* && "$size" -gt 1000 ]] || bad+=" $asset (HTTP $status, $type, $size bytes)"
    done
    [[ -z "$bad" ]] && pass "the app's bundles: ${assets[*]##*/}" || fail "the app's bundles" "$bad"
  fi
else
  fail "the app's page at /tatyx/" "HTTP $status"
fi
status="$(http "$base/tatyx/bots/i-builder.png")"
if [[ "$status" == 200 && "$(header content-type)" == image/png ]]; then
  pass "the bots' portraits (/tatyx/bots/i-builder.png)"
else
  fail "the bots' portraits" "/tatyx/bots/i-builder.png is HTTP $status, $(header content-type)"
fi
status="$(http "$base/tatyx/privacy/")"
if [[ "$status" == 200 ]] && grep -qi 'privacy' "$tmp/body"; then
  pass "the privacy page (/tatyx/privacy/)"
else
  fail "the privacy page" "HTTP $status"
fi

# The config: where aityx is (staging, the .env's AITYX_URL), the relay,
# and the Google sign-in set up (its client id is not printed).
want_url="$(setting AITYX_URL)"
want_url="${want_url%/}"
status="$(http "$base/api/config")"
url="$(field .aityxUrl)"
if [[ "$status" != 200 ]]; then
  fail "/api/config" "HTTP $status"
else
  if [[ "$(field .aityxRelay)" == /aityx/ && "$url" == https://* && (-z "$want_url" || "$url" == "$want_url") ]]; then
    pass "/api/config: aityx at $url, relayed at /aityx/"
  else
    fail "/api/config's aityx" "aityxUrl $url (the .env says ${want_url:-nothing}), aityxRelay $(field .aityxRelay)"
  fi
  if [[ -n "$(field '.signIn.clientId // empty')" ]]; then
    pass "/api/config: Google sign-in is set up (TATYX_OIDC_CLIENT_ID), for any account: $(field '.signIn.domains | join(",")')"
  else
    fail "/api/config's sign-in" "no client id: is TATYX_OIDC_CLIENT_ID in the Secret demo-env?"
  fi
fi

# The relay: refuses a call without a key, and a page of another origin.
body="$tmp/decision.json"
state='{"seconds": 30, "bytes_mb": 1, "bots": 3, "hackers": 0, "anchors": 1, "builders": 1, "testers": 0, "combinators": 0, "explorers": 1, "sites_known": 3, "sites_held": 1, "sites_total": 40, "room_mb": 12, "links_known": 4, "links_rotting": 0, "income_kbs": 48, "mainframe_connected": false, "hack_pct": 0, "leader_pct": 0, "threat": 0}'
# The request the game sends (strategy.ts, buildRequest): the team model
# with the Farmer's decisions, and a team's situation as its state.
jq -n --slurpfile model "$demo/tatyx_app/src/game/models/team.json" \
  --slurpfile s "$demo/tatyx_app/src/game/strategies/farmer.json" --argjson state "$state" \
  '{decision: {name: ($model[0].name + " · " + $s[0].name), types: $model[0].types, inputs: $model[0].inputs, decisions: $s[0].decisions}, state: $state}' >"$body"
status="$(http -X POST -H 'Content-Type: application/json' -H "Origin: $origin" --data-binary "@$body" "$base/aityx/v1/systemone")"
if [[ "$status" == 401 && "$(field .code)" == unauthorized ]]; then
  pass "the relay refuses a call without a player's key (401)"
else
  fail "the relay without a key" "HTTP $status (401 expected)"
fi
status="$(http -X POST -H 'Content-Type: application/json' -H 'Origin: https://elsewhere.example' -H 'Authorization: Bearer not-a-key' --data-binary "@$body" "$base/aityx/v1/systemone")"
if [[ "$status" == 403 && "$(field .code)" == proxy_cross_site ]]; then
  pass "the relay refuses another origin's page (403)"
else
  fail "the relay from another origin" "HTTP $status (403 expected)"
fi

# A real decision on aityx through the relay, on a player's key: the
# Farmer with one Builder buys a second (its table's rule 2).
# A key aityx refuses (401: revoked) gives way to the next.
tried=""
decided=""
for which in TATYX_PLAYER_KEY AITYX_API_KEY; do
  key="$(setting "$which")"
  [[ -n "$key" ]] || continue
  # Twice at most when aityx doesn't answer: staging now and then drops a call.
  for attempt in 1 2; do
    status="$(printf 'header = "Authorization: Bearer %s"\n' "$key" |
      http -K - -X POST -H 'Content-Type: application/json' -H "Origin: $origin" --data-binary "@$body" "$base/aityx/v1/systemone")"
    [[ "$status" == 000 || "$status" == 5* ]] || break
    [[ $attempt == 1 ]] && sleep 2
  done
  choice="$(field '.answers.build.choice // empty')"
  rule="$(field '.receipt.decisions.build.rule // empty')"
  if [[ "$status" == 200 && "$choice" == builder && "$rule" == 2 ]]; then
    decided="$which"
    break
  fi
  tried+="${tried:+; }$which: HTTP $status, build ${choice:-none}, rule ${rule:-none} ($(field '.detail // .code // .decision_error.code // empty' | head -c 120))"
  [[ "$status" == 401 ]] || break
done
unset key
if [[ -n "$decided" ]]; then
  pass "a decision on aityx through the relay, on a player's key ($decided): the Farmer buys a builder (rule 2)${tried:+; refused first: $tried}"
else
  [[ -n "$tried" ]] || tried="no key: neither TATYX_PLAYER_KEY nor AITYX_API_KEY is in the environment or the .env"
  fail "a decision through the relay" "$tried"
fi

# The leaderboard: open to all, and able to play (a key of its own and an
# https URL); the tournaments it played so far.
status="$(http "$base/api/leaderboard")"
if [[ "$status" == 200 && "$(field .enabled)" == true ]]; then
  pass "the leaderboard is open and can play: $(field .tournaments) tournaments, $(field '.standings | length') strategies standing, every $(field .everyHours) h"
else
  fail "the leaderboard" "HTTP $status, enabled $(field .enabled): $(field '.reason // empty')"
fi

# The leaderboard's key, in the pod: one decision by the runner the
# server plays its tournaments with, on TATYX_LEADERBOARD_KEY (else
# AITYX_API_KEY) and AITYX_URL, as leaderboard.mjs calls aityx. The
# script reads the key from the server's environment and prints only the
# decision.
script="
const g = await import('/app/tatyx_app/dist-runner/runner.mjs');
const url = (process.env.AITYX_URL || 'https://api.aityx.ai').replace(/\/+\$/, '');
const key = process.env.TATYX_LEADERBOARD_KEY || process.env.AITYX_API_KEY || '';
if (!key) { console.log('no leaderboard key in the pod'); process.exit(1); }
const call = async (body) => {
  const answer = await fetch(url + '/v1/systemone', { method: 'POST', headers: { Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' }, body: JSON.stringify(body), redirect: 'manual', signal: AbortSignal.timeout(30000) });
  return { status: answer.status, json: await answer.json().catch(() => null) };
};
try {
  const d = await g.deciderOn(call)('cyan', g.STRATEGIES.find((s) => s.id === 'farmer'), $state);
  console.log('decided ' + d.build + ' (rule ' + d.rule + ')');
} catch (error) {
  console.log('failed: ' + (error && error.message));
}
"
# Twice at most: staging now and then drops a call.
for attempt in 1 2; do
  out="$(kc -n "$ns" exec deploy/tatyx -c server -- node --input-type=module -e "$script" 2>&1 | tail -1)"
  [[ "$out" == "decided builder (rule 2)" ]] && break
  [[ $attempt == 1 ]] && sleep 2
done
if [[ "$out" == "decided builder (rule 2)" ]]; then
  pass "the leaderboard's key: its runner, in the pod, $out on aityx"
else
  fail "the leaderboard's key, in the pod" "${out:-no answer}"
fi

# The tour's files, on the volume: the session secret made on the first
# start, and the entries the repository's strategies started.
out="$(kc -n "$ns" exec deploy/tatyx -c server -- sh -c 'grep -qs " /data " /proc/mounts && test -s /data/session-secret && test -s /data/strategies.json && echo kept' 2>&1 | tail -1)"
claim="$(kc -n "$ns" get pvc tatyx-data -o jsonpath='{.status.phase}' 2>/dev/null)"
if [[ "$out" == kept && "$claim" == Bound ]]; then
  pass "the tour's files on the volume tatyx-data (the session secret, the entries)"
else
  fail "the tour's files on the volume" "the claim is ${claim:-missing}; in the pod: ${out:-no answer}"
fi

# Signed out: the sign-in gated API refuses cleanly (a Google sign-in
# can't be checked without a browser; the client lists this origin).
gated=""
check_gated() {
  local what="$1" want="$2"
  shift 2
  local got
  got="$(http "$@")"
  [[ "$got" == "$want" ]] || gated+=" $what (HTTP $got, $want expected)"
}
check_gated "GET /api/session" 401 "$base/api/session"
check_gated "GET /api/strategies" 401 "$base/api/strategies"
check_gated "POST /api/strategies" 401 -X POST -H "Origin: $origin" -H 'Content-Type: application/json' --data '{}' "$base/api/strategies"
check_gated "DELETE /api/strategies/x" 401 -X DELETE -H "Origin: $origin" "$base/api/strategies/x"
check_gated "PUT /api/me" 401 -X PUT -H "Origin: $origin" -H 'Content-Type: application/json' --data '{"alias":"x"}' "$base/api/me"
check_gated "POST /api/leaderboard/run" 401 -X POST -H "Origin: $origin" "$base/api/leaderboard/run"
# A sign-in with a credential that isn't Google's: refused by the
# server's own check (503 would mean sign-in isn't set up).
check_gated "POST /api/session with a forged credential" 401 -X POST -H "Origin: $origin" -H 'Content-Type: application/json' --data '{"credential":"not.a.token"}' "$base/api/session"
if [[ -z "$gated" ]]; then
  pass "signed out, the session, the strategies, the alias and an admin's tournament refuse cleanly (401); a sign-in itself can't be checked without a browser (the Google client lists http://localhost:19710)"
else
  fail "the sign-in gated API" "$gated"
fi

exit $failed
