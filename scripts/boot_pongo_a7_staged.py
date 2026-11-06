#!/usr/bin/env python3
"""Stage and execute the A7 LZ4 Pongo loader outside gaster's DFU buffer."""

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
STAGING_BASE = 0x180200000
TRAMPOLINE_SIZE = 0x200
COMMAND_HEADER_SIZE = 0x28
SHELLCODE_SIZE = 0x200
COMPRESSED_SIZE_OFFSET = 0x1FC
CAPACITY_INSTRUCTION_OFFSET = 0x0C
STAGED_CAPACITY_INSTRUCTION = bytes.fromhex("0304a052")
COPY_MAGIC = 0x6D656D636D656D63
EXEC_MAGIC = 0x6578656365786563
DONE_MAGIC = 0x646F6E65646F6E65


def parse_arguments():
    parser = argparse.ArgumentParser(
        description=(
            "Copy the LZ4-wrapped Pongo image to a safe A7 staging address, "
            "then execute one small register trampoline."
        ),
        epilog="Without --execute this performs no USB or device communication.",
    )
    parser.add_argument(
        "wrapper",
        nargs="?",
        type=Path,
        default=Path("build/Pongo.a7.staged.dfu.bin"),
        help="staged LZ4 wrapper produced by scripts/build-pongo-a7.sh",
    )
    parser.add_argument(
        "--trampoline",
        type=Path,
        default=Path("build/Pongo.a7.lz4.trampoline.bin"),
        help="LZ4-loader register trampoline",
    )
    parser.add_argument("--execute", action="store_true")
    parser.add_argument(
        "--chunk-size",
        type=lambda value: int(value, 0),
        default=0x400,
        help="MEMC payload bytes per command (default: 0x400)",
    )
    parser.add_argument("--usb-timeout", type=int, default=5000)
    parser.add_argument("--boot-timeout", type=int, default=30)
    return parser.parse_args()


def validate_inputs(wrapper, trampoline, chunk_size):
    wrapper_data = wrapper.read_bytes()
    trampoline_data = trampoline.read_bytes()
    if len(wrapper_data) <= 0x200:
        raise SystemExit(f"wrapper is too short: {len(wrapper_data)} bytes")
    compressed_size = int.from_bytes(
        wrapper_data[COMPRESSED_SIZE_OFFSET : COMPRESSED_SIZE_OFFSET + 4],
        "little",
    )
    if compressed_size != len(wrapper_data) - SHELLCODE_SIZE:
        raise SystemExit(
            f"compressed-size field is {compressed_size}, expected "
            f"{len(wrapper_data) - SHELLCODE_SIZE}"
        )
    capacity_instruction = wrapper_data[
        CAPACITY_INSTRUCTION_OFFSET : CAPACITY_INSTRUCTION_OFFSET + 4
    ]
    if capacity_instruction != STAGED_CAPACITY_INSTRUCTION:
        raise SystemExit(
            "wrapper is not the staged two-MiB variant; capacity instruction is "
            f"{capacity_instruction.hex()}"
        )
    if len(trampoline_data) > TRAMPOLINE_SIZE:
        raise SystemExit(
            f"trampoline is {len(trampoline_data)} bytes; limit is {TRAMPOLINE_SIZE}"
        )
    if chunk_size <= 0 or chunk_size % 8 != 0:
        raise SystemExit("--chunk-size must be a positive multiple of eight")
    if COMMAND_HEADER_SIZE + chunk_size + DFU_FILE_SUFFIX_LENGTH > DFU_TRANSFER_SIZE:
        raise SystemExit(
            "--chunk-size leaves no room for the command header and DFU suffix"
        )


def staged_image(wrapper, trampoline):
    trampoline_data = trampoline.read_bytes()
    return trampoline_data.ljust(TRAMPOLINE_SIZE, b"\0") + wrapper.read_bytes()


def describe_plan(wrapper, trampoline, chunk_size):
    image = staged_image(wrapper, trampoline)
    command_count = math.ceil(len(image) / chunk_size)
    print("A7 staged LZ4 Pongo boot plan")
    print(f"  wrapper: {wrapper} ({len(wrapper.read_bytes())} bytes)")
    print(f"  wrapper SHA-256: {hashlib.sha256(wrapper.read_bytes()).hexdigest()}")
    print(f"  trampoline: {trampoline} ({len(trampoline.read_bytes())} bytes)")
    print(f"  staged image: {len(image)} bytes at 0x{STAGING_BASE:x}")
    print(f"  copy commands: {command_count} x at most 0x{chunk_size:x} bytes")
    print("  final command: one EXEC of the staging-base trampoline")
    print("Dry run only; no USB command was sent.")


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
        raise SystemExit("DFU device is not marked PWND:[gaster]")
    try:
        device.set_configuration()
    except usb.core.USBError as error:
        raise SystemExit(f"could not configure pwned DFU device: {error}") from error
    print(f"found pwned A7 DFU device: {serial_number}")
    return device


