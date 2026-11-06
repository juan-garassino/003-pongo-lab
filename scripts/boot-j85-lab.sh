#!/usr/bin/env bash
# Guided hardware path: manual DFU → Hoolock Pongo → RAM-only J85 Linux.
# DFU entry remains manual by design. No restore or persistent storage operation.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

[[ "${1:-}" == "--approve" && $# -eq 1 ]] || {
  cat >&2 <<'EOF'
Usage: scripts/boot-j85-lab.sh --approve

This explicitly approves:
  1. checkm8/Pongo boot from clean DFU
  2. upload of build/m1n1-j85-ram-only.bin
  3. Pongo bootm

It does not enter DFU automatically and does not write persistent storage.
EOF
  exit 2
}

printf '%s\n' '==> Preparing host USB services'
sudo "$ROOT/scripts/prepare-pongo-host.sh"
state=$("$ROOT/scripts/pongo-usb-state.sh")

if ! grep -qE '^STATE=(DFU|Pongo|Linux)$' <<<"$state"; then
  printf '%s\n' "$state"
  cat <<'EOF'

Put the iPad into DFU manually:
  1. Hold Home + Power for about 10 seconds.
  2. Release Power while continuing Home for about 10 seconds.
  3. Keep the screen black.

Press Enter after the screen has stayed black for a few seconds...
EOF
  read -r _
  state=$("$ROOT/scripts/pongo-usb-state.sh")
fi

printf '%s\n' "$state"

if grep -q '^STATE=Linux$' <<<"$state"; then
  echo "J85 RAM-only Linux is already running."
  "$ROOT/scripts/j85-sh.py" 'uname -a'
  exit 0
fi

if grep -q '^STATE=DFU$' <<<"$state"; then
  printf '%s\n' '==> Clean DFU detected; booting Hoolock Pongo. Do not touch the cable.'
  sudo "$ROOT/scripts/palera1n-a7-hoolock-pongo.sh"
  state=$("$ROOT/scripts/pongo-usb-state.sh")
fi

grep -q '^STATE=Pongo$' <<<"$state" || {
  printf '%s\n' "$state" >&2
  echo "Expected Hoolock Pongo 2.6.3-bb492b00 before uploading Linux." >&2
  exit 1
}

printf '%s\n' '==> Uploading RAM-only Linux payload'
"$ROOT/scripts/boot-m1n1-j85.sh" --approve

printf '%s\n' '==> Waiting for the Linux USB gadget'
for _ in $(seq 1 60); do
  state=$("$ROOT/scripts/pongo-usb-state.sh") || true
  if grep -q '^STATE=Linux$' <<<"$state"; then
    printf '%s\n' "$state"
    "$ROOT/scripts/j85-sh.py" 'uname -a'
    "$ROOT/scripts/j85-sh.py" 'cat /tmp/steps'
    echo
    echo "J85 RAM-only Linux is ready: scripts/lab.sh shell 'uname -a'"
    exit 0
  fi
  sleep 1
done

"$ROOT/scripts/pongo-usb-state.sh" >&2 || true
echo "The Linux USB gadget did not appear within 60 seconds." >&2
exit 1
