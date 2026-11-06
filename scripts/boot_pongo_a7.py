#!/usr/bin/env python3
"""Boot a raw A7 Pongo image through gaster's bounded DFU request interface."""

import argparse
import hashlib
import math
import struct
import time
from pathlib import Path


APPLE_VENDOR_ID = 0x05AC
DFU_PRODUCT_ID = 0x1227
PONGO_PRODUCT_ID = 0x4141
DFU_DOWNLOAD = 1
DFU_GET_STATUS = 3
DFU_FILE_SUFFIX_LENGTH = 16
DFU_TRANSFER_SIZE = 0x800
DFU_STATUS_OK = 0
DFU_STATE_MANIFEST_SYNC = 6
DFU_STATE_MANIFEST = 7
DFU_STATE_MANIFEST_WAIT_RESET = 8

A7_SRTG = " SRTG:[iBoot-1704.10]"
PWNED_MARKER = " PWND:[gaster]"
INSECURE_MEMORY_BASE = 0x180380000
PONGO_LOAD_BASE = 0x180000000
PONGO_RELOCATED_BASE = 0x180180000
PONGO_COPY_SIZE = 0x200000
TRAMPOLINE_OFFSET = 0x100
COMMAND_HEADER_SIZE = 0x28
COPY_MAGIC = 0x6D656D636D656D63
EXEC_MAGIC = 0x6578656365786563
DONE_MAGIC = 0x646F6E65646F6E65


def parse_arguments():
    parser = argparse.ArgumentParser(
        description=(
            "Copy plain Pongo.bin through gaster MEMC requests, then execute an "
            "explicit A7 register trampoline. Does not pwn DFU or enter DFU."
        ),
        epilog="Without --execute this performs no USB or device communication.",
    )
    parser.add_argument(
        "image",
        nargs="?",
        type=Path,
        default=Path("src/pongoOS/build/Pongo.bin"),
        help="raw Pongo image (default: src/pongoOS/build/Pongo.bin)",
    )
    parser.add_argument(
        "--trampoline",
        type=Path,
        default=Path("build/Pongo.a7.trampoline.bin"),
        help="trampoline produced by scripts/build-pongo-a7.sh",
    )
    parser.add_argument(
        "--execute",
        action="store_true",
        help="communicate with the already-pwned iPad and execute the payload",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="print the exact bounded command plan without touching USB",
    )
    parser.add_argument(
        "--chunk-size",
        type=lambda value: int(value, 0),
        default=0x400,
        help="MEMC payload bytes per command (default: 0x400)",
    )
    parser.add_argument(
        "--image-copy-limit",
        type=int,
        default=0,
        metavar="N",
        help=(
            "copy only the first N image MEMC commands, then stop without "
            "trampoline copy or execution (default: 0 means all)"
        ),
    )
    parser.add_argument(
        "--usb-timeout",
        type=int,
        default=5000,
        help="USB control-transfer timeout in milliseconds",
    )
    parser.add_argument(
        "--boot-timeout",
        type=int,
        default=20,
        help="seconds to wait for Pongo USB enumeration",
    )
    return parser.parse_args()


def check_mode(arguments):
    if arguments.execute and arguments.dry_run:
        raise SystemExit("choose either --execute or --dry-run, not both")


def validate_inputs(image, trampoline, chunk_size, image_copy_limit):
    if not image.is_file():
        raise SystemExit(f"missing Pongo image: {image}")
    if not trampoline.is_file():
        raise SystemExit(
            f"missing trampoline: {trampoline}; run scripts/build-pongo-a7.sh"
        )
    if len(image.read_bytes()) == 0:
        raise SystemExit("Pongo image is empty")
    if len(image.read_bytes()) > PONGO_COPY_SIZE:
        raise SystemExit(
            f"Pongo image is {len(image.read_bytes())} bytes; limit is {PONGO_COPY_SIZE}"
        )
    if chunk_size <= 0 or chunk_size % 8 != 0:
        raise SystemExit("--chunk-size must be a positive multiple of eight")
    if COMMAND_HEADER_SIZE + chunk_size + DFU_FILE_SUFFIX_LENGTH > DFU_TRANSFER_SIZE:
        raise SystemExit(
            "--chunk-size leaves no room for the command header and DFU suffix"
        )
    if len(trampoline.read_bytes()) > TRAMPOLINE_OFFSET:
        raise SystemExit(
            f"trampoline is {len(trampoline.read_bytes())} bytes; limit is {TRAMPOLINE_OFFSET}"
        )
    if image_copy_limit < 0:
        raise SystemExit("--image-copy-limit must not be negative")


