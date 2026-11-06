#!/usr/bin/env bash
# Test scripts/j85-sh.py against a BusyBox shell on a linked pty pair, which
# behaves like ttyACM0 and ttyGS0 with device-side echo on. Never opens USB.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$ROOT/scripts/j85-sh.py"
WORK=$(mktemp -d)
failures=0

cleanup() {
  [[ -n "${SHELL_PID:-}" ]] && kill "$SHELL_PID" 2>/dev/null || true
  [[ -n "${SOCAT_PID:-}" ]] && kill "$SOCAT_PID" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

socat "pty,raw,echo=0,link=$WORK/host" "pty,echo=1,icanon=1,link=$WORK/device" &
SOCAT_PID=$!
for _ in $(seq 1 50); do
  [[ -e "$WORK/host" && -e "$WORK/device" ]] && break
  sleep 0.1
done

# Same gate as shell_loop in initramfs/init: wait for a line from the host first.
DEVICE="$WORK/device" setsid busybox sh -c '
  read -r _ < "$DEVICE"
  PS1="j85# " exec busybox sh -i < "$DEVICE" > "$DEVICE" 2>&1
' &
SHELL_PID=$!

check() {
  local name=$1 expected_status=$2 expected_output=$3 status=0 output
  shift 3
  output=$(python3 "$TOOL" --port "$WORK/host" --timeout 10 "$@" 2>/dev/null) || status=$?
  if [[ "$status" == "$expected_status" && "$output" == "$expected_output" ]]; then
    echo "  ok: $name"
  else
    echo "  FAIL: $name (status $status, output '$output')"
    failures=$((failures + 1))
  fi
}

check "first command after the gate" 0 "hello" 'echo hello'
check "multi-line output" 0 $'one\ntwo' 'printf "one\ntwo\n"'
check "exit status" 7 "" 'exit 7'
check "stderr is captured" 0 "oops" 'echo oops >&2'
check "output with no trailing newline" 0 "abc" 'printf abc'
check "shell survives subshell exit" 0 "still here" 'echo still here'
check "refuses hwclock" 2 "" 'hwclock -w'
check "refuses NTP" 2 "" 'ntpd -q'
check "refuses reboot" 2 "" 'reboot -f'
check "refuses watchdog" 2 "" 'cat /dev/watchdog'
check "refuses nvmem" 2 "" 'cat /sys/bus/nvmem/devices/x/nvmem'

if [[ $failures -eq 0 ]]; then
  echo "All j85-sh tests passed."
else
  echo "$failures j85-sh test(s) failed."
  exit 1
fi
