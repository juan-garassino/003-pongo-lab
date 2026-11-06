#!/bin/sh
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
GASTER="$ROOT/src/hoolock/gaster"
GENERATED="$ROOT/build/gaster-generated"
OUTPUT="$ROOT/build/gaster-a7-preflight"

mkdir -p "$GENERATED"
trap 'rm -rf "$GENERATED"' EXIT HUP INT TERM

for payload in \
  payload_A9 \
  payload_A7 \
  payload_notA9 \
  payload_notA9_armv7 \
  payload_handle_checkm8_request \
  payload_handle_checkm8_request_armv7
do
  (
    cd "$GASTER"
    xxd -iC "$payload.bin" "$GENERATED/$payload.h"
  )
done

cc \
  -Wall -Wextra -Wpedantic -Werror \
  -DHAVE_LIBUSB \
  -I"$GENERATED" \
  "$GASTER/gaster.c" "$GASTER/lzfse.c" \
  -o "$OUTPUT" \
  -lusb-1.0 -lcrypto -pthread -ldl -Os

printf 'built %s\n' "$OUTPUT"
