#!/usr/bin/env bash
# Build the 4K-page Hoolock kernel and J85 DTB in an isolated container.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCES="${LINUX_RESEARCH_SOURCE_DIR:-$ROOT/build/sources}"
LINUX="$SOURCES/hoolock-linux"
DOCS="$SOURCES/hoolock-docs"
OUT="$ROOT/build/linux-j85"
JOBS=${JOBS:-8}

"$ROOT/scripts/fetch-linux-research-sources.sh"
"$ROOT/scripts/build-linux-research-toolchain.sh"
mkdir -p "$OUT"

patch="$ROOT/patches/hoolock-linux-j85-touch-diagnostic.patch"
if git -C "$LINUX" apply --reverse --check "$patch" >/dev/null 2>&1; then
  :
elif git -C "$LINUX" apply --check "$patch" >/dev/null 2>&1; then
  git -C "$LINUX" apply "$patch"
else
  echo "Could not apply J85 touch diagnostic patch cleanly." >&2
  exit 1
fi

docker run --rm --platform linux/amd64 \
  --user "$(id -u):$(id -g)" \
  --network none \
  --mount "type=bind,source=$LINUX,target=/linux" \
  --mount "type=bind,source=$DOCS,target=/docs,readonly" \
  --mount "type=bind,source=$OUT,target=/out" \
  pongo-lab-linux-research:trixie \
  bash -c '
    set -euo pipefail
    cd /linux
    cp /docs/config_16k .config
    scripts/config --disable ARM64_16K_PAGES
    scripts/config --enable ARM64_4K_PAGES
    # Build the Apple Z2 driver and the J85 SPI child node needed to probe it.
    scripts/config --enable INPUT_TOUCHSCREEN
    scripts/config --enable TOUCHSCREEN_APPLE_Z2
    make ARCH=arm64 LLVM=1 olddefconfig
    grep -q "^CONFIG_ARM64_4K_PAGES=y$" .config
    grep -q "^CONFIG_TOUCHSCREEN_APPLE_Z2=y$" .config
    if grep -q "^CONFIG_ARM64_16K_PAGES=y$" .config; then
      echo "16K pages are enabled; A7 needs 4K" >&2
      exit 1
    fi
    make -j '"$JOBS"' ARCH=arm64 LLVM=1 Image.gz dtbs
    cp arch/arm64/boot/Image.gz /out/Image.gz
    cp arch/arm64/boot/dts/apple/s5l8960x-j85.dtb /out/s5l8960x-j85.dtb
    cp .config /out/kernel.config

    compatible="$(fdtget /out/s5l8960x-j85.dtb \
      /soc/spi@20a084000/touchscreen@0 compatible)"
    [[ "$compatible" == "apple,j85-multitouch" ]] || {
      echo "J85 touchscreen DT node is missing or wrong: $compatible" >&2
      exit 1
    }
  '

artifacts=(Image.gz s5l8960x-j85.dtb kernel.config)
for artifact in "${artifacts[@]}"; do
  [[ -s "$OUT/$artifact" ]] || {
    echo "Missing build artifact: $OUT/$artifact" >&2
    exit 1
  }
done
sha256sum "${artifacts[@]/#/$OUT/}"
ls -lh "${artifacts[@]/#/$OUT/}"
