#!/usr/bin/env bash
# Fetch the exact PongoOS/Newlib source used by the successful hardware MVP.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${PONGO_SOURCE_DIR:-$ROOT/build/sources/PongoOS-3c6a76da}"
PONGO_COMMIT=3c6a76da3acd45eaa0345849f2543c087b35b9fc
NEWLIB_COMMIT=f9ea5054de8fb51dff6f6d3c2e7cdd4aa89744b8

if [[ ! -d "$DEST/.git" ]]; then
  mkdir -p "$(dirname "$DEST")"
  git clone https://github.com/checkra1n/PongoOS.git "$DEST"
fi

git -C "$DEST" fetch origin "$PONGO_COMMIT"
git -C "$DEST" checkout --detach "$PONGO_COMMIT"
git -C "$DEST" submodule update --init --checkout --recursive

actual_pongo=$(git -C "$DEST" rev-parse HEAD)
actual_newlib=$(git -C "$DEST/newlib" rev-parse HEAD)
[[ "$actual_pongo" == "$PONGO_COMMIT" ]] || {
  echo "Pongo commit mismatch: $actual_pongo" >&2
  exit 1
}
[[ "$actual_newlib" == "$NEWLIB_COMMIT" ]] || {
  echo "Newlib commit mismatch: $actual_newlib" >&2
  exit 1
}

echo "Pongo source: $DEST"
echo "Pongo commit: $actual_pongo"
echo "Newlib commit: $actual_newlib"
