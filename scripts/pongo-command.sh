#!/usr/bin/env bash
# Send one explicit command to a connected PongoOS device and read stdout.
# This wrapper does not enter DFU, reset USB, load a module, or touch storage.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON="$ROOT/.venv/bin/python"
TRANSACT="$ROOT/scripts/pongo_transact.py"

[[ $# -eq 1 ]] || {
  cat >&2 <<'EOF'
Usage: scripts/pongo-command.sh 'command'

Example:
  scripts/pongo-command.sh 'juan help'
EOF
  exit 2
}

command_arg=$1
case "$command_arg" in
  *bootx*|*bootm*|*bootr*|*modload*|*restore*|*rootfs*|*reboot*|*shutdown*|*fuse*|*sepfuse*)
    echo "Refusing potentially device-state-changing command: $command_arg" >&2
    exit 2
    ;;
esac

[[ -x "$PYTHON" ]] || { echo "Missing Python environment: $PYTHON" >&2; exit 1; }
state=$("$ROOT/scripts/pongo-usb-state.sh")
grep -q '^STATE=Pongo$' <<<"$state" || {
  echo "No PongoOS USB device found (expected 05ac:4141)." >&2
  exit 1
}
grep -q '^COUNT=1$' <<<"$state" || {
  echo "Multiple Apple USB devices are connected." >&2
  exit 1
}
grep -qE '^SERIAL\[0\]=.*PongoOS-(2\.6\.2-3c6a76da|2\.6\.3-bb492b00)' <<<"$state" || {
  echo "Unexpected Pongo build or serial." >&2
  exit 1
}

"$PYTHON" "$TRANSACT" "$command_arg"
