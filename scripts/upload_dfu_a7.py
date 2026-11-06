#!/usr/bin/env python3

import argparse
import time
from pathlib import Path

import usb.core
import usb.util


APPLE_VENDOR_ID = 0x05AC
DFU_PRODUCT_ID = 0x1227
PONGO_PRODUCT_ID = 0x4141
DFU_DOWNLOAD = 1
DFU_CLEAR_STATUS = 4
CHUNK_SIZE = 0x800
SHELLCODE_SIZE = 512
COMPRESSED_SIZE_OFFSET = 0x1FC
A7_SRTG = " SRTG:[iBoot-1704.10]"
PWNED_MARKER = " PWND:[gaster]"


def parse_arguments():
    parser = argparse.ArgumentParser(
        description="Send an LZ4-wrapped image to an Apple A7 in pwned DFU."
    )
    parser.add_argument("image", type=Path, help="wrapped image path")
    parser.add_argument(
        "--execute",
        action="store_true",
        help="send the wrapped image to the already-pwned iPad",
    )
    parser.add_argument("--timeout", type=int, default=60, help="Pongo wait timeout")
    parser.add_argument("--usb-timeout", type=int, default=5000)
    return parser.parse_args()


def validate_image(image):
    if len(image) > 0x80000:
        raise SystemExit(f"image is {len(image)} bytes; A7 DFU limit is 524288")
    if len(image) <= SHELLCODE_SIZE:
        raise SystemExit("wrapped image has no compressed payload")
    compressed_size = int.from_bytes(
        image[COMPRESSED_SIZE_OFFSET : COMPRESSED_SIZE_OFFSET + 4], "little"
    )
    expected_size = len(image) - SHELLCODE_SIZE
    if compressed_size != expected_size:
        raise SystemExit(
            f"compressed-size field is {compressed_size}, expected {expected_size}"
        )


def find_single_dfu():
    devices = list(
        usb.core.find(
            idVendor=APPLE_VENDOR_ID, idProduct=DFU_PRODUCT_ID, find_all=True
        )
    )
    if len(devices) != 1:
        raise SystemExit(
            f"expected exactly one 05ac:1227 device, found {len(devices)}"
        )
    return devices[0]


def open_pwned_dfu():
    device = find_single_dfu()
    try:
        serial_number = usb.util.get_string(device, device.iSerialNumber)
    except (ValueError, usb.core.USBError) as error:
        raise SystemExit(
            "could not read the DFU serial descriptor; a fresh DFU/pwn cycle is "
            f"required before uploading the wrapped image: {error}"
        ) from error
    if A7_SRTG not in serial_number:
        raise SystemExit(
            f"device is not the recorded A7 iBoot build: {serial_number!r}"
        )
    if PWNED_MARKER not in serial_number:
        raise SystemExit(
            "DFU device is not marked PWND:[gaster]; run the manual pwn step first"
        )
    device.set_configuration()
    print(f"found pwned A7 DFU device: {serial_number}")
    return device

def execute(image, timeout, usb_timeout):
    device = open_pwned_dfu()
    print(f"sending {len(image)} bytes in {((len(image) + CHUNK_SIZE - 1) // CHUNK_SIZE)} blocks")
    for offset in range(0, len(image), CHUNK_SIZE):
        chunk = image[offset : offset + CHUNK_SIZE]
        transferred = device.ctrl_transfer(
            0x21, DFU_DOWNLOAD, 0, 0, chunk, usb_timeout
        )
        if transferred != len(chunk):
            raise SystemExit(f"DFU download failed at offset {offset}")
        print(f"{min(offset + CHUNK_SIZE, len(image))}/{len(image)}", flush=True)

    try:
        device.ctrl_transfer(0x21, DFU_CLEAR_STATUS, 0, 0, 0, usb_timeout)
    except usb.core.USBError as error:
        print(f"DFU_CLEAR_STATUS returned {error}; continuing to Pongo detection")
    print("payload handed to pwned DFU")
    usb.util.dispose_resources(device)

    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if usb.core.find(idVendor=APPLE_VENDOR_ID, idProduct=PONGO_PRODUCT_ID):
            print("05ac:4141 present: PongoOS is running")
            return
        time.sleep(0.3)

    raise SystemExit(f"PongoOS 05ac:4141 did not appear within {timeout} seconds")


def main():
    args = parse_arguments()
    image = args.image.read_bytes()
    validate_image(image)
    if not args.execute:
        print("A7 LZ4-wrapped Pongo upload plan")
        print(f"  image: {args.image} ({len(image)} bytes)")
        print(f"  blocks: {((len(image) + CHUNK_SIZE - 1) // CHUNK_SIZE)}")
        print("  execution: LZ4 loader entry after complete upload")
        print("Dry run only; no USB command was sent.")
        return
    execute(image, args.timeout, args.usb_timeout)


if __name__ == "__main__":
    main()
