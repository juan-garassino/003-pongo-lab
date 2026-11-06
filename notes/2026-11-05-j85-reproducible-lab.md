# J85 reproducible RAM-only Linux lab

Date: 2026-11-05

## Result

The complete local J85 build is now packaged behind one command:

```bash
scripts/lab.sh build
```

It:

1. builds the pinned m1n1/Linux research container;
2. builds m1n1 `d5a10ac5`;
3. builds the Hoolock Linux `6831bc70` kernel with A7 4K pages;
4. builds the J85 DTB and RAM-only BusyBox initramfs;
5. packages `build/m1n1-j85-ram-only.bin`;
6. runs all local no-hardware tests;
7. verifies the artifact manifest.

No USB device is opened by the build.

The guided hardware path is:

```bash
scripts/lab.sh boot --approve
```

It prepares host USB services, prompts for **manual** DFU entry, boots Hoolock
Pongo, uploads the payload, sends `bootm`, and waits for the Linux USB gadget.
It does not automate DFU, restore, downgrade, or persistent storage writes.

## Current verified artifacts

```text
m1n1:
  43e957944fa0e85aa7f60920b6b5d7908f2a0dd58fe838422b2b8d51eaa7fc44

J85 DTB:
  1a7f91129027b7f2d1080fa5be12e3f1555088d2a5464f6156a7b633edc659ae

Image.gz:
  3c04bcb5adab55bb2b30b7d0080a424b4a3f8bb83accf30022204140add4c3ec

initramfs.gz:
  5cb3c7ca6f8a56990d1b7d57358b7c3ddb2153705d049addb77845e49b733aff

combined payload:
  92564fcbfe72083e01e6380a2486843dedb285c9028ef389bf290e11fd6ab35e
```

The manifest is:

```text
build/linux-j85/manifest.sha256
```

## Touch diagnostic payload

The local payload now enables:

```text
CONFIG_ARM64_4K_PAGES=y
CONFIG_INPUT_TOUCHSCREEN=y
CONFIG_TOUCHSCREEN_APPLE_Z2=y
```

It also contains:

- the A7 SPI1 controller node;
- the J85 multitouch child with reset GPIO 23, interrupt GPIO 15, and 5 MHz SPI clock;
- SPI chip-select GPIO 71 with conservative setup/hold delays;
- a `touchscreen0` alias scoped to the mini 2 board so other A7 DTBs remain valid;
- the Apple Z2 Gen-1 upload sequence for J85;
- the exact 57,192-byte J85 multitouch firmware in `/lib/firmware/apple/`.

The initramfs also contains a static AArch64 `/bin/touch-test`. After USB setup, it
replaces the diagnostic text page with a complete 1536×2048 canvas containing four
touch zones, per-finger crosshairs, and a tap-count strip. It writes only to the RAM
framebuffer and reads evdev; it does not open storage.

The build verifies the DT compatible string and confirms the firmware survives
initramfs extraction. This is local verification only; no touch input has yet been
observed on the iPad.

The captured static Apple ADT reports this calibration property:

```text
multi-touch-calibration = "syscfg/MtCl/0x400,zeroes/0x400"
```

That is a SysCfg reference, not itself the resolved binary blob. The m1n1 patch
therefore refuses to forward ASCII `syscfg/` bytes as binary calibration. A later
hardware report corrected the runtime picture: the live Linux device tree did
contain a real 1,024-byte `apple,z2-cal-blob`. Calibration is present and is not
the current touch blocker.

Filtered, read-only iPadOS telemetry can be collected after returning to iPadOS:

```bash
scripts/lab.sh ios-telemetry
```

## Reports

A live Linux session can be captured with:

```bash
scripts/lab.sh report
```

Reports are written under `notes/` and include kernel identity, boot arguments,
memory, CPU, framebuffer, input devices, USB bring-up diagnostics, network,
device-tree identity, platform devices, partitions, mounts, and recent kernel log.
