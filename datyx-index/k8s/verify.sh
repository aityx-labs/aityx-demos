#!/usr/bin/env bash
# Checks the datyx index on the local cluster, from this host
# (http://127.0.0.1:19800/): the page and its health check; /api/demos,
# which asks the datyx API, the dashboard and HealthHub inside the
# cluster whether they're up; and the page's links: its own script, run
# in node as a browser would run it from :19800, must point each card at
# its demo's port plus 10000 (and, from :9800 or any other port such as
# :9850, at the usual one), and those links must answer. One line per
# check; exits 1 if any fails.
#
#   bash datyx-index/k8s/verify.sh
set -uo pipefail

base="http://127.0.0.1:19800"
failed=0
ok() { echo "✅ $*"; }
bad() {
  echo "✗ $*"
  failed=1
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# The page.
code="$(curl -s --max-time 5 -o "$tmp/page.html" -w '%{http_code}' "$base/")"
if [[ "$code" == 200 ]] && grep -q '<title>datyx</title>' "$tmp/page.html"; then
  ok "the page answers on $base/"
else
  bad "the page on $base/: HTTP $code"
fi

# The health check.
body="$(curl -s --max-time 5 "$base/api/health")"
if [[ "$(jq -c . <<<"$body" 2>/dev/null)" == '{"ok":true}' ]]; then
  ok "/api/health says ok"
else
  bad "/api/health: ${body:-no answer}"
fi

# /api/demos: the three systems INDEX_DEMOS names, each up. They may
# still be starting, so ask again for up to 45 s.
want="HealthHub=true datyx=true datyx-dashboard=true"
deadline=$((SECONDS + 45))
while :; do
  got="$(curl -s --max-time 10 "$base/api/demos" |
    jq -r '.demos | map("\(.folder)=\(.up)") | join(" ")' 2>/dev/null)"
  [[ "$got" == "$want" || $SECONDS -ge $deadline ]] && break
  sleep 5
done
if [[ "$got" == "$want" ]]; then
  ok "/api/demos lists datyx, datyx-dashboard and HealthHub, all up in the cluster"
else
  bad "/api/demos: want $want, got ${got:-no answer}"
fi

# links <origin>: the http:// links the page's script makes when the page
# is served from <origin>, one per line, from a fake location and a
# document that only records the cards.
links() {
  node -e '
    const fs = require("fs"), vm = require("vm");
    const [page, origin] = process.argv.slice(1);
    const html = fs.readFileSync(page, "utf8");
    const url = new URL(origin), cards = [];
    const document = {
      createElement: () => { const el = {}; cards.push(el); return el; },
      getElementById: () => ({ replaceChildren() {} }),
    };
    const context = vm.createContext({ location: { hostname: url.hostname, port: url.port }, document });
    for (const m of html.matchAll(/<script>([\s\S]*?)<\/script>/g)) vm.runInContext(m[1], context);
    for (const card of cards)
      for (const m of String(card.innerHTML).matchAll(/href="(http:[^"]+)"/g)) console.log(m[1]);
  ' "$tmp/page.html" "$1"
}

# The cards' Open links, served from the cluster's port, from the usual
# one and from another (INDEX_PORT=9850, a forwarded port), where a local
# run's must be unchanged; and no link on another port (the dashboard's
# Training and Inference are on its own).
check_links() {
  local origin="$1" dashboard="$2" api="$3" healthhub="$4" all wanted missing="" stray link
  all="$(links "$origin" 2>"$tmp/node.err")" || {
    bad "the page's script from $origin: $(head -1 "$tmp/node.err")"
    return 1
  }
  wanted="$dashboard/app/ $api/q/swagger-ui $healthhub/app/"
  for link in $wanted; do
    grep -qxF "http://127.0.0.1:$link" <<<"$all" || missing+=" $link"
  done
  stray="$(grep -vE "^http://127\.0\.0\.1:($dashboard|$api|$healthhub)/" <<<"$all" | tr '\n' ' ')"
  if [[ -z "$missing" && -z "$stray" ]]; then
    ok "served from $origin, the cards open :${wanted// / :} ($(wc -l <<<"$all" | tr -d ' ') links, none elsewhere)"
  else
    bad "served from $origin, the cards lack:${missing:- nothing}; stray links: ${stray:-none}"
    return 1
  fi
}
check_links "http://127.0.0.1:9800" 9906 9900 9801
check_links "http://127.0.0.1:9850" 9906 9900 9801
check_links "$base" 19906 19900 19801

# Every link the page makes from the cluster's port answers, 2xx, or a
# 3xx to the same origin that then answers 2xx (the Swagger UI's
# /q/swagger-ui to /q/swagger-ui/). A redirect elsewhere fails: it could
# reach a demo running locally on its usual port instead.
while IFS= read -r link; do
  [[ -n "$link" ]] || continue
  origin="$(sed -E 's#^(https?://[^/]+).*#\1#' <<<"$link")"
  read -r code next < <(curl -s --max-time 10 -o /dev/null -w '%{http_code} %{redirect_url}\n' "$link")
  if [[ "$code" == 3* && "$next" == "$origin/"* ]]; then
    code="$(curl -s --max-time 10 -o /dev/null -w '%{http_code}' "$next")"
  fi
  if [[ "$code" == 2* ]]; then
    ok "$link answers ($code)"
  else
    bad "$link: HTTP $code${next:+ (to $next)}"
  fi
done < <(links "$base" 2>/dev/null | grep -E '^http://127\.0\.0\.1:19[0-9]{3}/' | sort -u)

exit $failed
