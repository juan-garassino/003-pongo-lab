#!/usr/bin/env bash
# Build PongoOS + our hello-juan module. No sudo. Run from project root.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -f src/pongoOS/newlib/Makefile ]]; then
  echo "Missing Newlib source: src/pongoOS/newlib is empty or incomplete." >&2
  echo "Fetch the checkra1n/newlib dependency before building (see README.md)." >&2
  exit 1
fi

for b in clang ld64 cctools-strip llvm-ar llvm-ranlib make xxd; do
  command -v "$b" >/dev/null || { echo "Missing $b. Use: bash scripts/build-container.sh" >&2; exit 1; }
done

echo "==> building PongoOS core"
make -j "${JOBS:-4}" -C src/pongoOS PONGO_VERSION=2.5.1-4c9b7541 all

echo "==> building hello-juan module"
make -C modules/hello-juan all

echo
echo "Artifacts:"
ls -lh src/pongoOS/build/Pongo.bin src/pongoOS/build/PongoConsolidated.bin modules/hello-juan/build/hello-juan
echo
echo "Build complete. Device loading is a separate step; see README.md."
