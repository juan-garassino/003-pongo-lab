#!/usr/bin/env python3
"""Decode an Apple J85 multitouch resource fork into Linux firmware."""

from __future__ import annotations

import argparse
import plistlib
import zlib
from pathlib import Path


PERSONALITY = "C1F14,3"
EXPECTED_VERSION = "0x0210.bin"
EXPECTED_PACKET_TYPE = "Z2"


def decode_chunk(data: bytes, offset: int) -> tuple[bytes, int] | None:
    if offset >= len(data) or data[offset] != 0x78:
        return None
    decoder = zlib.decompressobj()
    try:
        output = decoder.decompress(data[offset:])
    except zlib.error:
        return None
    if not decoder.eof or not output:
        return None
    consumed = len(data) - offset - len(decoder.unused_data)
    return output, offset + consumed


def decode_resource_fork(data: bytes) -> bytes:
    first: tuple[bytes, int] | None = None
    for offset in range(min(len(data), 1024)):
        candidate = decode_chunk(data, offset)
        if candidate is not None and candidate[0].startswith(b"<?xml"):
            first = candidate
            break
    if first is None:
        raise ValueError("no XML plist zlib chunk found in resource fork")

    chunks: list[bytes] = []
    output, position = first
    chunks.append(output)
    while position < len(data):
        candidate = decode_chunk(data, position)
        if candidate is None:
            position += 1
            continue
        output, position = candidate
        chunks.append(output)
    return b"".join(chunks)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("resource_fork", type=Path)
    parser.add_argument("firmware_output", type=Path)
    parser.add_argument("--plist-output", type=Path)
    args = parser.parse_args()

    decoded = decode_resource_fork(args.resource_fork.read_bytes())
    plist = plistlib.loads(decoded)
    try:
        personality = plist[PERSONALITY]
        firmware = personality["Constructed Firmware"]
        version = personality["Constructed Firmware Version"]
        packet_type = personality["PreconstructedBootloadPacketType"]
    except KeyError as error:
        raise ValueError(f"missing J85 multitouch plist key: {error}") from error

    if version != EXPECTED_VERSION:
        raise ValueError(f"unexpected J85 firmware version: {version}")
    if packet_type != EXPECTED_PACKET_TYPE:
        raise ValueError(f"unexpected J85 packet type: {packet_type}")
    if not isinstance(firmware, bytes) or not firmware:
        raise ValueError("J85 constructed firmware is empty")

    args.firmware_output.parent.mkdir(parents=True, exist_ok=True)
    args.firmware_output.write_bytes(firmware)
    if args.plist_output is not None:
        args.plist_output.parent.mkdir(parents=True, exist_ok=True)
        args.plist_output.write_bytes(decoded)

    print(
        f"decoded {args.resource_fork}: "
        f"{len(decoded)}-byte plist, {len(firmware)}-byte firmware"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
