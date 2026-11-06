#!/usr/bin/env bash
# Build the next read-only hello-juan module against the exact running Pongo.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${PONGO_SOURCE_DIR:-$ROOT/build/sources/PongoOS-3c6a76da}"
OUTPUT="$ROOT/build/hello-juan-summary.2.6.2-3c6a76da"

"$ROOT/scripts/fetch-pongo-3c6a76da.sh"
[[ "$(id -u)" -ne 0 ]] || {
  echo "Run as the normal user; Docker handles the isolated build." >&2
  exit 1
}

docker run --rm --platform linux/amd64 \
  --user "$(id -u):$(id -g)" \
  --network none \
  --mount "type=bind,source=$ROOT,target=/work" \
  --mount "type=bind,source=$SOURCE,target=/pongo" \
  pongo-lab-toolchain:bullseye \
  bash -c 'set -euo pipefail; make -C /pongo/newlib all && make -C modules/hello-juan clean all PONGO=/pongo && cp modules/hello-juan/build/hello-juan /work/build/hello-juan-summary.2.6.2-3c6a76da'

sha256sum "$OUTPUT"
ls -lh "$OUTPUT"
file "$OUTPUT"
