#!/usr/bin/env bash
# Explicitly load one pinned hello-juan module into a running Pongo session.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON="$ROOT/.venv/bin/python"
LOADER="$ROOT/src/pongoOS/scripts/module_load.py"
version=mvp

while [[ $# -gt 0 ]]; do
  case $1 in
    --approve) approved=1 ;;
    --summary) version=summary ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done
[[ "${approved:-}" == 1 ]] || {
  echo "Refusing module load without --approve." >&2
  exit 2
}

case $version in
  mvp)
    module="$ROOT/build/hello-juan.2.6.2-3c6a76da"
    expected=bb662501c5077f52e26e5b856fbfcacd08b256854a6e7ca9d01d622b9b8672e0
    ;;
  summary)
    module="$ROOT/build/hello-juan-summary.2.6.2-3c6a76da"
    expected=a1b91d1d33a8b82fba63850f50bcd824d5954ea0b7f74a4893f0b0ba8f1c54ec
    ;;
esac

[[ -f "$module" ]] || { echo "Missing module: $module" >&2; exit 1; }
actual=$(sha256sum "$module" | awk '{print $1}')
[[ "$actual" == "$expected" ]] || {
  echo "Module hash mismatch: $module" >&2
  echo "expected: $expected" >&2
  echo "actual:   $actual" >&2
  exit 1
}

state=$("$ROOT/scripts/pongo-usb-state.sh")
grep -q '^STATE=Pongo$' <<<"$state" || { echo "Pongo is not connected." >&2; exit 1; }
grep -q '^SERIAL\[0\]=.*PongoOS-2\.6\.2-3c6a76da' <<<"$state" || {
  echo "Unexpected Pongo build." >&2
  exit 1
}

if "$ROOT/scripts/pongo-command.sh" 'juan help' |
   grep -q '^juan commands:'; then
  echo "A hello-juan module is already loaded; refusing a duplicate load." >&2
  exit 1
fi

"$PYTHON" "$LOADER" "$module"
"$ROOT/scripts/pongo-command.sh" 'juan help'
