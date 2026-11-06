#!/usr/bin/env python3
"""Send one Pongo command and drain its USB stdout response."""
import sys
import time
import usb.core

MAX_PACKET = 512
MAX_OUTPUT = 64 * 1024

if len(sys.argv) != 2:
    raise SystemExit("usage: pongo_transact.py 'command'")

devices = list(usb.core.find(find_all=True, idVendor=0x05AC, idProduct=0x4141))
if len(devices) != 1:
    raise SystemExit(f"expected exactly one Pongo device, found {len(devices)}")

device = devices[0]
device.set_configuration()
device.ctrl_transfer(0x21, 3, 0, 0, sys.argv[1].encode() + b"\n")

output = bytearray()
while len(output) < MAX_OUTPUT:
    time.sleep(0.08)
    chunk = device.ctrl_transfer(0xA1, 1, 0, 0, MAX_PACKET)
    if not chunk:
        break
    output.extend(chunk)
    if len(chunk) < MAX_PACKET:
        break

sys.stdout.write(output.decode("utf-8", errors="replace"))
if output and not output.endswith((b"\n", b"\r")):
    sys.stdout.write("\n")
