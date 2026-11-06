#!/usr/bin/env bash
# Read-only host/device preflight for Pongo development.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE=$("$ROOT/scripts/pongo-usb-state.sh")

echo "== Apple USB =="
printf '%s\n' "$STATE"

echo
echo "== Host services =="
if pgrep -x fwupd >/dev/null; then
  echo "fwupd=running"
else
  echo "fwupd=stopped"
fi
if lsmod | grep -q '^apple_mfi_fastcharge '; then
  echo "apple_mfi_fastcharge=loaded"
else
  echo "apple_mfi_fastcharge=not-loaded"
fi

if [[ -f /etc/udev/rules.d/74-pongo-lab.rules ]]; then
  echo "pongo-udev-rule=installed"
else
  echo "pongo-udev-rule=missing"
fi
if [[ -f /etc/modprobe.d/blacklist-apple-mfi-fastcharge.conf ]]; then
  echo "fastcharge-blacklist=installed"
else
  echo "fastcharge-blacklist=missing"
fi

echo
echo "== Pongo/checkra1n processes =="
found=0
while IFS= read -r line; do
  printf '%s\n' "$line"
  found=1
done < <(ps -eo pid,ppid,user,stat,lstart,args | grep -E '[c]heckra1n|[p]alera1n')
[[ $found -eq 0 ]] && echo "none"

echo
if grep -q '^STATE=Pongo$' <<<"$STATE"; then
  if grep -qE 'SERIAL\[0\]=.*PongoOS-(2\.6\.2-3c6a76da|2\.6\.3-bb492b00)' <<<"$STATE"; then
    echo "RESULT=ready-for-pongo-development"
  else
    echo "RESULT=unexpected-pongo-build"
    exit 1
  fi
elif grep -q '^STATE=Linux$' <<<"$STATE"; then
  echo "RESULT=linux-running"
elif grep -q '^STATE=DFU$' <<<"$STATE"; then
  if grep -q 'SERIAL\[0\]=.*CPID:8960.*SRTG:\[iBoot-1704\.10\]' <<<"$STATE" &&
     ! grep -q 'SERIAL\[0\]=.*\(YOLO\|PWND\)' <<<"$STATE"; then
    echo "RESULT=ready-for-checkra1n"
  else
    echo "RESULT=wrong-or-dirty-dfu-state"
    exit 1
  fi
else
  echo "RESULT=not-ready"
fi
