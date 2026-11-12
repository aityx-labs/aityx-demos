#!/usr/bin/env bash
# Checks the aityx index on the local cluster, from this host
# (http://127.0.0.1:18800/demos/): the page and its health check; the six
# demos, each with its release web build made for its path (its
# index.html, main.dart.js and CanvasKit, from this origin); the dev
# proxy's settings, a real aityx call through it on the server's key (one
# generation of the Cellfie app's own Life model, as the app sends it,
# which aityx answers with a decision for each cell), and its refusals: a
# page of another site, or one that reached it through DNS rebinding. One
# line per check; exits 1 if any fails. Never prints the key.
#
#   bash Index/k8s/verify.sh
set -uo pipefail

base="http://127.0.0.1:18800/demos"
failed=0
ok() { echo "✅ $*"; }
bad() {
  echo "✗ $*"
  failed=1
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# The health check; the server may still be starting, so ask again for up
# to 30 s.
deadline=$((SECONDS + 30))
while :; do
  body="$(curl -s --max-time 5 "$base/api/health")"
  [[ "$(jq -c . <<<"$body" 2>/dev/null)" == '{"ok":true}' || $SECONDS -ge $deadline ]] && break
  sleep 2
done
if [[ "$(jq -c . <<<"$body" 2>/dev/null)" == '{"ok":true}' ]]; then
  ok "/demos/api/health says ok"
else
  bad "/demos/api/health: ${body:-no answer}"
fi

# The page, with its policy as a header (which, unlike its meta tag,
# forbids framing).
code="$(curl -s --max-time 5 -D "$tmp/page.headers" -o "$tmp/page.html" -w '%{http_code}' "$base/")"
if [[ "$code" == 200 ]] && grep -q '<title>aityx demos</title>' "$tmp/page.html" &&
  grep -qi "^content-security-policy:.*frame-ancestors 'none'" "$tmp/page.headers"; then
  ok "the page answers on $base/, with its content security policy"
else
  bad "the page on $base/: HTTP $code, or no title or policy"
fi

# /demos/api/demos: the six demos, each built for the path it's served at.
want="Cellfie=true ContactHub=true MortgageHub=true PokerFace=true RiverRace=true RoboRules=true"
got="$(curl -s --max-time 5 "$base/api/demos" |
  jq -r '.demos | map("\(.folder)=\(.served)") | join(" ")' 2>/dev/null)"
if [[ "$got" == "$want" ]]; then
  ok "/demos/api/demos lists the six demos, each built for its path"
else
  bad "/demos/api/demos: want $want, got ${got:-no answer}"
fi

# Each demo: its index.html with its base href, its main.dart.js, and
# CanvasKit from this origin (built with --no-web-resources-cdn).
for slug in cellfie contacthub mortgagehub pokerface riverrace roborules; do
  code="$(curl -s --max-time 5 -o "$tmp/$slug.html" -w '%{http_code}' "$base/$slug/")"
  if [[ "$code" != 200 ]] || ! grep -q "<base href=\"/demos/$slug/\">" "$tmp/$slug.html"; then
    bad "/demos/$slug/: HTTP $code, or no base href /demos/$slug/"
    continue
  fi
  read -r code size type < <(curl -s --max-time 20 -o /dev/null \
    -w '%{http_code} %{size_download} %{content_type}\n' "$base/$slug/main.dart.js")
  if [[ "$code" != 200 || "${size:-0}" -lt 100000 || "$type" != text/javascript* ]]; then
    bad "/demos/$slug/main.dart.js: HTTP $code, ${size:-0} bytes, ${type:-no type}"
    continue
  fi
  wasm="$(curl -s --max-time 20 -o /dev/null -w '%{http_code}' "$base/$slug/canvaskit/canvaskit.wasm")"
  if [[ "$wasm" != 200 ]]; then
    bad "/demos/$slug/canvaskit/canvaskit.wasm: HTTP $wasm (CanvasKit not in the build)"
    continue
  fi
  ok "/demos/$slug/: index.html for its path, main.dart.js ($((size / 1024)) KB), CanvasKit from this origin"
