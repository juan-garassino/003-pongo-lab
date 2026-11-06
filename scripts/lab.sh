#!/usr/bin/env bash
# Dispatcher for the normal J85 lab workflow.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: scripts/lab.sh COMMAND [ARGS]

Local, no USB:
  build [--skip-tests]   Build kernel, m1n1, initramfs, payload; run tests
  test                   Run all local no-hardware tests
  doctor                 Show host/device USB state

Running Linux:
  shell 'command'        Run one safe command over USB serial
  report                 Write a read-only live report under notes/
  touch-report           Write a read-only touch-controller report under notes/

iPadOS research:
  ios-telemetry          Collect filtered read-only touch/battery telemetry

Hardware boot, explicit approval only:
  boot --approve         Guided manual DFU → Pongo → RAM-only Linux
  pongo                  Invoke the Pongo boot wrapper directly
  linux --approve        Invoke the Linux payload wrapper directly

Host services:
  host-prepare           Stop fwupd and install scoped USB rules
  host-restore           Restore normal firmware-update services
EOF
}

[[ $# -ge 1 ]] || { usage >&2; exit 2; }
command=$1
shift

case $command in
  build) exec "$ROOT/scripts/build-j85-lab.sh" "$@" ;;
  test)
    bash -n "$ROOT"/scripts/*.sh
    python3 -m py_compile "$ROOT"/scripts/*.py
    bash "$ROOT/initramfs/test_init.sh"
    bash "$ROOT/scripts/test_j85_sh.sh"
    bash "$ROOT/scripts/test-movie-lane.sh"
    bash "$ROOT/scripts/test-native-ipad.sh"
    bash "$ROOT/scripts/test-linux-apps.sh"
    ;;
  doctor) exec "$ROOT/scripts/pongo-doctor.sh" ;;
  shell) exec "$ROOT/scripts/j85-sh.py" "$@" ;;
  report) exec "$ROOT/scripts/j85-report.sh" ;;
  touch-report) exec "$ROOT/scripts/j85-touch-report.sh" ;;
  ios-telemetry) exec "$ROOT/scripts/collect-j85-ios-telemetry.sh" ;;
  boot) exec "$ROOT/scripts/boot-j85-lab.sh" "$@" ;;
  pongo) exec sudo "$ROOT/scripts/palera1n-a7-hoolock-pongo.sh" "$@" ;;
  linux) exec "$ROOT/scripts/boot-m1n1-j85.sh" "$@" ;;
  host-prepare) exec sudo "$ROOT/scripts/prepare-pongo-host.sh" ;;
  host-restore) exec sudo "$ROOT/scripts/restore-pongo-host.sh" ;;
  -h|--help|help) usage ;;
  *) usage >&2; exit 2 ;;
esac