def copy_command(data, destination):
    source = INSECURE_MEMORY_BASE + COMMAND_HEADER_SIZE
    return struct.pack(
        "<QQQQQ", COPY_MAGIC, 0, destination, source, len(data)
    ) + data


def execute_trampoline_command(trampoline_address, image_length):
    arguments = [
        0,
        PONGO_LOAD_BASE,
        PONGO_RELOCATED_BASE,
        trampoline_address,
        image_length,
        PONGO_LOAD_BASE + PONGO_COPY_SIZE,
        0,
        0,
    ]
    return struct.pack(
        "<QQ8Q", EXEC_MAGIC, trampoline_address, *arguments
    )


def describe_plan(image, trampoline, chunk_size, image_copy_limit):
    image_data = image.read_bytes()
    command_count = math.ceil(len(image_data) / chunk_size)
    print("A7 bounded gaster boot plan")
    print(f"  image: {image} ({len(image_data)} bytes)")
    print(f"  image SHA-256: {hashlib.sha256(image_data).hexdigest()}")
    print(f"  trampoline: {trampoline} ({len(trampoline.read_bytes())} bytes)")
    print(f"  DFU command buffer: 0x{INSECURE_MEMORY_BASE:x}")
    print(f"  trampoline destination: 0x{INSECURE_MEMORY_BASE + TRAMPOLINE_OFFSET:x}")
    print(f"  Pongo low address: 0x{PONGO_LOAD_BASE:x}")
    print(f"  Pongo relocated address: 0x{PONGO_RELOCATED_BASE:x}")
    print(f"  zeroed tail: 0x{PONGO_LOAD_BASE + len(image_data):x}..0x{PONGO_LOAD_BASE + PONGO_COPY_SIZE:x}")
    print(f"  copy commands: {command_count} x 0x{chunk_size:x}-byte chunks maximum")
    if image_copy_limit == 0:
        print("  final commands: trampoline copy, trampoline execute")
    else:
        limited_count = min(image_copy_limit, command_count)
        limited_bytes = min(len(image_data), limited_count * chunk_size)
        print(f"  staged copy limit: {limited_count} image MEMC command(s)")
        print(f"  staged copy range: 0x0..0x{limited_bytes:x}")
        print("  final commands: none; no trampoline copy or execution")
    print("Dry run only; no USB command was sent.")


def check_dfu_status(device, expected_state, timeout):
    response = device.ctrl_transfer(
        0xA1,
        DFU_GET_STATUS,
        0,
        0,
        6,
        timeout,
    )
    if len(response) != 6:
        raise SystemExit(f"short DFU status response: {len(response)} bytes")
    status = int(response[0])
    state = int(response[4])
    if status != DFU_STATUS_OK or state != expected_state:
        raise SystemExit(
            f"unexpected DFU status/state: {status}/{state}; expected 0/{expected_state}"
        )


