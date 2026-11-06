#!/usr/bin/env bash
# Makes each demo's recording an MP4 beside its GIF in www/ (<slug>.mp4),
# which the aityx website's blueprint pages play instead of the GIF: a
# browser decodes H.264 on the GPU, smoothly at any size, where a GIF is
# decoded frame by frame on the CPU and stutters once scaled up. The GIF
# stays, for the index page's cards and as the fallback.
#
#   bash Index/scripts/make-videos.sh                       # every www/*.gif
#   bash Index/scripts/make-videos.sh ~/Desktop/cellfie.mov # a screen recording
#
# A file given is named after its demo's slug (cellfie.mov → www/cellfie.mp4).
# A GIF keeps its own frames: the video plays them smoothly, but no more of
# them than the GIF has. For more motion, pass the original screen
# recording. WIDTH (1440 unless set; never scaled up) and FPS (30) shape
# the output. Needs ffmpeg (brew install ffmpeg).
set -euo pipefail

www="$(cd "$(dirname "$0")/../www" && pwd)"
width="${WIDTH:-1440}"
fps="${FPS:-30}"

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "✗ ffmpeg is not installed: brew install ffmpeg (or your package manager's)" >&2
  exit 1
fi

sources=("$@")
if [[ ${#sources[@]} -eq 0 ]]; then
  shopt -s nullglob
  sources=("$www"/*.gif)
fi
if [[ ${#sources[@]} -eq 0 ]]; then
  echo "✗ no GIFs in $www and no file given" >&2
  exit 1
fi

for source in "${sources[@]}"; do
  name="$(basename "$source")"
  slug="$(printf '%s' "${name%.*}" | tr '[:upper:]' '[:lower:]')"
  out="$www/$slug.mp4"
  # Constant frame rate (a GIF's frames last as long as their delays say),
  # an even size (H.264 needs one), yuv420p (what every browser plays), no
  # audio, and the index at the front so it starts before it has loaded.
  ffmpeg -hide_banner -loglevel error -y -i "$source" -an \
    -vf "fps=$fps,scale='min($width,iw)':-2:flags=lanczos,format=yuv420p" \
    -c:v libx264 -preset slow -crf 22 -movflags +faststart \
    "$out"
  echo "✓ $out ($(du -h "$out" | cut -f1 | tr -d ' '), from $name)"
done
