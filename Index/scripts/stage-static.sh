#!/usr/bin/env bash
# Puts the six aityx demos and the index page in one folder a static host
# serves as it is (Cloudflare Pages, demos.aityx.ai): the same layout
# bin/server.dart serves, everything under /demos/, with its headers as a
# _headers file. The aityx website's blueprint pages frame the demos and
# key.html from there.
#
#   ./build-all.sh                     # the release web builds, first
#   bash Index/scripts/stage-static.sh # → Index/static/
#   EMBED_ANCESTORS="https://aityx.ai https://stage.aityx.ai" \
#     bash Index/scripts/stage-static.sh
#
# EMBED_ANCESTORS: the pages allowed to frame key.html and the demos
# (space-separated origins), https://aityx.ai unless set. OUT: the folder,
# Index/static unless set; emptied first. A demo without a build made for
# /demos/<slug>/ stops the script: run ./build-all.sh <Folder>.
#
# Why a host of their own: the key lives in this origin's storage, and the
# aityx website runs third-party tags. demos.aityx.ai is the same site as
# aityx.ai, so the browser keeps the key the same in a frame of the
# website as on demos.aityx.ai itself, and no script of the website's
# reaches it.
set -euo pipefail

index="$(cd "$(dirname "$0")/.." && pwd)"
root="$(cd "$index/.." && pwd)"
out="${OUT:-$index/static}"
ancestors="${EMBED_ANCESTORS:-https://aityx.ai}"
group="$(tr -d '[:space:]' <"$index/group.id.txt")"

rm -rf "$out"
mkdir -p "$out/demos"

# The page, key.html, index.js, the GIFs and their MP4s
# (scripts/make-videos.sh): www/ as it is.
cp -R "$index/www/." "$out/demos/"

# Keep it the same as bin/server.dart's _pageCsp.
page_csp="default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self' https://*.aityx.ai; base-uri 'none'; form-action 'none'"

headers="$out/_headers"
cat >"$headers" <<EOF
/*
  X-Content-Type-Options: nosniff
  Referrer-Policy: same-origin

/demos/
  Content-Security-Policy: $page_csp; frame-ancestors 'none'

/demos/index.html
  Content-Security-Policy: $page_csp; frame-ancestors 'none'

/demos/key.html
  Content-Security-Policy: $page_csp; frame-ancestors 'self' $ancestors
EOF

cat >"$out/_redirects" <<'EOF'
/ /demos/ 301
/demos /demos/ 301
EOF

staged=()
for dir in "$root"/*/; do
  dir="${dir%/}"
  folder="$(basename "$dir")"
  slug="$(printf '%s' "$folder" | tr '[:upper:]' '[:lower:]')"
  [[ "$(tr -d '[:space:]' <"$dir/group.id.txt" 2>/dev/null)" == "$group" ]] || continue
  # A Flutter app, or a static page (Outpost).
  [[ -f "$dir/${slug}_app/pubspec.yaml" || -f "$dir/${slug}_app/web/index.html" ]] || continue
  web="$dir/${slug}_app/build/web"
  if ! grep -q "<base href=\"/demos/$slug/\"" "$web/index.html" 2>/dev/null; then
    echo "✗ $folder: no build for /demos/$slug/: run ./build-all.sh $folder" >&2
    exit 1
  fi
  mkdir -p "$out/demos/$slug"
  # Not the build's own records (.aityx-services, .last_build_id).
  rsync -a --exclude '.*' "$web/" "$out/demos/$slug/"
  printf '\n/demos/%s/*\n  Content-Security-Policy: frame-ancestors '"'"'self'"'"' %s\n' "$slug" "$ancestors" >>"$headers"
  staged+=("$folder")
done

echo "Staged ${staged[*]} in $out, framed by: $ancestors"
echo "Deploy it with: npx wrangler pages deploy \"$out\" --project-name aityx-demos"
