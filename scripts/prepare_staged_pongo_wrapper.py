#!/usr/bin/env python3
"""Prepare openra1n's LZ4 loader for gaster's two-MiB staged path."""

import argparse
import hashlib
from pathlib import Path


SHELLCODE_SIZE = 0x200
COMPRESSED_SIZE_OFFSET = 0x1FC
CAPACITY_INSTRUCTION_OFFSET = 0x0C
DFU_CAPACITY = 0x7FE00
STAGED_CAPACITY = 0x200000
DFU_CAPACITY_INSTRUCTION = bytes.fromhex("e3271732")
STAGED_CAPACITY_INSTRUCTION = bytes.fromhex("0304a052")


def parse_arguments():
    parser = argparse.ArgumentParser(
        description=(
            "Patch openra1n's relocatable LZ4 loader capacity from the normal "
            "DFU window to the full two-MiB Pongo destination."
        )
    )
    parser.add_argument(
        "wrapper",
        nargs="?",
        type=Path,
        default=Path("build/Pongo.a7.dfu.bin"),
        help="wrapper produced by scripts/build-pongo-a7.sh",
    )
    parser.add_argument(
        "output",
        nargs="?",
        type=Path,
        default=Path("build/Pongo.a7.staged.dfu.bin"),
        help="patched staged wrapper output",
    )
    return parser.parse_args()


def prepare(wrapper_path, output_path):
    wrapper = wrapper_path.read_bytes()
    if len(wrapper) <= SHELLCODE_SIZE:
        raise SystemExit(f"wrapper is too short: {len(wrapper)} bytes")

    compressed_size = int.from_bytes(
        wrapper[COMPRESSED_SIZE_OFFSET : COMPRESSED_SIZE_OFFSET + 4], "little"
    )
    if compressed_size != len(wrapper) - SHELLCODE_SIZE:
        raise SystemExit(
            f"compressed-size field is {compressed_size}, expected "
            f"{len(wrapper) - SHELLCODE_SIZE}"
        )

    capacity_offset = CAPACITY_INSTRUCTION_OFFSET
    capacity_instruction = wrapper[capacity_offset : capacity_offset + 4]
    if capacity_instruction == STAGED_CAPACITY_INSTRUCTION:
        raise SystemExit("input wrapper is already patched for the staged path")
    if capacity_instruction != DFU_CAPACITY_INSTRUCTION:
        raise SystemExit(
            "unexpected LZ4 capacity instruction at offset 0xc: "
            f"{capacity_instruction.hex()}"
        )

    patched = bytearray(wrapper)
    patched[capacity_offset : capacity_offset + 4] = STAGED_CAPACITY_INSTRUCTION
    output_path.write_bytes(patched)

    print(f"prepared staged LZ4 wrapper: {output_path}")
    print(f"  wrapper bytes: {len(patched)}")
    print(f"  compressed bytes: {compressed_size:#x}")
    print(f"  decompression capacity: {DFU_CAPACITY:#x} -> {STAGED_CAPACITY:#x}")
    print(f"  SHA-256: {hashlib.sha256(patched).hexdigest()}")


def main():
    arguments = parse_arguments()
    prepare(arguments.wrapper, arguments.output)


if __name__ == "__main__":
    main()
