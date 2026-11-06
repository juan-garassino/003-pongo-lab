#!/usr/bin/env python3
# pylint: disable=import-outside-toplevel
"""Compile and run the portable hello app against deterministic fake devices."""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

from fake_device import FakeFramebuffer, FakeTouchStream, PointerEvent


ROOT = Path(__file__).resolve().parent.parent
LINUX_APPS = ROOT / "linux-apps"


def compile_simulator(binary: Path) -> None:
    binary.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            "cc",
            "-std=c11",
            "-Wall",
            "-Wextra",
            "-Werror",
            "-pedantic",
            f"-I{LINUX_APPS / 'include'}",
            str(LINUX_APPS / "juan-core.c"),
            str(LINUX_APPS / "hello-juan.c"),
            str(Path(__file__).parent / "hello-sim.c"),
            "-o",
            str(binary),
        ],
        check=True,
    )


def assert_close(actual, expected, tolerance=32):
    if any(abs(left - right) > tolerance for left, right in zip(actual, expected)):
        raise AssertionError(f"color {actual} is not close to {expected}")


def validate_frames(output: Path, framebuffer: FakeFramebuffer) -> None:
    initial = framebuffer.read_ppm(output / "frame-000000.ppm")
    assert_close(initial[20][8], (27, 80, 165))
    assert_close(initial[20][-8], (34, 120, 69))
    assert_close(initial[-20][-8], (163, 123, 33))

    touched = framebuffer.read_ppm(output / "frame-000012.ppm")
    # The horizontal crosshair remains visible beside the pointer.
    assert_close(touched[171][152], (248, 250, 252))
    # The active lower-right quadrant is visibly brighter than its neighbors.
    lower_right = touched[320][250]
    lower_left = touched[320][5]
    assert sum(lower_right) > sum(lower_left)


def run(output: Path) -> None:
    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)

    framebuffer = FakeFramebuffer(width=256, height=342)
    events = FakeTouchStream(
        [
            PointerEvent(10, "down", 128, 171),
            PointerEvent(11, "move", 150, 184),
            PointerEvent(12, "move", 128, 171),
            PointerEvent(14, "up", 128, 171),
            PointerEvent(20, "down", 64, 86),
            PointerEvent(24, "up", 64, 86),
        ]
    )
    script = output / "events.tsv"
    events.write_script(script)
    binary = output.parent / "hello-sim"
    compile_simulator(binary)
    result = subprocess.run(
        [str(binary), str(output), "256", "342", str(script)],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    )
    print(result.stdout.strip())
    summary = result.stdout.strip().split()
    assert summary[-1] == "tones=12", result.stdout
    validate_frames(output, framebuffer)
    print("linux-apps simulator checks passed")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--build-dir",
        type=Path,
        default=ROOT / "build" / "linux-apps",
    )
    arguments = parser.parse_args()
    run(arguments.build_dir / "simulator")
    return 0


if __name__ == "__main__":
    sys.exit(main())
