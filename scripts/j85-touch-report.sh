#!/usr/bin/env bash
# Collect read-only J85 touch-controller diagnostics from running RAM Linux.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
state=$("$ROOT/scripts/pongo-usb-state.sh")
grep -q '^STATE=Linux$' <<<"$state" || {
  printf '%s\n' "$state" >&2
  echo "The J85 Linux USB gadget is not connected." >&2
  exit 1
}

stamp=$(date -u +%Y-%m-%dT%H%M%SZ)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

run_section() {
  local title=$1 command=$2 output
  output=$("$ROOT/scripts/j85-sh.py" --timeout 15 "$command") || true
  printf '## %s\n\n```text\n%s\n```\n\n' "$title" "$output" >>"$work/report.md"
}

{
  echo "# J85 touch-controller diagnostic"
  echo
  echo "Collected: $stamp"
  echo
  echo "All queries were read-only. No input-event test writes device state."
} >"$work/report.md"

run_section "Identity and uptime" "uname -a; cat /proc/uptime"
run_section "Input devices" "cat /proc/bus/input/devices"
run_section "Interrupts" "cat /proc/interrupts"
run_section "Apple Z2 / SPI kernel log" \
  "dmesg | grep -Ei 'apple-z2|Gen-1 bring-up|touch|spi@20a084000|gpio-71'"
run_section "Touch device-tree properties" \
  "for p in compatible firmware-name reset-gpios interrupts-extended apple,z2-cal-blob; do printf '%s: ' \"\${p}\"; wc -c < /proc/device-tree/soc/spi@20a084000/touchscreen@0/\${p}; done"
run_section "Touch calibration first 32 bytes" \
  "dd if=/proc/device-tree/soc/spi@20a084000/touchscreen@0/apple/z2-cal-blob bs=32 count=1 2>/dev/null | hexdump -C"
run_section "SPI device links" "ls -l /sys/bus/spi/devices /sys/bus/spi/drivers"
run_section "SPI controller IRQ counters" \
  "grep -Ei '20a084000|spi|pinctrl' /proc/interrupts || true"
run_section "GPIO 71 state" \
  "find /sys/class/gpio -maxdepth 1 -iname 'gpio71' -exec sh -c 'echo {}; cat {}/direction; cat {}/value' \\;"
run_section "Bounded evdev read (5 seconds)" \
  "timeout 5 dd if=/dev/input/event0 bs=24 count=1 2>/dev/null | hexdump -C"

destination="$ROOT/notes/$(date -u +%Y-%m-%d)-j85-touch-diagnostic.md"
if [[ -e "$destination" ]]; then
  destination="$ROOT/notes/$(date -u +%Y-%m-%d)-j85-touch-diagnostic-$stamp.md"
fi
mv "$work/report.md" "$destination"
echo "Touch diagnostic: $destination"
echo "All queries were read-only."
