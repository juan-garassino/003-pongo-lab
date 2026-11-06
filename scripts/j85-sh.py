#!/usr/bin/env python3
"""Run one shell command on the iPad's Linux over its USB serial port."""
from __future__ import annotations

import argparse
import glob
import os
import re
import secrets
import select
import sys
import termios
import time
import tty

VENDOR = "1d6b"
PRODUCT = "0104"
PROBE_INTERVAL = 1.0
DENIED = re.compile(
    r"\b(hwclock|ntpd|ntpdate|devmem|mkfs\S*|fdisk|reboot|poweroff|halt|flash_\w+)\b"
    r"|/dev/watchdog|/sys/power/|nvmem"
)


def find_port() -> str:
    for tty_path in sorted(glob.glob("/sys/class/tty/ttyACM*")):
        path = os.path.realpath(os.path.join(tty_path, "device"))
        while path != "/":
            try:
                with open(os.path.join(path, "idVendor")) as handle:
                    vendor = handle.read().strip()
                with open(os.path.join(path, "idProduct")) as handle:
                    product = handle.read().strip()
            except OSError:
                path = os.path.dirname(path)
                continue
            if (vendor, product) == (VENDOR, PRODUCT):
                return "/dev/" + os.path.basename(tty_path)
            break
    raise SystemExit(f"no {VENDOR}:{PRODUCT} serial port found; is the iPad's Linux up?")


class Session:
    def __init__(self, fd: int) -> None:
        self.fd = fd
        self.buffer = b""

    def send(self, text: str) -> None:
        os.write(self.fd, text.encode())

    def wait_for(self, pattern: re.Pattern[bytes], deadline: float) -> re.Match[bytes] | None:
        while True:
            match = pattern.search(self.buffer)
            if match:
                return match
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return None
            ready, _, _ = select.select([self.fd], [], [], remaining)
            if ready:
                try:
                    self.buffer += os.read(self.fd, 65536)
                except OSError as error:
                    raise SystemExit(f"serial port read failed: {error}") from error


def run(port: str, command: str, timeout: float) -> int:
    token = secrets.token_hex(6)
    deadline = time.monotonic() + timeout
    # Quotes split each marker so the tty's echo of the command can never match.
    ready = re.compile(f"J85_RDY_{token}".encode())
    result = re.compile(f"J85_BEG_{token}\r?\n(.*?)J85_END_{token} (\\d+)\r?\n".encode(), re.DOTALL)

    fd = os.open(port, os.O_RDWR | os.O_NOCTTY)
    try:
        tty.setraw(fd, termios.TCSANOW)
        session = Session(fd)
        session.send("\n")
        while True:
            session.send(f"echo J85_RDY_''{token}\n")
            if session.wait_for(ready, min(time.monotonic() + PROBE_INTERVAL, deadline)):
                break
            if time.monotonic() >= deadline:
                print("timed out waiting for the shell", file=sys.stderr)
                return 124

        session.buffer = b""
        session.send(
            f"printf 'J85_BEG_''{token}\\n'; ( {command}\n) 2>&1; "
            f"printf '\\nJ85_END_''{token} %s\\n' \"$?\"\n"
        )
        match = session.wait_for(result, deadline)
    finally:
        os.close(fd)

    if not match:
        print("timed out waiting for the command", file=sys.stderr)
        sys.stderr.write(session.buffer.decode("utf-8", "replace"))
        return 124
    output = match.group(1).replace(b"\r\n", b"\n").strip(b"\n")
    if output:
        sys.stdout.write(output.decode("utf-8", "replace") + "\n")
    return int(match.group(2))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command")
    parser.add_argument("--port", help="serial device (default: find the iPad)")
    parser.add_argument("--timeout", type=float, default=30.0)
    args = parser.parse_args()

    if DENIED.search(args.command):
        print(f"Refusing a command that may change persistent device state: {args.command}", file=sys.stderr)
        return 2
    return run(args.port or find_port(), args.command, args.timeout)


if __name__ == "__main__":
    sys.exit(main())
