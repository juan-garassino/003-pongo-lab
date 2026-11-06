#!/usr/bin/env bash
# Build pinned Hoolock m1n1 with chainloading support. No USB device is opened.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCES="${LINUX_RESEARCH_SOURCE_DIR:-$ROOT/build/sources}"
M1N1="$SOURCES/m1n1-idevice"
EXPECTED=d5a10ac52a6468484854419a6c5130f1d62073eb
JOBS=${JOBS:-8}

"$ROOT/scripts/fetch-linux-research-sources.sh"
"$ROOT/scripts/vendor-m1n1-rust.sh"
[[ "$(git -C "$M1N1" rev-parse HEAD)" == "$EXPECTED" ]] || {
  echo "m1n1 commit mismatch" >&2
  exit 1
}

patch="$ROOT/patches/m1n1-j85-multitouch-cal.patch"
if git -C "$M1N1" apply --reverse --check "$patch" >/dev/null 2>&1; then
  :
elif git -C "$M1N1" apply --check "$patch" >/dev/null 2>&1; then
  git -C "$M1N1" apply "$patch"
else
  echo "Could not apply J85 multitouch calibration patch cleanly." >&2
  exit 1
fi

"$ROOT/scripts/build-linux-research-toolchain.sh"

docker run --rm --platform linux/amd64 \
  --user "$(id -u):$(id -g)" \
  --network none \
  --mount "type=bind,source=$M1N1,target=/work" \
  pongo-lab-linux-research:trixie \
  bash -c 'mkdir -p .cargo && cp rust/.cargo/config.toml .cargo/config.toml && ln -sfn rust/vendor vendor && make -j '"$JOBS"' ARCH=aarch64-linux-gnu- CHAINLOADING=1'

[[ -s "$M1N1/build/m1n1.bin" ]] || {
  echo "m1n1 build did not produce build/m1n1.bin" >&2
  exit 1
}
sha256sum "$M1N1/build/m1n1.bin"
ls -lh "$M1N1/build/m1n1.bin"
