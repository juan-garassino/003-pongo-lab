#!/usr/bin/env bash
# A six-second H.264/AAC test served over the laptop's local network.
set -euo pipefail
cd "$(dirname "$0")/.."
for tool in ffmpeg python3; do
  command -v "$tool" >/dev/null || { echo "Missing $tool" >&2; exit 1; }
done

mkdir -p build/video-test
ffmpeg -y -hide_banner -loglevel error \
  -f lavfi -i testsrc2=size=640x360:rate=24 \
  -f lavfi -i sine=frequency=440:sample_rate=44100 -t 6 \
  -c:v libx264 -profile:v baseline -level:v 3.0 -pix_fmt yuv420p \
  -preset ultrafast -b:v 500k -g 48 -sc_threshold 0 \
  -c:a aac -b:a 64k -ac 2 \
  -f hls -hls_time 2 -hls_playlist_type vod -hls_flags independent_segments \
  build/video-test/test.m3u8

cat > build/video-test/index.html <<'HTML'
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>iPad video test</title></head>
<body style="background:#18202b;color:#fff;font-family:Arial,sans-serif;margin:24px">
<h1>iPad video test</h1>
<p>Tap Play. You should see a moving pattern and hear a tone for six seconds.</p>
<video controls playsinline style="width:100%;max-width:800px" preload="metadata">
<source src="test.m3u8" type="application/vnd.apple.mpegurl">
</video>
<p>This video comes from your laptop over the local network.</p>
</body></html>
HTML

echo "Open http://YOUR-LAPTOP-WIFI-IP:${1:-8765} in iPad Safari."
echo "Use the same local network. Stop the server with Ctrl-C."
exec python3 -m http.server "${1:-8765}" --bind 0.0.0.0 --directory build/video-test
