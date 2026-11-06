#!/usr/bin/env bash
# Build and locally test the complete RAM-only J85 Linux lab payload.
# This is the reproducible local-build entry point. It never opens USB.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
skip_tests=0

while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-tests) skip_tests=1 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

for tool in docker git sha256sum xxd python3; do
  command -v "$tool" >/dev/null || {
    echo "Missing required tool: $tool" >&2
    exit 1
  }
done

printf '%s\n' '==> J85 lab: preparing pinned m1n1/Linux toolchain'
"$ROOT/scripts/build-linux-research-toolchain.sh"
"$ROOT/scripts/build-m1n1-idevice.sh"

printf '%s\n' '==> J85 lab: building 4K-page kernel and J85 DTB'
"$ROOT/scripts/build-hoolock-j85-linux.sh"

printf '%s\n' '==> J85 lab: extracting pinned Apple J85 touch artifacts'
"$ROOT/scripts/extract-j85-ipsw-artifacts.sh"

printf '%s\n' '==> J85 lab: building and packaging RAM-only initramfs'
"$ROOT/scripts/build-j85-initramfs.sh"
"$ROOT/scripts/package-m1n1-j85-ram.sh"

if [[ $skip_tests -eq 0 ]]; then
  printf '%s\n' '==> J85 lab: running local no-hardware tests'
  bash -n "$ROOT"/scripts/*.sh
  python3 -m py_compile "$ROOT"/scripts/*.py
  bash "$ROOT/initramfs/test_init.sh"
  bash "$ROOT/scripts/test_j85_sh.sh"
  bash "$ROOT/scripts/test-linux-apps.sh"
fi

printf '%s\n' '==> J85 lab: verifying artifact manifest'
sha256sum --check "$ROOT/build/linux-j85/manifest.sha256"

cat <<EOF

J85 lab build complete. No USB command was sent.

Payload:  $ROOT/build/m1n1-j85-ram-only.bin
Manifest: $ROOT/build/linux-j85/manifest.sha256

Guided hardware boot:
  scripts/lab.sh boot --approve
EOF