def check_dfu_status(device, expected_state, timeout):
    response = device.ctrl_transfer(0xA1, DFU_GET_STATUS, 0, 0, 6, timeout)
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
            0x21, DFU_DOWNLOAD, 0, 0, chunk, timeout
        )
        if transferred != len(chunk):
            raise SystemExit(
                f"DFU download failed at request offset 0x{offset:x}: "
                f"{transferred}/{len(chunk)}"
            )

    suffix = bytes(DFU_FILE_SUFFIX_LENGTH)
    transferred = device.ctrl_transfer(0x21, DFU_DOWNLOAD, 0, 0, suffix, timeout)
    if transferred != len(suffix):
        raise SystemExit("DFU suffix transfer failed")
    transferred = device.ctrl_transfer(0x21, DFU_DOWNLOAD, 0, 0, b"", timeout)
    if transferred != 0:
        raise SystemExit("zero-length DFU download failed")
    check_dfu_status(device, DFU_STATE_MANIFEST_SYNC, timeout)
    check_dfu_status(device, DFU_STATE_MANIFEST, timeout)
    check_dfu_status(device, DFU_STATE_MANIFEST_WAIT_RESET, timeout)


def copy_command(data, destination):
    source = INSECURE_MEMORY_BASE + COMMAND_HEADER_SIZE
    return struct.pack(
        "<QQQQQ", COPY_MAGIC, 0, destination, source, len(data)
    ) + data


def gaster_copy(device, data, destination, timeout):
    download_request(device, copy_command(data, destination), timeout)
    response = device.ctrl_transfer(0xA1, 2, 0xFFFF, 0, 16, timeout)
    if len(response) != 16:
        raise SystemExit(f"short MEMC response: {len(response)} bytes")
    done, returned = struct.unpack("<QQ", bytes(response))
    if done != DONE_MAGIC or returned != destination:
        raise SystemExit(
            f"MEMC copy failed: done=0x{done:x} return=0x{returned:x}"
        )


def execute_trampoline_command(trampoline_address):
    return struct.pack(
        "<QQ8Q",
        EXEC_MAGIC,
        trampoline_address,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
    )


def wait_for_pongo(timeout):
    import usb.core

    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            if find_single_device(PONGO_PRODUCT_ID):
                print("05ac:4141 present: PongoOS is running")
                return
        except SystemExit:
            pass
        time.sleep(0.25)
    raise SystemExit(f"PongoOS 05ac:4141 did not appear within {timeout} seconds")


def execute_on_hardware(wrapper, trampoline, chunk_size, usb_timeout, boot_timeout):
    import usb.core
    import usb.util

    image = staged_image(wrapper, trampoline)
    device = open_pwned_dfu(usb_timeout)
    command_count = math.ceil(len(image) / chunk_size)
    print(f"copying staged LZ4 image in {command_count} bounded MEMC commands")
    for index, offset in enumerate(range(0, len(image), chunk_size), start=1):
        chunk = image[offset : offset + chunk_size]
        gaster_copy(device, chunk, STAGING_BASE + offset, usb_timeout)
        print(
            f"  {index:3d}/{command_count}: "
            f"0x{offset:06x}..0x{offset + len(chunk):06x}"
        )

    print(f"executing {len(trampoline.read_bytes())}-byte LZ4 trampoline")
    download_request(
        device, execute_trampoline_command(STAGING_BASE), usb_timeout
    )
    try:
        response = device.ctrl_transfer(
            0xA1, 2, 0xFFFF, 0, 16, min(usb_timeout, 1000)
        )
        done = struct.unpack("<Q", bytes(response[:8]))[0]
        if done == DONE_MAGIC:
            raise SystemExit(
                "LZ4 trampoline returned to gaster before Pongo took over; no boot"
            )
    except usb.core.USBError:
        pass

    usb.util.dispose_resources(device)
    wait_for_pongo(boot_timeout)


def main():
    args = parse_arguments()
    validate_inputs(args.wrapper, args.trampoline, args.chunk_size)
    if not args.execute:
        describe_plan(args.wrapper, args.trampoline, args.chunk_size)
        return
    execute_on_hardware(
        args.wrapper,
        args.trampoline,
        args.chunk_size,
        args.usb_timeout,
        args.boot_timeout,
    )


if __name__ == "__main__":
    main()
