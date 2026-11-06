#!/usr/bin/env bash
# Prepare this host for one Pongo session. Run explicitly with sudo.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ $EUID -eq 0 ]] || { echo "Run with sudo: sudo $0" >&2; exit 1; }

install -m 0644 "$ROOT/scripts/modprobe-blacklist-apple-mfi-fastcharge.conf" \
  /etc/modprobe.d/blacklist-apple-mfi-fastcharge.conf
if lsmod | grep -q '^apple_mfi_fastcharge '; then
  modprobe -r apple_mfi_fastcharge
fi

systemctl stop fwupd.service fwupd-refresh.service fwupd-refresh.timer 2>/dev/null || true
"$ROOT/scripts/install-pongo-udev-rule.sh"
udevadm settle
"$ROOT/scripts/pongo-doctor.sh"

cat <<'EOF'
Host prepared. Restore normal firmware-update services later with:
  sudo scripts/restore-pongo-host.sh
EOF
