#!/usr/bin/env bash
# Send the packaged RAM-only m1n1 + Linux payload to Hoolock Pongo and run bootm.
# Nothing is written to storage by this script or by the packaged initramfs.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON="$ROOT/.venv/bin/python"
PAYLOAD="$ROOT/build/m1n1-j85-ram-only.bin"
MANIFEST="$ROOT/build/linux-j85/manifest.sha256"

[[ "${1:-}" == --approve && $# -eq 1 ]] || {
  echo "Refusing to send payload without --approve." >&2
  exit 2
}
[[ -x "$PYTHON" ]] || { echo "Missing Python environment: $PYTHON" >&2; exit 1; }
[[ -s "$MANIFEST" && -s "$PAYLOAD" ]] || {
  echo "Missing payload; run scripts/package-m1n1-j85-ram.sh" >&2
  exit 1
}
sha256sum --check --quiet "$MANIFEST"

state=$("$ROOT/scripts/pongo-usb-state.sh")
grep -q '^STATE=Pongo$' <<<"$state" && grep -q '^COUNT=1$' <<<"$state" || {
  printf '%s\n' "$state" >&2
  echo "Expected exactly one PongoOS device." >&2
  exit 1
}
grep -q '^SERIAL\[0\]=.*CPID:8960.*BDID:0A.*PongoOS-2\.6\.3-bb492b00' <<<"$state" || {
  printf '%s\n' "$state" >&2
  echo "Expected Hoolock Pongo 2.6.3-bb492b00 on J85 (only that build has bootm)." >&2
  exit 1
}

"$PYTHON" "$ROOT/scripts/pongo_boot_m1n1.py" "$PAYLOAD"
