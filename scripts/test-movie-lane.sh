#!/usr/bin/env bash
# Local movie-lane test using generated media only; no device is contacted.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$ROOT/build/movie-test/selftest"

for tool in ffmpeg ffprobe; do
  command -v "$tool" >/dev/null || {
    echo "Missing required tool: $tool" >&2
    exit 1
  }
done

mkdir -p "$work"
ffmpeg -y -hide_banner -loglevel error \
  -f lavfi -i smptehdbars=size=320x180:rate=12 \
  -f lavfi -i sine=frequency=660:sample_rate=48000 \
  -t 2 -c:v libx264 -pix_fmt yuv420p -c:a aac -b:a 64k \
  "$work/source.mp4"

"$ROOT/scripts/serve-movie.sh" --prepare-only --height 240 \
  --output "$work/hls" "$work/source.mp4" >/dev/null

[[ -s "$work/hls/movie.m3u8" ]]
[[ -s "$work/hls/index.html" ]]
grep -q 'application/vnd.apple.mpegurl' "$work/hls/index.html"
grep -q 'playsinline' "$work/hls/index.html"

streams=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,profile \
  -of default=nw=1:nk=1 "$work/hls"/movie*.ts | tr '\n' ' ')
grep -qw h264 <<<"$streams"
grep -qw Baseline <<<"$streams"

aac_streams=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name \
  -of default=nw=1:nk=1 "$work/hls"/movie*.ts | tr '\n' ' ')
grep -qw aac <<<"$aac_streams"

echo "Movie lane self-test passed with generated H.264/AAC HLS media."
