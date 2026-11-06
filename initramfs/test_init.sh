#!/usr/bin/env bash
# Run initramfs/init on the laptop against a fake /sys, /proc, /dev and framebuffer.
# Uses host BusyBox, the same major version as the iPad's. Never opens USB.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INIT="$ROOT/initramfs/init"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
STRIDE=6144
HEIGHT=2048
UDC_NAME=20c100000.usbdev
failures=0

make_root() {
  local r=$1
  mkdir -p "$r"/{tmp,dev/input,proc/device-tree/chosen/framebuffer@1,sys/class/graphics/fb0}
  mkdir -p "$r/sys/kernel/config/usb_gadget"
  mkdir -p "$r/sys/bus/platform/drivers/dwc2/20c100000.usbdev"
  printf 'Apple iPad mini 2 (Wi-Fi)\0' > "$r/proc/device-tree/model"
  printf 'x8r8g8b8\0' > "$r/proc/device-tree/chosen/framebuffer@1/format"
  echo 'earlycon console=tty0' > "$r/proc/cmdline"
  echo '12.34 1.00' > "$r/proc/uptime"
  echo 'MemAvailable: 900000 kB' > "$r/proc/meminfo"
  mkdir -p "$r/proc/bus/input"
  echo 'N: Name="gpio-keys"' > "$r/proc/bus/input/devices"
  echo "$STRIDE" > "$r/sys/class/graphics/fb0/stride"
  echo "1536,$HEIGHT" > "$r/sys/class/graphics/fb0/virtual_size"
  echo 32 > "$r/sys/class/graphics/fb0/bits_per_pixel"
  truncate -s $((STRIDE * HEIGHT)) "$r/dev/fb0"
}

add_udc() {
  mkdir -p "$1/sys/class/udc/$UDC_NAME"
  echo "$2" > "$1/sys/class/udc/$UDC_NAME/state"
  echo high-speed > "$1/sys/class/udc/$UDC_NAME/current_speed"
}

run_init() {
  local r=$1 pages=${2:-2} wait=${3:-2}
  sed 's/@BUILD_ID@/test-build/' "$INIT" > "$r/init"
  J85_ROOT="$r" J85_MAX_PAGES="$pages" J85_UDC_WAIT="$wait" \
    timeout 60 busybox sh "$r/init" > "$r/out" 2>&1 </dev/null || {
      echo "  init exited with status $?"
      failures=$((failures + 1))
    }
}

expect_out() {
  local r=$1 name=$2 pattern=$3
  if grep -qE -- "$pattern" "$r/out"; then
    echo "  ok: $name"
  else
    echo "  FAIL: $name (no match for: $pattern)"
    failures=$((failures + 1))
  fi
}

expect_file() {
  local path=$1 name=$2 expected=$3 actual
  actual=$(cat "$path" 2>/dev/null || true)
  if [[ "$actual" == "$expected" ]]; then
    echo "  ok: $name"
  else
    echo "  FAIL: $name (expected '$expected', got '$actual')"
    failures=$((failures + 1))
  fi
}

# BGRX hex at the middle of the verdict band.
band_pixel() {
  od -An -tx1 -j $((STRIDE * (HEIGHT * 6 / 10 + 10))) -N 4 "$1/dev/fb0" | tr -d ' '
}

noise_written() {
  od -An -tx1 -v -j $((STRIDE * (HEIGHT * 8 / 10 + 5))) -N 64 "$1/dev/fb0" | tr -d ' \n' | grep -q '[1-9a-f]'
}

echo "connected host"
r=$WORK/connected
make_root "$r"
add_udc "$r" configured
run_init "$r"
expect_out "$r" "verdict" 'USB: CONNECTED +udc=20c100000.usbdev +state=configured +speed=high-speed +functions=acm\+ncm'
expect_out "$r" "build id" 'build test-build'
expect_out "$r" "diagnostics" 'driver dwc2: 20c100000.usbdev'
expect_out "$r" "fb format" 'fb format: x8r8g8b8'
expect_file "$r/sys/kernel/config/usb_gadget/j85/idVendor" "vendor" 0x1d6b
expect_file "$r/sys/kernel/config/usb_gadget/j85/idProduct" "product" 0x0104
expect_file "$r/sys/kernel/config/usb_gadget/j85/UDC" "UDC written" "$UDC_NAME"
[[ -L "$r/sys/kernel/config/usb_gadget/j85/configs/c.1/acm.usb0" ]] && echo "  ok: acm linked" || { echo "  FAIL: acm link"; failures=$((failures + 1)); }
expect_file <(band_pixel "$r") "green band" 00ff0000
noise_written "$r" && echo "  ok: noise drawn" || { echo "  FAIL: noise"; failures=$((failures + 1)); }
[[ "$(stat -c %s "$r/dev/fb0")" == $((STRIDE * HEIGHT)) ]] && echo "  ok: fb size unchanged" || { echo "  FAIL: fb size"; failures=$((failures + 1)); }

echo "waiting for host"
r=$WORK/waiting
make_root "$r"
add_udc "$r" 'not attached'
run_init "$r"
expect_out "$r" "verdict" 'USB: WAIT-HOST'
expect_file <(band_pixel "$r") "yellow band" 00ffff00

echo "no controller"
r=$WORK/noudc
make_root "$r"
run_init "$r" 2 1
expect_out "$r" "verdict" 'USB: NO-UDC'
expect_out "$r" "step" 'FAILED no UDC after 1s'
expect_file <(band_pixel "$r") "red band" 0000ff00

echo "bind fails, including the serial-only retry"
r=$WORK/retry
make_root "$r"
add_udc "$r" configured
g=$r/sys/kernel/config/usb_gadget/j85
mkdir -p "$g"
mkdir "$g/UDC"
run_init "$r"
expect_out "$r" "first bind failure" 'FAILED UDC bind \(acm\+ncm\)'
expect_out "$r" "reports failure" 'USB: BIND-FAILED'
[[ ! -e "$g/configs/c.1/ncm.usb0" ]] && echo "  ok: ncm removed for retry" || { echo "  FAIL: ncm still linked"; failures=$((failures + 1)); }

echo "button events"
r=$WORK/keys
make_root "$r"
add_udc "$r" configured
python3 -c '
import struct, sys
ev = lambda t, c, v: struct.pack("<qqHHi", 0, 0, t, c, v)
sys.stdout.buffer.write(ev(1, 172, 1) + ev(0, 0, 0) + ev(1, 172, 0) + ev(1, 115, 1))
' > "$r/dev/input/event0"
run_init "$r"
expect_out "$r" "counts key events and skips sync" 'count/name/value = 3 VOL\+ 1'

echo
if [[ $failures -eq 0 ]]; then
  echo "All init tests passed."
else
  echo "$failures init test(s) failed."
  exit 1
fi