def download_request(device, request, timeout):
    for offset in range(0, len(request), DFU_TRANSFER_SIZE):
        chunk = request[offset : offset + DFU_TRANSFER_SIZE]
        transferred = device.ctrl_transfer(
            0x21,
            DFU_DOWNLOAD,
            0,
            0,
            chunk,
            timeout,
        )
        if transferred != len(chunk):
            raise SystemExit(
                f"DFU download failed at request offset 0x{offset:x}: {transferred}/{len(chunk)}"
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


def gaster_copy(device, data, destination, timeout):
    request = copy_command(data, destination)
    download_request(device, request, timeout)
    response = device.ctrl_transfer(
        0xA1, 2, 0xFFFF, 0, 16, timeout
    )
    if len(response) != 16:
        raise SystemExit(f"short MEMC response: {len(response)} bytes")
    done, returned = struct.unpack("<QQ", bytes(response))
    if done != DONE_MAGIC or returned != destination:
        raise SystemExit(
            f"MEMC copy failed: done=0x{done:x} return=0x{returned:x}"
        )


def find_single_device(product_id):
    import usb.core

    devices = list(
        usb.core.find(idVendor=APPLE_VENDOR_ID, idProduct=product_id, find_all=True)
    )
    if len(devices) != 1:
        raise SystemExit(
            f"expected exactly one 05ac:{product_id:04x} device, found {len(devices)}"
        )
    return devices[0]


def open_pwned_dfu(timeout):
    import usb.core
    import usb.util

    device = find_single_device(DFU_PRODUCT_ID)
    serial_number = usb.util.get_string(device, device.iSerialNumber)
    if A7_SRTG not in serial_number:
        raise SystemExit(
            f"device is not the recorded A7 iBoot build: {serial_number!r}"
        )
    if PWNED_MARKER not in serial_number:
        raise SystemExit(
            "DFU device is not marked PWND:[gaster]; run the manual pwn step first"
        )
    try:
        device.set_configuration()
    except usb.core.USBError as error:
        raise SystemExit(f"could not configure pwned DFU device: {error}") from error
    print(f"found pwned A7 DFU device: {serial_number}")
    return device


def wait_for_pongo(timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            if find_single_device(PONGO_PRODUCT_ID):
                print("05ac:4141 present: PongoOS is running")
                return
        except SystemExit:
            pass
        time.sleep(0.25)
    raise SystemExit(
        f"PongoOS 05ac:4141 did not appear within {timeout} seconds"
    )


def execute_on_hardware(
    image,
    trampoline,
    chunk_size,
    image_copy_limit,
    usb_timeout,
    boot_timeout,
):
    import usb.core
    import usb.util

    image_data = image.read_bytes()
    trampoline_data = trampoline.read_bytes()
    device = open_pwned_dfu(usb_timeout)

    command_count = math.ceil(len(image_data) / chunk_size)
    staged_copy = image_copy_limit > 0
    if staged_copy:
        print(
            f"staged copy: only {image_copy_limit} of {command_count} "
            "image MEMC commands"
        )
    else:
        print(f"copying Pongo in {command_count} bounded MEMC commands")
    for index, offset in enumerate(range(0, len(image_data), chunk_size), start=1):
        if staged_copy and index > image_copy_limit:
            break
        chunk = image_data[offset : offset + chunk_size]
        gaster_copy(device, chunk, PONGO_LOAD_BASE + offset, usb_timeout)
        print(f"  {index:3d}/{command_count}: 0x{offset:06x}..0x{offset + len(chunk):06x}")

    if staged_copy:
        print("staged copy complete; stopping without trampoline or EXEC")
        usb.util.dispose_resources(device)
        return

    trampoline_address = INSECURE_MEMORY_BASE + TRAMPOLINE_OFFSET
    print(f"copying {len(trampoline_data)}-byte register trampoline")
    gaster_copy(device, trampoline_data, trampoline_address, usb_timeout)

    request = execute_trampoline_command(trampoline_address, len(image_data))
    print("executing trampoline; control transfer may time out when Pongo takes USB")
    download_request(device, request, usb_timeout)
    try:
        response = device.ctrl_transfer(
            0xA1, 2, 0xFFFF, 0, 16, min(usb_timeout, 1000)
        )
        done = struct.unpack("<Q", bytes(response[:8]))[0]
        if done == DONE_MAGIC:
            raise SystemExit(
                "trampoline returned to gaster before Pongo took over; no boot"
            )
    except usb.core.USBError:
        pass

    usb.util.dispose_resources(device)
    wait_for_pongo(boot_timeout)


def main():
    args = parse_arguments()
    check_mode(args)
    validate_inputs(
        args.image, args.trampoline, args.chunk_size, args.image_copy_limit
    )
    if not args.execute:
        describe_plan(
            args.image, args.trampoline, args.chunk_size, args.image_copy_limit
        )
        return
    execute_on_hardware(
        args.image,
        args.trampoline,
        args.chunk_size,
        args.image_copy_limit,
        args.usb_timeout,
        args.boot_timeout,
    )


if __name__ == "__main__":
    main()
