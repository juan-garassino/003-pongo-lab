#!/usr/bin/env python3
"""Upload one m1n1 payload to Pongo's RAM buffer and issue bootm."""
import struct
import sys

import usb.core

UPLOAD_MAX = 128 * 1024 * 1024
BULK_TIMEOUT_MS = 1_000_000


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: pongo_boot_m1n1.py payload.bin")

    with open(sys.argv[1], "rb") as handle:
        data = handle.read()
    if not data or len(data) > UPLOAD_MAX:
        raise SystemExit(f"payload size {len(data)} outside 1..{UPLOAD_MAX}")

    devices = list(usb.core.find(find_all=True, idVendor=0x05AC, idProduct=0x4141))
    if len(devices) != 1:
        raise SystemExit(f"expected exactly one Pongo device, found {len(devices)}")

    device = devices[0]
    device.set_configuration()
    device.ctrl_transfer(0x21, 2, 0, 0, 0)
    device.ctrl_transfer(0x21, 1, 0, 0, struct.pack("I", len(data)))
    written = device.write(2, data, BULK_TIMEOUT_MS)
    if written != len(data):
        raise SystemExit(f"short upload: {written} of {len(data)} bytes; bootm not sent")
    if len(data) % 512 == 0:
        device.write(2, b"")
    print(f"uploaded {written} bytes")

    try:
        device.ctrl_transfer(0x21, 3, 0, 0, b"bootm\n")
    except usb.core.USBError as error:
        # Pongo may leave USB while handling the command, so this is not a failure.
        print(f"USB ended during bootm: {error}")
    print("bootm sent; watch the iPad screen for m1n1")


if __name__ == "__main__":
    main()