done

# The dev proxy's settings: a key, from the environment (the demo-env
# Secret), never from a .env file. Only the answer's fields are read: it
# never holds the key.
config="$(curl -s --max-time 5 "$base/aityx/config")"
if [[ "$(jq -r '"\(.available) \(.source)"' <<<"$config" 2>/dev/null)" == "true environment" ]]; then
  ok "/demos/aityx/config: the dev proxy has a key, from the environment"
else
  bad "/demos/aityx/config: $(jq -c '{available, source, detail}' <<<"$config" 2>/dev/null || echo no answer)"
fi

# A real call through the dev proxy, on the server's key: one generation
# of Life on aityx, with the Cellfie app's model as the build serves it
# (assets/models/life.json) and a board of three situations: a live cell
# with two neighbours survives, an empty one with three is born, a live
# one with one dies.
model="$tmp/life.json"
code="$(curl -s --max-time 10 -o "$model" -w '%{http_code}' "$base/cellfie/assets/assets/models/life.json")"
if [[ "$code" != 200 ]] || ! jq -e '.decision' "$model" >/dev/null 2>&1; then
  bad "the Cellfie model, $base/cellfie/assets/assets/models/life.json: HTTP $code"
else
  jq -c '. + {state: {generation: 7,
    rules: {conway: true, highlife: false, no_death: false},
    situations: [{alive: true, neighbours: 2, cells: 1},
                 {alive: false, neighbours: 3, cells: 1},
                 {alive: true, neighbours: 1, cells: 1}],
    clusters: []}}' "$model" >"$tmp/request.json"
  code="$(curl -s --max-time 60 -o "$tmp/answer.json" -w '%{http_code}' \
    -H 'Content-Type: application/json' --data-binary "@$tmp/request.json" \
    "$base/aityx/v1/systemone")"
  fates="$(jq -c '.answers.fates.value' "$tmp/answer.json" 2>/dev/null)"
  next="$(jq -r '.answers.next_generation.number' "$tmp/answer.json" 2>/dev/null)"
  if [[ "$code" == 200 && "$fates" == '["survives","is_born","dies_lonely"]' && "$next" == 8 ]]; then
    ok "aityx through the dev proxy, on the server's key: Cellfie's Life model decided survives, is_born, dies_lonely"
  else
    bad "aityx through the dev proxy: HTTP $code, $(jq -c '{code, detail, decision_error, fates: .answers.fates.value}' "$tmp/answer.json" 2>/dev/null | head -c 300)"
  fi
fi

# The proxy answers this origin's pages only: a request from a page of
# another site, and one whose Host isn't this machine (a page that reached
# it through DNS rebinding), are refused before aityx is called.
refused() {
  curl -s --max-time 5 -o "$tmp/refused.json" -w '%{http_code}' -X POST \
    -H 'Content-Type: application/json' --data '{}' "$@" "$base/aityx/v1/systemone"
  printf ' %s' "$(jq -r '.code' "$tmp/refused.json" 2>/dev/null)"
}
got="$(refused -H 'Sec-Fetch-Site: cross-site')"
if [[ "$got" == "403 proxy_cross_site" ]]; then
  ok "the dev proxy refuses a page of another site (403 proxy_cross_site)"
else
  bad "the dev proxy, from another site: want 403 proxy_cross_site, got $got"
fi
got="$(refused -H 'Host: rebound.example:18800')"
if [[ "$got" == "403 proxy_cross_site" ]]; then
  ok "the dev proxy refuses a Host that isn't this machine, as on a laptop (403 proxy_cross_site)"
else
  bad "the dev proxy, Host rebound.example: want 403 proxy_cross_site, got $got"
fi

exit $failed
