#!/usr/bin/env python3
"""Deterministic fake device boundary for Juan Linux applications."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import struct


@dataclass(frozen=True)
class PointerEvent:
    frame: int
    kind: str
    x: int
    y: int


@dataclass(frozen=True)
class AudioIntent:
    kind: str
    frequency_hz: int
    level: int


class FakeFramebuffer:
    def __init__(self, width: int = 256, height: int = 342) -> None:
        if width <= 0 or height <= 0:
            raise ValueError("fake framebuffer dimensions must be positive")
        self.width = width
        self.height = height

    def read_ppm(self, path: Path) -> list[list[tuple[int, int, int]]]:
        data = path.read_bytes()
        marker, dimensions, maximum, pixels = data.split(b"\n", 3)
        if marker != b"P6":
            raise ValueError(f"{path}: expected binary PPM")
        width_s, height_s = dimensions.split()
        if (int(width_s), int(height_s)) != (self.width, self.height):
            raise ValueError(f"{path}: wrong PPM dimensions")
        if int(maximum) != 255:
            raise ValueError(f"{path}: unsupported PPM range")
        expected = self.width * self.height * 3
        if len(pixels) != expected:
            raise ValueError(f"{path}: expected {expected} pixel bytes")

        rows: list[list[tuple[int, int, int]]] = []
        offset = 0
        for _ in range(self.height):
            row: list[tuple[int, int, int]] = []
            for _ in range(self.width):
                row.append(tuple(pixels[offset : offset + 3]))
                offset += 3
            rows.append(row)
        return rows


class FakeTouchStream:
    def __init__(self, events: list[PointerEvent]) -> None:
        self.events = events

    def write_script(self, path: Path) -> None:
        lines = ["frame\tkind\tx\ty"]
        lines.extend(
            f"{event.frame}\t{event.kind}\t{event.x}\t{event.y}"
            for event in self.events
        )
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")


class FakeAudioSink:
    def __init__(self) -> None:
        self.intents: list[AudioIntent] = []

    def append(self, kind: str, frequency_hz: int, level: int) -> None:
        self.intents.append(
            AudioIntent(kind=kind, frequency_hz=frequency_hz, level=level)
        )


def rgb_to_x8r8g8b8(color: tuple[int, int, int]) -> int:
    red, green, blue = color
    return (red << 16) | (green << 8) | blue


def x8r8g8b8_to_rgb(value: int) -> tuple[int, int, int]:
    return ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)


def ppm_header(width: int, height: int) -> bytes:
    return f"P6\n{width} {height}\n255\n".encode("ascii")


def pixels_to_ppm(width: int, height: int, pixels: list[int]) -> bytes:
    if len(pixels) != width * height:
        raise ValueError("pixel count does not match dimensions")
    body = bytearray()
    for value in pixels:
        body.extend(struct.pack(">I", value)[1:])
    return ppm_header(width, height) + bytes(body)
