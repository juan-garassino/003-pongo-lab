#!/usr/bin/env python3
"""Check the A7 gaster custom-request interface with bounded operations."""

import argparse
import struct
import usb.core
import usb.util


APPLE_VENDOR_ID = 0x05AC
DFU_PRODUCT_ID = 0x1227
DFU_TRANSFER_SIZE = 0x800
DFU_DOWNLOAD = 1
DFU_FILE_SUFFIX_LENGTH = 16
DFU_STATE_MANIFEST_SYNC = 6
DFU_STATE_MANIFEST = 7
DFU_STATE_MANIFEST_WAIT_RESET = 8

A7_SRTG = " SRTG:[iBoot-1704.10]"
PWNED_MARKER = " PWND:[gaster]"
INSECURE_MEMORY_BASE = 0x180380000
DIAGNOSTIC_OFFSET = 0x28
DIAGNOSTIC_LENGTH = 8
DIAGNOSTIC_DESTINATION_OFFSET = 0x100
COPY_MAGIC = 0x6D656D636D656D63
DONE_MAGIC = 0x646F6E65646F6E65


def parse_arguments():
    parser = argparse.ArgumentParser(
        description=(
            "Probe gaster's A7 custom request handler, then copy 8 bytes "
            "within gaster's own insecure command buffer."
        ),
        epilog=(
            "Without --execute this prints the plan and performs no USB or "
            "device communication."
        ),
    )
    parser.add_argument(
        "--execute",
        action="store_true",
        help="send the two bounded diagnostic requests to USB",
    )
    parser.add_argument(
        "--no-write-only",
        action="store_true",
        help="send only the 16-byte custom IN request; never send MEMC",
    )
    parser.add_argument(
        "--usb-timeout",
        type=int,
        default=5000,
        metavar="MS",
        help="USB timeout in milliseconds (default: 5000)",
    )
    return parser.parse_args()


def describe_plan(no_write_only):
    destination = INSECURE_MEMORY_BASE + DIAGNOSTIC_DESTINATION_OFFSET
    source = INSECURE_MEMORY_BASE + DIAGNOSTIC_OFFSET
    print("A7 gaster custom-request diagnostic")
    print("  step 1: read 16 bytes from the gaster command buffer")
    if no_write_only:
        print("  step 2: skipped by --no-write-only")
    else:
        print("  step 2: MEMC-copy 8 bytes within the same buffer")
        print(f"  source: 0x{source:x}")
        print(f"  destination: 0x{destination:x}")
    print("  execution: none")
    print("  arbitrary read: none")
    print("  memory outside gaster's command buffer: none")
    print("Dry run only; no USB command was sent.")


def find_single_pwned_dfu():
    devices = list(
        usb.core.find(
            idVendor=APPLE_VENDOR_ID,
            idProduct=DFU_PRODUCT_ID,
            find_all=True,
        )
    )
    if len(devices) != 1:
        raise SystemExit(
            f"expected exactly one 05ac:1227 device, found {len(devices)}"
        )

    device = devices[0]
    serial_number = usb.util.get_string(device, device.iSerialNumber)
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


def check_dfu_status(device, expected_state, timeout):
    response = device.ctrl_transfer(
        0xA1, 3, 0, 0, 6, timeout
    )
    if len(response) != 6:
        raise SystemExit(f"short DFU status response: {len(response)} bytes")
    status = int(response[0])
    state = int(response[4])
    if status != 0 or state != expected_state:
        raise SystemExit(
            f"unexpected DFU status/state: {status}/{state}; "
            f"expected 0/{expected_state}"
        )


def download_request(device, request, timeout):
    for offset in range(0, len(request), DFU_TRANSFER_SIZE):
        chunk = request[offset : offset + DFU_TRANSFER_SIZE]
        transferred = device.ctrl_transfer(
            0x21, DFU_DOWNLOAD, 0, 0, chunk, timeout
        )
        if transferred != len(chunk):
            raise SystemExit(
                f"DFU download failed at offset 0x{offset:x}: "
                f"{transferred}/{len(chunk)} bytes"
            )

    suffix = bytes(DFU_FILE_SUFFIX_LENGTH)
    transferred = device.ctrl_transfer(
        0x21, DFU_DOWNLOAD, 0, 0, suffix, timeout
    )
    if transferred != len(suffix):
        raise SystemExit("DFU suffix transfer failed")
    transferred = device.ctrl_transfer(
        0x21, DFU_DOWNLOAD, 0, 0, b"", timeout
    )
    if transferred != 0:
        raise SystemExit("zero-length DFU download failed")
    check_dfu_status(device, DFU_STATE_MANIFEST_SYNC, timeout)
    check_dfu_status(device, DFU_STATE_MANIFEST, timeout)
    check_dfu_status(device, DFU_STATE_MANIFEST_WAIT_RESET, timeout)


def preflight_custom_request(device, timeout):
    try:
        response = device.ctrl_transfer(
            0xA1, 2, 0xFFFF, 0, 16, timeout
        )
    except usb.core.USBError as error:
        raise SystemExit(
            "custom-request preflight failed before any diagnostic write: "
            f"{error}"
        ) from error
    if len(response) != 16:
        raise SystemExit(
            f"custom-request preflight returned {len(response)} bytes, expected 16"
        )
    print(f"preflight command-buffer response: {bytes(response).hex()}")


def same_buffer_copy(device, timeout):
    source = INSECURE_MEMORY_BASE + DIAGNOSTIC_OFFSET
    destination = INSECURE_MEMORY_BASE + DIAGNOSTIC_DESTINATION_OFFSET
    payload = b"A7DIAG\x00\x00"
    request = struct.pack(
        "<QQQQQ", COPY_MAGIC, 0, destination, source, len(payload)
    ) + payload

    download_request(device, request, timeout)
    try:
        response = device.ctrl_transfer(
            0xA1, 2, 0xFFFF, 0, 16, timeout
        )
    except usb.core.USBError as error:
        raise SystemExit(f"same-buffer MEMC response failed: {error}") from error
    if len(response) != 16:
        raise SystemExit(
            f"same-buffer MEMC returned {len(response)} bytes, expected 16"
        )

    done, returned = struct.unpack("<QQ", bytes(response))
    print(f"same-buffer MEMC response: done=0x{done:x} return=0x{returned:x}")
    if done != DONE_MAGIC or returned != destination:
        raise SystemExit(
            "same-buffer MEMC did not return DONE_MAGIC with its destination"
        )
    print("A7 gaster custom-request interface is responsive.")


def execute_on_hardware(timeout, no_write_only):
    device = find_single_pwned_dfu()
    try:
        preflight_custom_request(device, timeout)
        if not no_write_only:
            same_buffer_copy(device, timeout)
        else:
            print("no-write mode: MEMC diagnostic skipped")
    finally:
        usb.util.dispose_resources(device)


def main():
    args = parse_arguments()
    if not args.execute:
        describe_plan(args.no_write_only)
        return
    execute_on_hardware(args.usb_timeout, args.no_write_only)


if __name__ == "__main__":
    main()
