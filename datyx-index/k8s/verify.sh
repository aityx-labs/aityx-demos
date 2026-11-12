#!/usr/bin/env bash
# Checks the datyx index on the local cluster, from this host
# (http://127.0.0.1:19800/): the page and its health check; /api/demos,
# which asks the datyx API, the dashboard and HealthHub inside the
# cluster whether they're up; /api/settings, which must say the cluster's
# host ports (k8s/deployment.yaml sets them); and the page's links: its
# own script, run in node as a browser would run it, must point each card
# at the port the settings say, whatever port the page itself is on, and
# those links must answer. One line per check; exits 1 if any fails.
# Needs curl, jq and node.
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

# /api/settings: this copy is the cluster's, and every system is where
# k8s/kind/cluster.yaml publishes it on this host. DATYX_DEBUG_PORT is
# left out: the cluster publishes no debugger, and the page names that
# port in a local run only.
want='{"cluster":true,"ports":{"AITYX_INDEX_PORT":18800,"MULTYX_INDEX_PORT":19700,"DATYX_INDEX_PORT":19800,"DATYX_DASHBOARD_WEB_PORT":19906,"DATYX_API_PORT":19900,"DATYX_OPENMETADATA_PORT":19902,"HEALTHHUB_WEB_PORT":19801,"HEALTHHUB_FLINK_PORT":19806}}'
curl -s --max-time 5 -o "$tmp/cluster-settings.json" "$base/api/settings"
got="$(jq -cS 'del(.ports.DATYX_DEBUG_PORT)' "$tmp/cluster-settings.json" 2>/dev/null)"
if [[ -n "$got" && "$got" == "$(jq -cS . <<<"$want")" ]]; then
  ok "/api/settings says the cluster's ports: $(jq -r '.ports | [.DATYX_INDEX_PORT, .DATYX_DASHBOARD_WEB_PORT, .DATYX_API_PORT, .DATYX_OPENMETADATA_PORT, .HEALTHHUB_WEB_PORT, .HEALTHHUB_FLINK_PORT, .AITYX_INDEX_PORT, .MULTYX_INDEX_PORT] | join(" ")' "$tmp/cluster-settings.json")"
else
  bad "/api/settings: want $want, got ${got:-$(head -c 200 "$tmp/cluster-settings.json" 2>/dev/null)}"
fi

# The page takes every port from those settings: it reads neither its own
# port nor a shift to add to the usual ones.
if grep -qE 'location\.port|10000' "$tmp/page.html"; then
  bad "the page still reads its own port or adds 10000: $(grep -nE 'location\.port|10000' "$tmp/page.html" | head -1)"
else
  ok "the page reads no port of its own and adds none: its ports are /api/settings'"
fi

# links <origin> <settings>: the http:// links the page's script makes
# when the page is served from <origin> and its server answers
# /api/settings with the file <settings>, one per line, from a fake
# location, a fetch that answers only that, and a document that only
# records the cards.
links() {
  node -e '
    const fs = require("fs"), vm = require("vm");
    const [page, origin, settings] = process.argv.slice(1);
    const html = fs.readFileSync(page, "utf8");
    const answer = JSON.parse(fs.readFileSync(settings, "utf8"));
    const url = new URL(origin), cards = [];
    const document = {
      createElement: () => { const el = {}; cards.push(el); return el; },
      getElementById: () => ({ replaceChildren() {} }),
    };
    const fetch = async (path) => path === "/api/settings"
      ? { ok: true, status: 200, json: async () => answer }
      : { ok: false, status: 404, json: async () => ({}) };
    const context = vm.createContext({ location: { hostname: url.hostname, port: url.port }, document, fetch });
    for (const m of html.matchAll(/<script>([\s\S]*?)<\/script>/g)) vm.runInContext(m[1], context);
    // The cards come once the settings have: after the pending promises.
    setTimeout(() => {
      for (const card of cards)
        for (const m of String(card.innerHTML).matchAll(/href="(http:[^"]+)"/g)) console.log(m[1]);
    }, 50);
  ' "$tmp/page.html" "$1" "$2"
}

# The cards' Open links for the settings the cluster's server answers,
# with the page on the cluster's port and on another (9800, where a page
# that worked the ports out from its own would open a local run's); and
# for a local run's settings, the usual ports, with the page on the
# cluster's port all the same. No link on another port (the dashboard's
# Training and Inference are on its own).
check_links() {
  local origin="$1" settings="$2" dashboard="$3" api="$4" healthhub="$5" all wanted missing="" stray link
  all="$(links "$origin" "$settings" 2>"$tmp/node.err")" || {
    bad "the page's script from $origin: $(head -1 "$tmp/node.err")"
    return 1
  }
  wanted="$dashboard/app/ $api/q/swagger-ui $healthhub/app/"
  for link in $wanted; do
    grep -qxF "http://127.0.0.1:$link" <<<"$all" || missing+=" $link"
  done
  stray="$(grep -vE "^http://127\.0\.0\.1:($dashboard|$api|$healthhub)/" <<<"$all" | tr '\n' ' ')"
  if [[ -z "$missing" && -z "$stray" ]]; then
    ok "served from $origin with ${settings##*/}, the cards open :${wanted// / :} ($(wc -l <<<"$all" | tr -d ' ') links, none elsewhere)"
  else
    bad "served from $origin with ${settings##*/}, the cards lack:${missing:- nothing}; stray links: ${stray:-none}"
    return 1
  fi
}
cat >"$tmp/local-settings.json" <<'JSON'
{"cluster":false,"ports":{"AITYX_INDEX_PORT":8800,"MULTYX_INDEX_PORT":9700,"DATYX_INDEX_PORT":9800,"DATYX_DASHBOARD_WEB_PORT":9906,"DATYX_API_PORT":9900,"DATYX_OPENMETADATA_PORT":9902,"DATYX_DEBUG_PORT":9905,"HEALTHHUB_WEB_PORT":9801,"HEALTHHUB_FLINK_PORT":9806}}
JSON
check_links "$base" "$tmp/cluster-settings.json" 19906 19900 19801
check_links "http://127.0.0.1:9800" "$tmp/cluster-settings.json" 19906 19900 19801
check_links "$base" "$tmp/local-settings.json" 9906 9900 9801

# Every link the page makes on the cluster answers, 2xx, or a
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
done < <(links "$base" "$tmp/cluster-settings.json" 2>/dev/null | grep -E '^http://127\.0\.0\.1:19[0-9]{3}/' | sort -u)

exit $failed
