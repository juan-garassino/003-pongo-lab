#!/usr/bin/env bash
# Restore host services after a Pongo session. This does not touch the iPad.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo: sudo $0" >&2; exit 1; }

systemctl start fwupd.service fwupd-refresh.timer 2>/dev/null || true
systemctl start fwupd-refresh.service 2>/dev/null || true
echo "fwupd services restored."
