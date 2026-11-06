#!/usr/bin/env bash
# Extract the J85 Apple DeviceTree and BCM5976 multitouch firmware locally.
# Downloads only the pinned IPSW when needed and never opens a USB device.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IPSW="${J85_IPSW:-$ROOT/build/ipsw/iPad_64bit_12.5.8_16H88_Restore.ipsw}"
IPSW_URL='https://updates.cdn-apple.com/2026WinterFCS/fullrestores/047-28446/9ED122D9-755C-403E-B95E-7C36998B9838/iPad_64bit_12.5.8_16H88_Restore.ipsw'
IPSW_SHA256='8d0c6a232e720246d8b699bfe2240833560221e8a4bf10fcb707b73be412b5f3'
DEVICETREE_SHA256='ed71ed5fef2b6ada426ba77619085eb962d0639c0eee2a12c3940d2ffbe63c39'
FIRMWARE_SHA256='943e1b065d0b0b01adc6ead7d6fbd50ff9f2d269ef6b039789953cf48146569b'

OUT="$ROOT/build/linux-j85"
DT_OUT="$OUT/apple/DeviceTree.j85ap.im4p"
FW_OUT="$OUT/firmware/apple/j85-multitouch.bin"
WORK="$ROOT/build/ipsw/j85-extract"

mkdir -p "$(dirname "$IPSW")" "$OUT/apple" "$OUT/firmware/apple"

sha_matches() {
  local path=$1 expected=$2 actual
  [[ -s "$path" ]] || return 1
  actual=$(sha256sum "$path" | awk '{print $1}')
  [[ "$actual" == "$expected" ]]
}

if [[ -s "$IPSW" ]]; then
  actual_ipsw_sha=$(sha256sum "$IPSW" | awk '{print $1}')
else
  actual_ipsw_sha=
fi

if [[ "$actual_ipsw_sha" != "$IPSW_SHA256" ]]; then
  echo "==> Downloading pinned J85 iPadOS IPSW"
  curl -fL --retry 3 -o "$IPSW" "$IPSW_URL"
  actual_ipsw_sha=$(sha256sum "$IPSW" | awk '{print $1}')
fi

[[ "$actual_ipsw_sha" == "$IPSW_SHA256" ]] || {
  echo "IPSW hash mismatch: $IPSW" >&2
  echo "expected: $IPSW_SHA256" >&2
  echo "actual:   $actual_ipsw_sha" >&2
  exit 1
}

if ! sha_matches "$DT_OUT" "$DEVICETREE_SHA256"; then
  echo "==> Extracting Apple J85 DeviceTree"
  python3 - "$IPSW" "$DT_OUT" <<'PY'
import sys
import zipfile
from pathlib import Path

ipsw, destination = map(Path, sys.argv[1:])
member = "Firmware/all_flash/DeviceTree.j85ap.im4p"
with zipfile.ZipFile(ipsw) as archive:
    with archive.open(member) as source, destination.open("wb") as target:
        while chunk := source.read(1024 * 1024):
            target.write(chunk)
PY
fi
sha_matches "$DT_OUT" "$DEVICETREE_SHA256" || {
  echo "J85 DeviceTree hash mismatch: $DT_OUT" >&2
  exit 1
}

if sha_matches "$FW_OUT" "$FIRMWARE_SHA256"; then
  echo "J85 IPSW artifacts already present:"
  echo "  $DT_OUT"
  echo "  $FW_OUT"
  exit 0
fi

echo "==> Extracting J85 multitouch firmware through the isolated toolchain"
"$ROOT/scripts/build-linux-research-toolchain.sh"
rm -rf "$WORK"
mkdir -p "$WORK/dmg" "$WORK/rootfs" "$WORK/mtprops"

docker run --rm --platform linux/amd64 \
  --user "$(id -u):$(id -g)" \
  --network none \
  --mount "type=bind,source=$ROOT,target=/work" \
  pongo-lab-linux-research:trixie \
  bash -euo pipefail -c '
    ipsw="/work/'"${IPSW#$ROOT/}"'"
    work="/work/'"${WORK#$ROOT/}"'"
    dmg="$work/dmg/038-87004-062.dmg"
    img="$work/dmg/038-87004-062.img"
    apfs="$work/rootfs/1.disk image.apfs"

    7z x -y -o"$work/dmg" "$ipsw" "038-87004-062.dmg"
    dmg2img -i "$dmg" -o "$img"
    7z x -y -o"$work/rootfs" "$img" "1.disk image.apfs"
    7z x -y -o"$work/mtprops" "$apfs" "usr/share/firmware/multitouch/J85.mtprops*"

    rm -f "$img" "$apfs" "$dmg"
  '

resource="$WORK/mtprops/usr/share/firmware/multitouch/J85.mtprops:com.apple.ResourceFork"
[[ -s "$resource" ]] || {
  echo "Did not find J85.mtprops resource fork: $resource" >&2
  exit 1
}

python3 "$ROOT/scripts/decode-j85-mtprops.py" \
  "$resource" \
  "$FW_OUT" \
  --plist-output "$WORK/J85.mtprops"

rm -rf "$WORK"
sha_matches "$FW_OUT" "$FIRMWARE_SHA256" || {
  echo "J85 multitouch firmware hash mismatch: $FW_OUT" >&2
  exit 1
}

cat <<EOF
Extracted J85 IPSW artifacts:
  $DT_OUT
    SHA-256 $DEVICETREE_SHA256
  $FW_OUT
    SHA-256 $FIRMWARE_SHA256

No USB device was opened.
EOF
