#!/usr/bin/env bash
# Prepare and optionally serve a user-supplied movie as iPad-compatible HLS.
# The source is never committed to the repository and no device is contacted.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
input=""
port=8766
height=720
prepare_only=0
output="$ROOT/build/movie-lane"

usage() {
  cat <<'EOF'
Usage: scripts/serve-movie.sh [OPTIONS] MOVIE_FILE

Prepare a locally owned movie for fullscreen Safari playback on the iPad.
The transcode is RAM/disk-local and stored only under ignored build/.

Options:
  --prepare-only       Transcode and exit; do not start the HTTP server
  --height PIXELS      Vertical output cap (default: 720)
  --output DIR         Output directory (default: build/movie-lane)
  --port PORT          HTTP port (default: 8766)
  -h, --help           Show this help

The file must contain an audio stream. No copyrighted media is downloaded,
committed, or redistributed by this script.
EOF
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --prepare-only) prepare_only=1 ;;
    --height)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      height=$2
      shift
      ;;
    --output)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      output=$2
      shift
      ;;
    --port)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      port=$2
      shift
      ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *)
      [[ -z $input ]] || { echo "only one movie file may be given" >&2; exit 2; }
      input=$1
      ;;
  esac
  shift
done

while [[ $# -gt 0 ]]; do
  [[ -z $input ]] || { echo "only one movie file may be given" >&2; exit 2; }
  input=$1
  shift
done

[[ -n $input && -f $input ]] || {
  echo "Movie file not found: ${input:-<missing>}" >&2
  usage >&2
  exit 2
}
[[ $height =~ ^[0-9]+$ && $height -ge 240 && $height -le 1080 ]] || {
  echo "--height must be between 240 and 1080" >&2
  exit 2
}
[[ $port =~ ^[0-9]+$ && $port -ge 1024 && $port -le 65535 ]] || {
  echo "--port must be between 1024 and 65535" >&2
  exit 2
}

for tool in ffmpeg ffprobe python3; do
  command -v "$tool" >/dev/null || {
    echo "Missing required tool: $tool" >&2
    exit 1
  }
done

audio_streams=$(
  ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$input" |
    grep -c . || true
)
[[ "$audio_streams" -gt 0 ]] || {
  echo "The movie has no audio stream; this movie-lane test requires audio." >&2
  exit 1
}

mkdir -p "$output"
playlist="$output/movie.m3u8"

printf '%s\n' "==> Preparing iPad-compatible HLS (height cap: ${height}px)"
ffmpeg -y -hide_banner -loglevel error \
  -i "$input" \
  -map 0:v:0 -map 0:a:0 \
  -vf "scale=-2:min(${height}\\,ih),fps=30" \
  -c:v libx264 -profile:v baseline -level:v 3.1 -pix_fmt yuv420p \
  -preset veryfast -crf 23 -g 90 -sc_threshold 0 \
  -c:a aac -b:a 128k -ar 48000 -ac 2 \
  -f hls -hls_time 6 -hls_playlist_type vod \
  -hls_flags independent_segments \
  "$playlist"

python3 - "$input" "$output/index.html" <<'PY'
from html import escape
from pathlib import Path
import sys

source, destination = map(Path, sys.argv[1:])
title = source.stem.replace("-", " ").replace("_", " ").strip() or "Movie"
page = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
  <title>{escape(title)}</title>
  <style>
    html,body {{ margin:0; height:100%; background:#000; overflow:hidden;
                 font-family:system-ui,-apple-system,sans-serif; }}
    video {{ width:100vw; height:100vh; object-fit:contain; background:#000; }}
    #hint {{ position:fixed; left:50%; bottom:max(12px,env(safe-area-inset-bottom));
             transform:translateX(-50%); color:#fff; background:rgba(0,0,0,.65);
             padding:10px 14px; border-radius:10px; font-size:15px;
             opacity:1; transition:opacity .4s; pointer-events:none; }}
    video:playing + #hint {{ opacity:0; }}
  </style>
</head>
<body>
  <video controls playsinline webkit-playsinline preload="metadata">
    <source src="movie.m3u8" type="application/vnd.apple.mpegurl">
  </video>
  <div id="hint">Tap Play for fullscreen movie with audio</div>
</body>
</html>
"""
destination.write_text(page, encoding="utf-8")
PY

duration=$(
  ffprobe -v error -show_entries format=duration -of csv=p=0 "$input" |
    cut -d. -f1
)
segments=$(find "$output" -maxdepth 1 -name '*.ts' | wc -l)
printf 'Prepared: %s\nDuration: %ss\nSegments: %s\nOutput:  %s\n' \
  "$input" "${duration:-unknown}" "$segments" "$playlist"

if [[ $prepare_only -eq 1 ]]; then
  echo "Prepare-only requested; no HTTP server was started."
  exit 0
fi

lan_ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i=="src") {print $(i+1); exit}}')
printf 'Open http://%s:%s in iPad Safari on the same Wi-Fi network.\n' \
  "${lan_ip:-YOUR-LAPTOP-WIFI-IP}" "$port"
echo 'Stop the server with Ctrl-C.'
exec python3 -m http.server "$port" --bind 0.0.0.0 --directory "$output"
