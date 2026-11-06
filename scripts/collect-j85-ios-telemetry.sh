#!/usr/bin/env bash
# Collect narrowly filtered, read-only iPadOS telemetry for touch research.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
state=$("$ROOT/scripts/pongo-usb-state.sh")
grep -q '^STATE=iPadOS$' <<<"$state" || {
  printf '%s\n' "$state" >&2
  echo "The iPad must be in normal iPadOS for this collection." >&2
  exit 1
}

stamp=$(date -u +%Y-%m-%dT%H%M%SZ)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

ideviceinfo -q com.apple.mobile.battery >"$work/battery.txt"
idevicediagnostics ioreg IODeviceTree >"$work/device-tree.txt"
idevicediagnostics ioreg IOService >"$work/io-service.txt"

{
  echo "# J85 iPadOS touch telemetry"
  echo
  echo "Collected: $stamp"
  echo
  echo "## Device identity"
  echo
  echo '```text'
  ideviceinfo -s ProductType
  ideviceinfo -s HardwareModel
  ideviceinfo -s ProductVersion
  echo '```'
  echo
  echo "## Battery"
  echo
  echo '```text'
  cat "$work/battery.txt"
  echo '```'
  echo
  echo "## Filtered touch-related IORegistry context"
  echo
  echo "Only touch, multitouch, Z2, SPI, and BCM597 context is retained; full registry dumps are discarded because they may contain unrelated identifiers."
  echo
  echo '```text'
  grep -iE -B8 -A30 \
    'touch|multitouch|apple.*z2|z2.*apple|bcm597|\bspi\b|dfrmtfw' \
    "$work/device-tree.txt" "$work/io-service.txt" || true
  echo '```'
} >"$work/report.md"

destination="$ROOT/notes/$(date -u +%Y-%m-%d)-j85-ipados-touch-telemetry.md"
if [[ -e "$destination" ]]; then
  destination="$ROOT/notes/$(date -u +%Y-%m-%d)-j85-ipados-touch-telemetry-$stamp.md"
fi
mv "$work/report.md" "$destination"
echo "Telemetry note: $destination"
echo "No device state was changed."
