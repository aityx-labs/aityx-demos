#!/usr/bin/env bash
# Checks the multyx index on the local cluster from this host, on
# http://127.0.0.1:19700/ (k8s/kind/cluster.yaml): the page at / and
# /app/, /api/health, /api/demos seeing tatyx and Poker Tour up through
# their Services, /api/settings saying the cluster's host ports
# (k8s/deployment.yaml sets them), and the page's Open links, worked out
# by the page's own script as a browser would from those settings,
# pointing at tatyx on :19710 and Poker Tour on :19810, which answer,
# whatever port the page itself is on. One line per check; exits 1 if any
# fails. Needs curl, jq and node.
set -uo pipefail

base="${MULTYX_INDEX_URL:-http://127.0.0.1:19700}"
failed=0
ok() { echo "✅ $1"; }
fail() { echo "✗ $1: $2"; failed=1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# get <path> <file>: the HTTP status of GET <base><path>, the body in <file>.
get() {
  curl -s -o "$2" -w '%{http_code}' --max-time 5 "$base$1" 2>/dev/null || true
}

# The page, at / and at /app/ (where start-all.sh looks for a demo).
for path in / /app/; do
  status="$(get "$path" "$tmp/page.html")"
  if [[ "$status" == 200 ]] && grep -q '<title>multyx</title>' "$tmp/page.html" && grep -q 'PokerTour' "$tmp/page.html"; then
    ok "the page answers at $path"
  else
    fail "the page at $path" "HTTP $status, or not the multyx index"
  fi
done

status="$(get /api/health "$tmp/health.json")"
if [[ "$status" == 200 ]] && jq -e '.ok == true' "$tmp/health.json" >/dev/null 2>&1; then
  ok "/api/health says ok"
else
  fail "/api/health" "HTTP $status: $(head -c 200 "$tmp/health.json" 2>/dev/null)"
fi

# /api/demos lists exactly the two demos INDEX_DEMOS names, each checked
# from inside the cluster (http://tatyx:9710/tatyx/, http://pokertour:9810/
# pokertour/). Either may be restarting: up to about 45 s for both.
deadline=$((SECONDS + 45))
while :; do
  status="$(get /api/demos "$tmp/demos.json")"
  if [[ "$status" == 200 ]] &&
    jq -e '[.demos[].folder] == ["PokerTour", "tatyx"] and all(.demos[]; .up == true)' "$tmp/demos.json" >/dev/null 2>&1; then
    ok "/api/demos lists PokerTour and tatyx, both up from inside the cluster"
    break
  fi
  if ((SECONDS >= deadline)); then
    fail "/api/demos" "HTTP $status: $(jq -c '[.demos[]? | {folder, url, up}]' "$tmp/demos.json" 2>/dev/null || head -c 200 "$tmp/demos.json")"
    break
  fi
  sleep 3
done

# /api/settings: this copy is the cluster's, and every demo is where
# k8s/kind/cluster.yaml publishes it on this host.
want='{"cluster":true,"ports":{"AITYX_INDEX_PORT":18800,"DATYX_INDEX_PORT":19800,"TATYX_PORT":19710,"POKERTOUR_WEB_PORT":19810}}'
status="$(get /api/settings "$tmp/cluster-settings.json")"
if [[ "$status" == 200 && "$(jq -cS . "$tmp/cluster-settings.json" 2>/dev/null)" == "$(jq -cS . <<<"$want")" ]]; then
  ok "/api/settings says the cluster's ports: tatyx $(jq -r '.ports | "\(.TATYX_PORT), Poker Tour \(.POKERTOUR_WEB_PORT), the aityx index \(.AITYX_INDEX_PORT), the datyx index \(.DATYX_INDEX_PORT)"' "$tmp/cluster-settings.json")"
else
  fail "/api/settings" "HTTP $status: want $want, got $(head -c 300 "$tmp/cluster-settings.json" 2>/dev/null)"
fi

# The page takes every port from those settings: it reads neither its own
# port nor a shift to add to the usual ones.
get / "$tmp/page.html" >/dev/null
if grep -qE 'location\.port|10000' "$tmp/page.html"; then
  fail "the page's ports" "it still reads its own port or adds 10000: $(grep -nE 'location\.port|10000' "$tmp/page.html" | head -1)"
else
  ok "the page reads no port of its own and adds none: its ports are /api/settings'"
fi

# The page's Open links, from the page as served: its script run in Node
# with a stand-in for the browser's document, a location on this host at
# port $PORT, and a fetch that answers /api/settings with the file
# $SETTINGS. Each card's id and the href of its Open button.
cat >"$tmp/links.js" <<'JS'
const fs = require('node:fs');
const vm = require('node:vm');
const html = fs.readFileSync(process.env.PAGE, 'utf8');
const script = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map((m) => m[1]).join('\n');
const cards = [];
const document = {
  createElement: () => ({ className: '', id: '', innerHTML: '' }),
  getElementById: () => ({ replaceChildren: (...children) => cards.push(...children) }),
};
const port = process.env.PORT;
const location = { hostname: '127.0.0.1', port, href: 'http://127.0.0.1:' + port + '/' };
const settings = JSON.parse(fs.readFileSync(process.env.SETTINGS, 'utf8'));
const fetch = async (path) =>
  path === '/api/settings' ? { ok: true, status: 200, json: async () => settings } : { ok: false, status: 404, json: async () => ({}) };
vm.runInNewContext(script, { document, location, fetch });
// The cards come once the settings have: after the pending promises.
setTimeout(() => {
  for (const card of cards) {
    console.log(card.id + ' ' + (/class="btn primary" href="([^"]+)"/.exec(card.innerHTML)?.[1] ?? 'none'));
  }
}, 50);
JS

# check_links <port> <settings> <tatyx port> <Poker Tour port> [answer]:
# from the page on <port> with the settings in the file <settings>, the
# cards open tatyx and Poker Tour on those ports; with answer, those links
# must answer too.
check_links() {
  local port="$1" settings="$2" answer="${5:-}" links want card url got status
  links="$(PAGE="$tmp/page.html" PORT="$port" SETTINGS="$settings" node "$tmp/links.js" 2>&1)"
  for want in "demo-tatyx http://127.0.0.1:$3/tatyx/" "demo-poker-tour http://127.0.0.1:$4/pokertour/"; do
    card="${want%% *}" url="${want#* }"
    if ! grep -qxF "$want" <<<"$links"; then
      # The card's line, or what Node said when the script didn't run.
      got="$(grep -F "$card " <<<"$links" | head -1)"
      fail "the page's $card link from :$port with ${settings##*/}" "expected $url, got: ${got:-$(head -1 <<<"$links")}"
    elif [[ -z "$answer" ]]; then
      ok "the page's $card link from :$port with ${settings##*/} is $url"
    else
      status="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$url" 2>/dev/null || true)"
      if [[ "$status" =~ ^[23][0-9][0-9]$ ]]; then
        ok "the page's $card link from :$port with ${settings##*/} is $url, which answers (HTTP $status)"
      else
        fail "the page's $card link $url" "HTTP $status"
      fi
    fi
  done
}

# With the settings the cluster's server answers, every demo on its
# cluster port, the page on the cluster's port or on another (9700, where
# a page that worked the ports out from its own would open a local
# run's); with a local run's settings, the usual ports, the page on the
# cluster's port all the same.
cat >"$tmp/local-settings.json" <<'JSON'
{"cluster":false,"ports":{"AITYX_INDEX_PORT":8800,"DATYX_INDEX_PORT":9800,"TATYX_PORT":9710,"POKERTOUR_WEB_PORT":9810}}
JSON
check_links 19700 "$tmp/cluster-settings.json" 19710 19810 answer
check_links 9700 "$tmp/cluster-settings.json" 19710 19810
check_links 19700 "$tmp/local-settings.json" 9710 9810

exit $failed
