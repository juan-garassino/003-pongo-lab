# iPad mini 2 manual PongoOS test

This checklist is intentionally manual. Do not automate DFU entry, USB device
selection, restore, downgrade, or module loading. Only Juan should connect or
disconnect the iPad.

## Preconditions

1. Confirm the iPad is the recorded `iPad4,4` device in `notes/device.md`.
2. Build from the repository root with `bash scripts/build-container.sh`.
3. Record artifact hashes with:

   ```bash
   sha256sum src/pongoOS/build/Pongo.bin modules/hello-juan/build/hello-juan
   ```

4. Ensure `pyusb` is available to the A7 and upstream helper scripts.
5. Use only plain `Pongo.bin`; do not use `PongoConsolidated.bin` for this test.
6. Build and inspect the explicit A7 boot plan without communicating with the
   iPad:

   ```bash
   bash scripts/build-pongo-a7.sh
   scripts/boot_pongo_a7.py --dry-run
   ```

   The dry run must report the recorded `Pongo.bin` SHA-256 and no USB command.

## Manual boot and module load

1. Put the iPad into DFU mode using the device-specific upstream checkra1n
   instructions. Do not run a restore or downgrade.
2. Confirm DFU before running the exploit:

   ```bash
   lsusb | grep -i '05ac:1227'
   ```

   The screen must remain black. A recovery icon, Apple logo, or lock screen
   means the attempt must start over.
3. Pwn DFU explicitly with the absolute `gaster` path:

   ```bash
   sudo env USB_TIMEOUT=30 \
     /home/garassino-juan/Code/007-sandbox/003-pongo-lab/src/hoolock/gaster/gaster pwn
   ```

   When the A7 output says `Unplug and replug the device now (at least 2
   times)`, disconnect and reconnect the USB cable twice, pausing briefly
   between replugs. Do not press the iPad buttons. Success is:
   `Now you can boot untrusted images.` The USB ID normally remains
   `05ac:1227`.
4. Confirm `lsusb` still shows exactly one pwned `05ac:1227` device, then run
   the explicit bounded copy/execute path:

   ```bash
   sudo /home/garassino-juan/Code/007-sandbox/003-pongo-lab/.venv/bin/python \
     /home/garassino-juan/Code/007-sandbox/003-pongo-lab/scripts/boot_pongo_a7.py \
     /home/garassino-juan/Code/007-sandbox/003-pongo-lab/src/pongoOS/build/Pongo.bin \
     --trampoline \
       /home/garassino-juan/Code/007-sandbox/003-pongo-lab/build/Pongo.a7.trampoline.bin \
     --execute
   ```

   This sends one bounded `MEMC` copy request per 0x400-byte image chunk, one
   trampoline copy request, and one execution request. It does not use
   `readmem`, `writemem`, restore, downgrade, or persistent-storage commands.
   PongoOS should then re-enumerate as `05ac:4141`; the helper also waits for
   that ID. Verify independently with:

   ```bash
   lsusb | grep -i '05ac:4141'
   ```

5. Confirm the Pongo shell responds before loading custom code.
6. Load the diagnostic module explicitly:

   ```bash
   sudo /home/garassino-juan/Code/007-sandbox/003-pongo-lab/.venv/bin/python \
     /home/garassino-juan/Code/007-sandbox/003-pongo-lab/src/pongoOS/scripts/module_load.py \
     /home/garassino-juan/Code/007-sandbox/003-pongo-lab/modules/hello-juan/build/hello-juan
   ```

7. Run the first read-only module command:

   ```bash
   sudo /home/garassino-juan/Code/007-sandbox/003-pongo-lab/.venv/bin/python \
     /home/garassino-juan/Code/007-sandbox/003-pongo-lab/src/pongoOS/scripts/issue_cmd.py \
     'juan help'
   sudo /home/garassino-juan/Code/007-sandbox/003-pongo-lab/.venv/bin/python \
     /home/garassino-juan/Code/007-sandbox/003-pongo-lab/src/pongoOS/scripts/fetch_stdout.py
   ```

## Read-only commands

Run each command separately with
`python3 src/pongoOS/scripts/issue_cmd.py '<command>'`, then retrieve and save
the output:

- `juan help`
- `juan info`
- `juan bootargs`
- `juan display`
- `juan dt /`
- `juan dt arm-io`
- `juan dt arm-io compatible`
- `juan dt chosen`
- `juan dt chosen firmware-version`

Record the exact responses in a dated note under `notes/`. If a node is absent,
the module should print a readable `Node not found` message; that result is
still useful. Property output is capped at 64 bytes.

## Pass criteria

- The preboot hook message appears without a panic or watchdog reset.
- All `info`, `bootargs`, and `display` fields print sensibly.
- Memory and framebuffer geometry are plausible for an iPad mini 2.
- Device-tree lookups return either valid bounded data or readable errors.
- No command writes storage, registers, clock state, power state, or pixels.

If the device resets, disconnect it and preserve the last captured output before
trying anything else. Do not retry repeatedly or change the payload until the
failure is understood.
