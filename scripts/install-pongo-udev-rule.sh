#!/usr/bin/env bash
# Install the narrowly scoped PongoOS USB permission rule.
# Run explicitly with sudo; no USB command is sent to the iPad.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RULE="$ROOT/scripts/74-pongo-lab.rules"
DEST="/etc/udev/rules.d/74-pongo-lab.rules"

[[ $EUID -eq 0 ]] || {
  echo "Run with sudo: sudo $0" >&2
  exit 1
}

install -m 0644 "$RULE" "$DEST"
udevadm control --reload

# Apply the rule to Pongo devices that are already connected. This is a host
# udev rediscovery only; it does not reset, reconfigure, or command the device.
found=0
for devpath in /sys/bus/usb/devices/*; do
  [[ -f "$devpath/idVendor" && -f "$devpath/idProduct" ]] || continue
  if [[ "$(cat "$devpath/idVendor"):$(cat "$devpath/idProduct")" == "05ac:4141" ]]; then
    udevadm trigger --action=change "$devpath"
    found=1
  fi
done

if [[ $found -eq 0 ]]; then
  echo "Rule installed. No currently connected 05ac:4141 device was found."
else
  echo "Rule installed and applied to the connected PongoOS device."
fi
