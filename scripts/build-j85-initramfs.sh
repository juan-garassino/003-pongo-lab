#!/usr/bin/env bash
# Build the arm64 BusyBox initramfs for the J85 RAM-only Linux boot from
# initramfs/init, then check it before it can reach the iPad. Never opens USB.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build/linux-j85"
INIT="$ROOT/initramfs/init"
TOUCH_TEST="$ROOT/initramfs/touch-test.c"
LINUX_APPS="$ROOT/linux-apps"
TOUCH_FW="$ROOT/build/linux-j85/firmware/apple/j85-multitouch.bin"
TOUCH_FW_SHA256=943e1b065d0b0b01adc6ead7d6fbd50ff9f2d269ef6b039789953cf48146569b
IMAGE=pongo-lab-linux-research:trixie
BUILD_ID=$(git -C "$ROOT" describe --always --dirty --abbrev=8)

sh -n "$INIT"
[[ -s "$TOUCH_TEST" ]] || {
  echo "Missing fullscreen touch test source: $TOUCH_TEST" >&2
  exit 1
}
[[ -s "$LINUX_APPS/juan-core.c" && -s "$LINUX_APPS/hello-juan.c" &&
  -s "$LINUX_APPS/linux-hello-juan.c" ]] || {
  echo "Missing portable Linux application sources under: $LINUX_APPS" >&2
  exit 1
}
[[ "$(awk 'NF && $1 !~ /^#/ {print $1}' "$LINUX_APPS/apps.list" | tr '\n' ' ')" == "hello-juan " ]] || {
  echo "linux-apps/apps.list does not contain exactly hello-juan" >&2
  exit 1
}
[[ -s "$TOUCH_FW" ]] || {
  echo "Missing J85 multitouch firmware; run scripts/extract-j85-ipsw-artifacts.sh" >&2
  exit 1
}
actual_fw_sha=$(sha256sum "$TOUCH_FW" | awk '{print $1}')
[[ "$actual_fw_sha" == "$TOUCH_FW_SHA256" ]] || {
  echo "J85 multitouch firmware hash mismatch" >&2
  echo "expected: $TOUCH_FW_SHA256" >&2
  echo "actual:   $actual_fw_sha" >&2
  exit 1
}
mkdir -p "$OUT"

docker_args=(
  --rm -i --platform linux/amd64
  --user "$(id -u):$(id -g)"
  --network none
  --mount "type=bind,source=$OUT,target=/out"
)
docker_args+=(--mount "type=bind,source=$TOUCH_FW,target=/firmware/j85-multitouch.bin,readonly")
docker_args+=(--mount "type=bind,source=$ROOT/initramfs,target=/source,readonly")
docker_args+=(--mount "type=bind,source=$LINUX_APPS,target=/apps,readonly")

sed "s/@BUILD_ID@/$BUILD_ID/" "$INIT" | docker run \
  "${docker_args[@]}" "$IMAGE" \
  bash -c '
    set -euo pipefail
    rd=$(mktemp -d)
    mkdir -p "$rd"/{bin,dev,proc,sys,tmp}
    mkdir -p "$rd/lib/firmware/apple"
    cp /firmware/j85-multitouch.bin "$rd/lib/firmware/apple/j85-multitouch.bin"
    cp /usr/bin/busybox "$rd/bin/busybox"
    aarch64-linux-gnu-gcc -static -O2 -Wall -Wextra -Werror \
      /source/touch-test.c -o "$rd/bin/touch-test"
    aarch64-linux-gnu-gcc -static -O2 -Wall -Wextra -Werror \
      -I/apps/include \
      /apps/juan-core.c /apps/hello-juan.c /apps/linux-hello-juan.c \
      -o "$rd/bin/hello-juan"
    ln -s busybox "$rd/bin/sh"
    cat > "$rd/init"
    chmod 755 "$rd/init"
    find "$rd" -exec touch -h -d @0 {} +
    cd "$rd"
    find . -print0 | LC_ALL=C sort -z \
      | cpio --null --create --format=newc --owner=0:0 --reproducible --quiet \
      | gzip -9 -n > /out/initramfs.gz

    check=$(mktemp -d)
    cd "$check"
    gzip -dc /out/initramfs.gz | cpio -idm --quiet
    [[ "$(stat -c %a init)" == 755 ]] || { echo "init is not executable" >&2; exit 1; }
    sh -n init
    grep -qx "BUILD_ID='"$BUILD_ID"'" init || { echo "init has the wrong build ID" >&2; exit 1; }
    cmp /firmware/j85-multitouch.bin lib/firmware/apple/j85-multitouch.bin
    touch_headers=$(readelf -hl bin/touch-test)
    grep -q "AArch64" <<<"$touch_headers" || {
      echo "touch-test is not arm64" >&2
      exit 1
    }
    if grep -q "INTERP" <<<"$touch_headers"; then
      echo "touch-test is not static" >&2
      exit 1
    fi
    hello_headers=$(readelf -hl bin/hello-juan)
    grep -q "AArch64" <<<"$hello_headers" || {
      echo "hello-juan is not arm64" >&2
      exit 1
    }
    if grep -q "INTERP" <<<"$hello_headers"; then
      echo "hello-juan is not static" >&2
      exit 1
    fi
    headers=$(readelf -hl bin/busybox)
    grep -q "AArch64" <<<"$headers" || { echo "busybox is not arm64" >&2; exit 1; }
    if grep -q "INTERP" <<<"$headers"; then
      echo "busybox is not static" >&2
      exit 1
    fi
  '

[[ "$(xxd -p -l2 "$OUT/initramfs.gz")" == 1f8b ]] || {
  echo "initramfs has invalid gzip magic" >&2
  exit 1
}
echo "Build ID: $BUILD_ID"
sha256sum "$OUT/initramfs.gz"
ls -lh "$OUT/initramfs.gz"
