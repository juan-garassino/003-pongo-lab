#!/usr/bin/env bash
# Build a RAM-only m1n1 + Hoolock Linux payload. This script never opens USB.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCES="${LINUX_RESEARCH_SOURCE_DIR:-$ROOT/build/sources}"
M1N1="$SOURCES/m1n1-idevice/build/m1n1.bin"
LINUX="$ROOT/build/linux-j85"
OUT="$ROOT/build/m1n1-j85-ram-only.bin"
INITRAMFS="$ROOT/build/linux-j85/initramfs.gz"
TOUCH_FW="$ROOT/build/linux-j85/firmware/apple/j85-multitouch.bin"
BOOTARGS='chosen.bootargs=earlycon keep_boot_con console=tty0 ignore_loglevel loglevel=8 rdinit=/init panic=0 cpufreq.off=1'

for artifact in "$M1N1" "$LINUX/Image.gz" "$LINUX/s5l8960x-j85.dtb" "$INITRAMFS" "$TOUCH_FW"; do
  [[ -s "$artifact" ]] || { echo "Missing artifact: $artifact" >&2; exit 1; }
done

[[ "$(xxd -p -l4 "$LINUX/s5l8960x-j85.dtb")" == d00dfeed ]] || {
  echo "J85 DTB has invalid FDT magic" >&2
  exit 1
}
[[ "$(xxd -p -l2 "$LINUX/Image.gz")" == 1f8b ]] || {
  echo "Kernel Image.gz has invalid gzip magic" >&2
  exit 1
}
[[ "$(xxd -p -l2 "$INITRAMFS")" == 1f8b ]] || {
  echo "initramfs has invalid gzip magic" >&2
  exit 1
}

{
  cat "$M1N1"
  printf '%s\n' "$BOOTARGS"
  cat "$LINUX/s5l8960x-j85.dtb"
  cat "$LINUX/Image.gz"
  cat "$INITRAMFS"
} > "$OUT"

manifest="$ROOT/build/linux-j85/manifest.sha256"
: > "$manifest"
sha256sum "$M1N1" "$LINUX/s5l8960x-j85.dtb" \
  "$LINUX/Image.gz" "$INITRAMFS" "$TOUCH_FW" "$OUT" > "$manifest"
cat "$manifest"
ls -lh "$OUT"
cat <<'EOF'
RAM-only payload prepared. No USB command was issued.
Sending bootm or this payload requires a separate explicit approval.
EOF
