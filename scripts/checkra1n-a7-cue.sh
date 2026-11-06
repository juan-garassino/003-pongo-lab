#!/usr/bin/env bash
# Boot the known-good official A7 Pongo chain. The user must put the iPad in DFU.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKRA1N="${CHECKRA1N_BIN:-$ROOT/build/checkra1n-official/checkra1n-0.1337.2-linux-x86_64}"
CHECKRA1N_SHA256=04c481ce54b9e6b507f5e33dd1574874e0149261485bf507fa47f9bebcc2ae39
LOGDIR="$ROOT/build/logs"
LOG="$LOGDIR/$(date -u +%Y%m%dT%H%M%SZ)-checkra1n-a7.log"
LATEST="$ROOT/build/checkra1n-a7.log"

[[ $EUID -eq 0 ]] || {
  echo "Run with sudo after placing the iPad in clean DFU: sudo $0" >&2
  exit 1
}
[[ -x "$CHECKRA1N" ]] || { echo "Missing checkra1n: $CHECKRA1N" >&2; exit 1; }

actual_sha=$(sha256sum "$CHECKRA1N" | awk '{print $1}')
[[ "$actual_sha" == "$CHECKRA1N_SHA256" ]] || {
  echo "checkra1n hash mismatch" >&2
  echo "expected: $CHECKRA1N_SHA256" >&2
  echo "actual:   $actual_sha" >&2
  exit 1
}

if lsmod | grep -q '^apple_mfi_fastcharge '; then
  echo "apple_mfi_fastcharge is loaded; run sudo scripts/prepare-pongo-host.sh" >&2
  exit 1
fi
if pgrep -x fwupd >/dev/null; then
  echo "fwupd is running; run sudo scripts/prepare-pongo-host.sh" >&2
  exit 1
fi

doctor=$("$ROOT/scripts/pongo-doctor.sh")
if grep -q '^RESULT=ready-for-pongo-development$' <<<"$doctor"; then
  printf '%s\n' "$doctor"
  echo "Pongo is already running; no checkra1n attempt was made."
  exit 0
fi
grep -q '^RESULT=ready-for-checkra1n$' <<<"$doctor" || {
  printf '%s\n' "$doctor" >&2
  echo "Put exactly one clean A7 iPad mini 2 in DFU mode, then rerun." >&2
  exit 1
}

state=$("$ROOT/scripts/pongo-usb-state.sh")
topology=$(sed -n 's/^TOPOLOGY\[0\]=//p' <<<"$state")
[[ "$topology" != *.* ]] || {
  echo "The iPad is behind a hub or dock ($topology). Connect it directly." >&2
  exit 1
}

mkdir -p "$LOGDIR"
rm -f "$LATEST"

tail -n +1 -F "$LOG" 2>/dev/null | while IFS= read -r line; do
  printf '%s\n' "$line"
  case "$line" in
    *"Setting up the exploit"*)
      printf '\a\033[1;33m=== DO NOT TOUCH CABLE: exploit setup ===\033[0m\n\n'
      ;;
    *"trigger stage"*)
      printf '\a\033[1;32m=== DO NOT TOUCH CABLE: trigger stage ===\033[0m\n\n'
      ;;
    *"Checkmate!"*)
      printf '\a\033[1;35m=== CHECKMATE: DO NOT TOUCH CABLE =========\033[0m\n\n'
      ;;
    *"download mode"*)
      printf '\a\033[1;32m=== DOWNLOAD MODE: DO NOT TOUCH CABLE =====\033[0m\n\n'
      ;;
    *"Booting PongoOS"*)
      printf '\a\033[1;32m=== PONGO PHASE: DO NOT TOUCH CABLE =======\033[0m\n\n'
      ;;
    *"DFU mode device disconnected"*)
      printf '\033[2m=== USB disconnect observed; do not act ===\033[0m\n\n'
      ;;
  esac
done &
CUE_PID=$!

cleanup() {
  kill "$CUE_PID" 2>/dev/null || true
  wait "$CUE_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

printf 'checkra1n log: %s\n\n' "$LOG"
set +e
timeout --preserve-status 120 "$CHECKRA1N" -E -p -n -l "$LOG"
status=$?
set -e
ln -sf "$(basename "$LOG")" "$LATEST"

for _ in $(seq 1 60); do
  if state=$("$ROOT/scripts/pongo-usb-state.sh") &&
     grep -q '^STATE=Pongo$' <<<"$state" &&
     grep -q '^SERIAL\[0\]=.*PongoOS-2\.6\.2-3c6a76da' <<<"$state"; then
    echo
    printf '%s\n' "$state"
    echo "Pongo reached; log: $LOG"
    exit 0
  fi
  sleep 0.5
done

echo "Pongo did not appear within 30 seconds after checkra1n exit." >&2
echo "Log: $LOG" >&2
exit "${status:-1}"
