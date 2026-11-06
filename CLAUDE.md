# CLAUDE.md

This file gives Claude Code and other coding agents the minimum operating rules
for this repository. `AGENTS.md` remains authoritative for repository mechanics.

## Mission

Maintain two visible application lanes for Juan's iPad mini 2:

1. **Stable iPadOS lane:** native, offline, touchable applications under
   `native-ipad/`, built on a Mac with Xcode.
2. **Custom Linux lane:** portable framebuffer/touch/audio applications under
   `linux-apps/`, simulated under `simulator/`, and bundled by
   `initramfs/` into the RAM-only J85 payload.

Do not collapse these lanes. iPadOS provides stability now; the Linux lane makes
the system more custom as drivers become trustworthy.

## Architecture boundaries

- Keep portable application state and rendering in `linux-apps/juan-core.c`,
  `linux-apps/hello-juan.c`, and headers under `linux-apps/include/juan/`.
- Put host-only or device-only I/O in adapters such as
  `linux-apps/linux-hello-juan.c` and `simulator/hello-sim.c`.
- Extend `simulator/fake_device.py` when a test needs a fake boundary. Do not
  make application logic simulator-aware.
- Add binaries to `linux-apps/apps.list` only when the no-hardware and initramfs
  builds both validate them.
- Treat `JuanAudioIntent` as a request. Until a verified A7 audio backend
  exists, adapters may log it but must not issue hardware register writes.

## Safety contract

- Never automate DFU entry, cable actions, USB passthrough, restore, downgrade,
  NAND/NVRAM writes, or SecureROM replacement.
- Never add arbitrary memory-read/write tooling.
- Keep RAM-only Linux nonpersistent: no block-device mounts and no persistent
  iPad storage writes.
- Keep container builds network-isolated and without USB devices.
- Hardware boot remains explicit, manually reviewed, and normally run by Juan
  with `sudo scripts/lab.sh boot --approve`.
- Do not ask for or store Juan's sudo password.
- Never commit Apple firmware, IPSWs, signing material, provisioning profiles,
  credentials, generated `build/` output, or copyrighted media.
- Redact UDIDs, ECIDs, serial numbers, and other unique device identifiers
  before committing or publishing notes.

## Normal workflow

Use the no-hardware gate before review:

```bash
bash scripts/lab.sh test
```

For the complete local payload build (still no USB):

```bash
bash scripts/lab.sh build
```

Hardware-only commands are never part of autonomous completion:

```bash
sudo scripts/lab.sh boot --approve
scripts/lab.sh touch-report
```

If a hardware result is needed, prepare a read-only command, explain the exact
effect, and wait for explicit user approval.

## Coding and review expectations

- Preserve surrounding style: four spaces in C/Objective-C/Python and aligned
  two-space shell continuations.
- Use POSIX-safe shell with `set -euo pipefail` where practical.
- Treat compiler warnings as errors in supplied C paths.
- Every change should state which no-hardware command proved it and which
  physical-device behavior remains unverified.
- Device-visible behavior must be documented in the relevant README or dated
  note.

## Publishing

This repository is intended to be public and reproducible. Before publishing,
check `git status`, scan tracked files for unique identifiers and credentials,
and confirm no ignored media or firmware artifact was accidentally added.
