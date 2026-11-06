#!/usr/bin/env bash
# Boot Hoolock's prebuilt Pongo (has bootm) through palera1n, as Hoolock documents
# for A7 on Linux. The user must put the iPad in DFU. Stops at the Pongo shell.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PALERA1N="$ROOT/build/palera1n/palera1n-v2.1-beta.2"
PALERA1N_SHA256=d0ba1cc315523703a7f61e6ba6687ee166e7ac319d36f71b1e79f273180d0738
PONGO="$ROOT/build/sources/hoolock-docs/binaries/Pongo.bin"
PONGO_SHA256=1e5543fd8e6dbd84c334b87d71aa473f4d347c2ba8a5e863b6e10f18461c7575
PONGO_SERIAL='PongoOS-2\.6\.3-bb492b00'
LOGDIR="$ROOT/build/logs"
LOG="$LOGDIR/$(date -u +%Y%m%dT%H%M%SZ)-palera1n-a7.log"

[[ $EUID -eq 0 ]] || {
  echo "Run with sudo after placing the iPad in clean DFU: sudo $0" >&2
  exit 1
}

check_hash() {
  local path=$1 expected=$2 actual
  [[ -f "$path" ]] || { echo "Missing: $path" >&2; exit 1; }
  actual=$(sha256sum "$path" | awk '{print $1}')
  [[ "$actual" == "$expected" ]] || {
    echo "Hash mismatch: $path" >&2
    echo "expected: $expected" >&2
    echo "actual:   $actual" >&2
    exit 1
  }
}
check_hash "$PALERA1N" "$PALERA1N_SHA256"
check_hash "$PONGO" "$PONGO_SHA256"

if lsmod | grep -q '^apple_mfi_fastcharge '; then
  echo "apple_mfi_fastcharge is loaded; run sudo scripts/prepare-pongo-host.sh" >&2
  exit 1
fi
if pgrep -x fwupd >/dev/null; then
  echo "fwupd is running; run sudo scripts/prepare-pongo-host.sh" >&2
  exit 1
fi

doctor=$("$ROOT/scripts/pongo-doctor.sh") || true
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
printf 'palera1n log: %s\nDo not touch the cable until this script exits.\n\n' "$LOG"

# Hoolock warns palera1n can sit at "Booting pongoOS..." after Pongo is up, so
# success is judged from USB and palera1n is then stopped.
PALERA1N_BYPASS_PASSCODE_CHECK=1 timeout 180 "$PALERA1N" -l -p -k "$PONGO" 2>&1 \
  | tee "$LOG" &
PIPE_PID=$!

for _ in $(seq 1 360); do
  if state=$("$ROOT/scripts/pongo-usb-state.sh") &&
     grep -q '^STATE=Pongo$' <<<"$state" &&
     grep -q "^SERIAL\[0\]=.*$PONGO_SERIAL" <<<"$state"; then
    pkill -f "$PALERA1N" 2>/dev/null || true
    wait "$PIPE_PID" 2>/dev/null || true
    echo
    printf '%s\n' "$state"
    echo "Hoolock Pongo reached; log: $LOG"
    exit 0
  fi
  if ! kill -0 "$PIPE_PID" 2>/dev/null && [[ -z "${exited:-}" ]]; then
    exited=$SECONDS
  fi
  if [[ -n "${exited:-}" ]] && (( SECONDS - exited > 30 )); then
    break
  fi
  sleep 0.5
done

pkill -f "$PALERA1N" 2>/dev/null || true
wait "$PIPE_PID" 2>/dev/null || true
"$ROOT/scripts/pongo-usb-state.sh" >&2 || true
echo "Hoolock Pongo did not appear. Log: $LOG" >&2
exit 1
