#!/usr/bin/env bash
# Checks the multyx index on the local cluster from this host, on
# http://127.0.0.1:19700/ (k8s/kind/cluster.yaml): the page at / and
# /app/, /api/health, /api/demos seeing tatyx and Poker Tour up through
# their Services, and the page's Open links, worked out by the page's own
# script as a browser on :19700 would, pointing at tatyx on :19710 and
# Poker Tour on :19810, which answer (and, from :9700 or :9750, at their
# usual ports). One line per check; exits 1 if any fails. Needs curl, jq
# and node.
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

# The page's Open links, from the page as served: its script run in Node
# with a stand-in for the browser's document and a location on this host
# at port $PORT. Each card's id and the href of its Open button.
get / "$tmp/page.html" >/dev/null
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
vm.runInNewContext(script, { document, location });
for (const card of cards) {
  console.log(card.id + ' ' + (/class="btn primary" href="([^"]+)"/.exec(card.innerHTML)?.[1] ?? 'none'));
}
JS

# check_links <port> <tatyx port> <Poker Tour port> [answer]: from the page
# on <port>, the cards open tatyx and Poker Tour on those ports; with
# answer, those links must answer too.
check_links() {
  local port="$1" answer="${4:-}" links want card url got status
  links="$(PAGE="$tmp/page.html" PORT="$port" node "$tmp/links.js" 2>&1)"
  for want in "demo-tatyx http://127.0.0.1:$2/tatyx/" "demo-poker-tour http://127.0.0.1:$3/pokertour/"; do
    card="${want%% *}" url="${want#* }"
    if ! grep -qxF "$want" <<<"$links"; then
      # The card's line, or what Node said when the script didn't run.
      got="$(grep -F "$card " <<<"$links" | head -1)"
      fail "the page's $card link from :$port" "expected $url, got: ${got:-$(head -1 <<<"$links")}"
    elif [[ -z "$answer" ]]; then
      ok "the page's $card link from :$port is $url"
    else
      status="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$url" 2>/dev/null || true)"
      if [[ "$status" =~ ^[23][0-9][0-9]$ ]]; then
        ok "the page's $card link from :$port is $url, which answers (HTTP $status)"
      else
        fail "the page's $card link $url" "HTTP $status"
      fi
    fi
  done
}

# From the cluster's port, every demo at its usual port plus 10000; from
# the usual port, or any other (INDEX_PORT=9750, a forwarded port), the
# usual ports, as a local run expects.
check_links 19700 19710 19810 answer
check_links 9700 9710 9810
check_links 9750 9710 9810

exit $failed
