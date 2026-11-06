#!/usr/bin/env bash
# Build the LZ4-wrapped Pongo image required by the A7 512 KiB DFU limit.
set -euo pipefail
cd "$(dirname "$0")/.."

openra1n="${OPENRA1N_DIR:-/tmp/openra1n}"
pongo="src/pongoOS/build/Pongo.bin"
shellcode="$openra1n/payloads/shellcode.bin"
output="build/Pongo.a7.dfu.bin"
trampoline_source="scripts/pongo_a7_trampoline.S"
trampoline="build/Pongo.a7.trampoline.bin"
lz4_trampoline_source="scripts/pongo_a7_lz4_trampoline.S"
lz4_trampoline="build/Pongo.a7.lz4.trampoline.bin"
staged_wrapper="build/Pongo.a7.staged.dfu.bin"

for tool in clang llvm-objcopy; do
  command -v "$tool" >/dev/null || {
    echo "Missing $tool. Use: bash scripts/build-container.sh" >&2
    exit 1
  }
done

for path in "$openra1n/lz4/lz4.c" "$openra1n/lz4/lz4hc.c" \
            "$openra1n/include/lz4/lz4.h" "$openra1n/include/lz4/lz4hc.h" \
            "$shellcode" "$pongo" "$trampoline_source" "$lz4_trampoline_source"; do
  if [[ ! -f "$path" ]]; then
    echo "Missing required file: $path" >&2
    echo "Clone mineek/openra1n or set OPENRA1N_DIR." >&2
    exit 1
  fi
done

mkdir -p build
clang --target=aarch64-none-elf -c "$trampoline_source" \
  -o build/Pongo.a7.trampoline.o
llvm-objcopy -O binary build/Pongo.a7.trampoline.o "$trampoline"
trampoline_sz="$(stat -c '%s' "$trampoline")"
if (( trampoline_sz > 256 )); then
  echo "A7 trampoline is $trampoline_sz bytes; expected at most 256." >&2
  exit 1
fi

clang --target=aarch64-none-elf -c "$lz4_trampoline_source" \
  -o build/Pongo.a7.lz4.trampoline.o
llvm-objcopy -O binary build/Pongo.a7.lz4.trampoline.o "$lz4_trampoline"
lz4_trampoline_sz="$(stat -c '%s' "$lz4_trampoline")"
if (( lz4_trampoline_sz > 512 )); then
  echo "A7 LZ4 trampoline is $lz4_trampoline_sz bytes; expected at most 512." >&2
  exit 1
fi

cc -O2 -Wall -Wextra -Werror \
  -I"$openra1n/include" scripts/compress_pongo.c \
  "$openra1n/lz4/lz4.c" "$openra1n/lz4/lz4hc.c" \
  -o build/compress_pongo
build/compress_pongo "$pongo" "$shellcode" "$output"
scripts/prepare_staged_pongo_wrapper.py "$output" "$staged_wrapper"
sha256sum "$output"
sha256sum "$staged_wrapper"
sha256sum "$trampoline"
sha256sum "$lz4_trampoline"
chmod +x scripts/upload_dfu_a7.py
chmod +x scripts/boot_pongo_a7.py
