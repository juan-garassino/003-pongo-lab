#!/usr/bin/env bash
# Write a read-only report from a running J85 RAM-only Linux session.
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
  output=$("$ROOT/scripts/j85-sh.py" "$command") || true
  printf '## %s\n\n```text\n%s\n```\n\n' "$title" "$output" >>"$work/report.md"
}

{
  echo "# J85 RAM-only Linux live report"
  echo
  echo "Collected: $stamp"
} >"$work/report.md"

run_section "Identity" "uname -a"
run_section "Build ID" "grep '^BUILD_ID=' /init"
run_section "Command line" "cat /proc/cmdline"
run_section "Uptime" "cat /proc/uptime"
run_section "Memory" "grep -E '^(MemTotal|MemFree):' /proc/meminfo"
run_section "CPU" "grep -E '^(processor|CPU part|CPU revision):' /proc/cpuinfo"
run_section "Framebuffer" "printf 'size='; cat /sys/class/graphics/fb0/virtual_size; printf ' stride='; cat /sys/class/graphics/fb0/stride; printf ' format='; cat /proc/device-tree/chosen/framebuffer*/format | tr '\\000' ' '"
run_section "Input devices" "cat /proc/bus/input/devices"
run_section "USB bring-up trace" "cat /tmp/steps"
run_section "USB diagnostics" "cat /tmp/diag"
run_section "USB kernel log" "cat /tmp/usblog"
run_section "Network" "ip addr show usb0; ip route"
run_section "UDCs" "ls /sys/class/udc"
run_section "Device-tree identity" "cat /proc/device-tree/model /proc/device-tree/compatible | tr '\\000' ' '"
run_section "Platform devices" "ls /sys/bus/platform/devices"
run_section "Partitions" "cat /proc/partitions"
run_section "Mounts" "cat /proc/mounts"
run_section "Recent kernel log" "dmesg | tail -n 160"

destination="$ROOT/notes/$(date -u +%Y-%m-%d)-j85-linux-live-report.md"
if [[ -e "$destination" ]]; then
  destination="$ROOT/notes/$(date -u +%Y-%m-%d)-j85-linux-live-report-$stamp.md"
fi
mv "$work/report.md" "$destination"
echo "Live report: $destination"
echo "All queries were read-only."
