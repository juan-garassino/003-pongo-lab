# A7 gaster copy/execute path

Date: 2026-11-04

## Continuation from the handoff

The handoff ruled out another blind DFU upload. I compared the local custom
request handler with the local `openra1n` Pongo booter and implemented the
bounded upload/copy/execute route requested there.

Relevant local interfaces:

- `src/hoolock/gaster/payload_handle_checkm8_request.S`
  - `MEMC` request: `{ magic, pad, dst, src, len }`, followed by source bytes.
  - `EXEC` request: `{ magic, func, x[0] ... x[7] }`.
  - `EXEC` can initialize `x0` through `x7`, but `x8` contains the called
    function address when the handler reaches the trampoline.
- `src/hoolock/gaster/gaster.c`
  - A7 `iBoot-1704.10` command buffer: `0x180380000`.
  - A7 gaster DFU transfer size: `0x800`, including the final 16-byte suffix.
  - `dfu_send_data()` finishes with manifest-state polls before the custom
    `0xa1 / request 2 / wValue 0xffff` response request.
- `src/pongoOS/src/boot/entry.S`
  - Pongo consumes incoming boot arguments through `x8`.
  - A low Pongo image copies its 2 MiB window to `0x180180000` and returns;
    the relocated entry at `0x180180000` then continues normally.
- `/tmp/openra1n/payloads/shellcode.bin`
  - The known booter copies/decompresses Pongo, cleans cache, disables SCTLR,
    and enters Pongo with its original argument register preserved.
  - It also preserves the DFU image caller's `x30`; Pongo's low copy returns
    through that register into its relocated image.

## Implementation

New `scripts/boot_pongo_a7.py` is dry-run by default. `--execute` is the only
mode that opens USB. It refuses multiple DFU devices and requires the serial to
contain both ` SRTG:[iBoot-1704.10]` and ` PWND:[gaster]`.

The hardware path is bounded and explicit:

1. Send `0x400` image bytes per gaster `MEMC` request from command-buffer
   offset `0x28` to `0x180000000 + image_offset`.
2. Copy the 168-byte `scripts/pongo_a7_trampoline.S` binary to
   `0x180380100`.
3. Issue one `EXEC` request for that trampoline.
4. The trampoline:
   - sets Pongo's incoming `x8` boot-argument register to zero;
  - preserves the known booter's Pongo base in `x18`;
   - zeroes the low image tail through the 2 MiB copy-window end;
   - cleans/invalidates the copied window;
   - disables SCTLR for the current exception level;
   - calls the low Pongo copy entry;
   - re-sets `x8`/`x18` and explicitly branches to the relocated Pongo entry,
    supplying the same effect as the known booter's preserved high-address `x30`.
5. Treat execution-request non-return as expected and wait for `05ac:4141`.

The script does not pwn DFU, send cable actions, invoke `irecovery`, or use
gaster `readmem`/`writemem`.

## Local verification only

Commands run:

```bash
python3 -m py_compile scripts/boot_pongo_a7.py
bash -n scripts/build-pongo-a7.sh
bash scripts/build-pongo-a7.sh
scripts/boot_pongo_a7.py --dry-run
```

Current artifacts:

- `src/pongoOS/build/Pongo.bin`
  - 675936 bytes
  - SHA-256 `c580b3179f312770a8ccdf0b93ee70d59ab8db7acd89ad3d42a02f8e058157e8`
- `build/Pongo.a7.trampoline.bin`
  - 168 bytes
  - SHA-256 `53a391646e21655704578989557185ab81bc8556f00d9c4481cedaef5473d430`

The dry run plans 661 image-copy commands plus trampoline copy and execute.
No iPad command was issued while implementing this path.

## Device gate

### Approved first execution attempt

Juan approved the first `--execute` attempt on 2026-11-04. A `sudo` invocation
could not authenticate through the tool PTY, so the approved helper was run
directly; PyUSB had sufficient host access.

Observed serial:

```text
CPID:8960 CPRV:11 CPFM:03 SCEP:01 BDID:0A ECID:<redacted> IBFL:1C
SRTG:[iBoot-1704.10] PWND:[gaster]
```

The helper opened the correct pwned A7 DFU device, accepted the first
`0x400`-byte MEMC download, and completed all three expected DFU manifest state
polls. The custom `0xa1 / request 2 / wValue 0xffff` response then timed out.
The helper stopped at command `1/661`; it did not execute the trampoline or
Pongo. `lsusb` still reported exactly one `05ac:1227` DFU device and no
`05ac:4141` device.

Interpretation: normal DFU download still works and the pwned serial marker is
present, but there is no confirmation that the A7 custom request handler copied
the chunk. This may be a handler-state, request-size, or protocol-trigger
mismatch. Do not blind-retry. The next diagnostic should be a separately
reviewable tiny same-buffer MEMC command before another Pongo destination write.

### Follow-up diagnosis on 2026-11-04

The initial hypothesis that the vendored Hoolock gaster predates the upstream
2023-01-17 A7 fix is false:

- Hoolock commit `2b9d747f2367f8c0860def02ec4fd299e531c52a` includes LukeZGD's
  A7 payload and Linux replug guidance.
- `payload_A7.S` zeroes `dfu_handle_bus_reset` before installing the custom
  `dfu_handle_request` callback.
- The A7 values use `insecure_memory_base = 0x180380000`, matching the helper.
- The Hoolock Linux `remote_boot` project pins this exact gaster revision.

The helper's request layout, DFU termination sequence, and custom response
request match `gaster_command()` and `dfu_send_data()`. The remaining useful
split is therefore between an absent/unresponsive installed handler and a
command-specific failure.

Added `scripts/gaster_a7_request_diagnostic.py` for that split. It is dry-run
by default and `--execute` performs only two bounded requests:

1. a 16-byte custom IN request that reads gaster's own command buffer and
   writes nothing;
2. one `MEMC` copy of the 8-byte value `A7DIAG\0\0` from `0x180380028` to
   `0x180380100`.

It performs no arbitrary-memory read, no write outside gaster's command buffer,
no code execution, no Pongo transfer, and no storage/register operation.
Offline checks passed:

```bash
python3 -m py_compile scripts/gaster_a7_request_diagnostic.py
scripts/gaster_a7_request_diagnostic.py
```

Juan subsequently approved continuing with bounded, safe steps. The diagnostic
found exactly one matching pwned A7 DFU device, but the first no-write custom
request timed out:

```text
custom-request preflight failed before any diagnostic write:
[Errno 110] Operation timed out
```

This is stronger than the earlier MEMC result: the custom request handler is
absent or unresponsive before any diagnostic write, so the failure is no longer
consistent with a malformed `MEMC` header or destination address. The PWND serial
marker remains insufficient evidence that the custom request callback survived
the later Linux USB reset/replug sequence.

## Immediate post-patch preflight tooling

To distinguish a callback that was never installed from one that was lost across
reset/replug or process teardown, the vendored gaster source now has a bounded
`a7-preflight` mode. The mode:

- accepts only CPID `0x8960`;
- refuses an already-`PWND` device because that cannot reinstall the callback;
- aborts after any failed checkm8 stage instead of looping;
- after one successful A7 patch, issues only the existing 16-byte custom IN
  request;
- performs no `MEMC`, `EXEC`, Pongo transfer, arbitrary read/write, storage
  operation, or USB reset;
- closes the USB handle and stops immediately after recording the result.

`scripts/build-gaster-a7-preflight.sh` builds the diagnostic binary without
changing the pinned upstream payload binaries. Local verification passed:

```bash
bash -n scripts/build-gaster-a7-preflight.sh
scripts/build-gaster-a7-preflight.sh
build/gaster-a7-preflight
```

Artifact:

- `build/gaster-a7-preflight`
  - SHA-256 `21126962f48e05321bbafe3e1be134ff58d41d1a3d1162a21233d8f7d8cea039`

No iPad command was issued while adding or building this diagnostic. Running it
requires a fresh, unpwned A7 DFU cycle and explicit approval. If the immediate
request succeeds, the next bounded check is the already-approved no-write Python
preflight in a separate process, which tests whether the callback survives handle
close/reopen. Only after both checks succeed should the same-buffer `MEMC`
diagnostic resume.

`scripts/gaster_a7_request_diagnostic.py` now supports `--no-write-only`, so
that separate-process survival test cannot accidentally continue into `MEMC`.
Its dry run and Python compilation were rechecked; no USB command was sent.
Current SHA-256:

```text
63f6d06c210ea2e12208809a5ec10d52e9bccb9262f5928fc2d6dedd5a4ad401
```

### Approved immediate-preflight result

Juan manually returned the iPad to fresh DFU. A read-only serial check confirmed
the correct A7 iBoot build with no `PWND` marker. Juan then approved:

```bash
USB_TIMEOUT=5000 USB_ABORT_TIMEOUT_MIN=0 \
  build/gaster-a7-preflight a7-preflight
```

The RESET, SETUP, SPRAY, and PATCH stages all returned success. The immediate
16-byte custom IN request timed out, and the diagnostic stopped as designed
without issuing a USB reset. `lsusb` still showed exactly one `05ac:1227` DFU
device and no `05ac:4141` device.

This proves the custom request is not responsive in the pre-reset, immediately
post-patch state. It does not by itself prove that A7 handler installation
failed permanently: upstream gaster explicitly instructs Linux users to reset
and unplug/replug an A7 at least twice after PATCH before using the interface.
The next useful bounded observation is a read-only serial check of this
post-patch/pre-reset state, followed only if necessary by the documented normal
A7 reset/replug sequence and another no-write request.

The post-patch serial-string check could not obtain a language ID. Juan then
approved a normal DFU reset. That command did not return, the iPad left DFU and
enumerated normally as `05ac:12ab`; the host-side waiting process was
interrupted without sending another device command. This state requires a fresh
DFU cycle. For the next cycle, use stock gaster `pwn` so PATCH performs its own
USB reset before the documented two physical unplug/replug cycles, rather than
using the deliberately reset-free immediate-preflight mode.

### Successful stock A7 pwn cycle

Juan manually returned the iPad to fresh DFU and ran stock gaster `pwn` in a
visible terminal. After the instructed A7 unplug/replug cycles, gaster completed
and the device returned to DFU with `PWND:[gaster]`.

The separate-process no-write custom-request check then succeeded:

```text
preflight command-buffer response: fd7bbfa960058820600585f0000f9
no-write mode: MEMC diagnostic skipped
```

This resolves the previous interface blocker: after the complete documented A7
reset/replug sequence, the custom request handler is present and responsive.
The immediate pre-reset timeout was therefore an expected consequence of
testing before the required A7 post-patch sequence, not evidence that the
handler installation was broken.

Juan then approved the same-buffer `MEMC` diagnostic. It succeeded:

```text
same-buffer MEMC response: done=0x646f6e65646f6e65 return=0x180380100
A7 gaster custom-request interface is responsive.
```

`scripts/boot_pongo_a7.py` now supports `--image-copy-limit N`. With a nonzero
limit it sends only the first N image `MEMC` commands and explicitly stops before
trampoline copy or `EXEC`. This provides the next gated test: copy exactly one
`0x400`-byte Pongo chunk to `0x180000000`. The full and one-command dry runs and
Python compilation passed; current helper SHA-256:

```text
41b3b476caa34b3b6eabfcff11180eca9139d076f1cbdd9ef166d72b9e7392ad
```

Juan approved that one-command staged copy. It opened the correct pwned A7 DFU
device, copied Pongo bytes `0x000000..0x000400` to `0x180000000`, received the
expected `DONE_MAGIC` response, and stopped without the trampoline or `EXEC`.
The device remained in DFU as `05ac:1227`.

### Full MEMC transfer result

Juan approved the full 661-command transfer. Commands 1 through 512 succeeded,
covering Pongo offsets `0x000000..0x080000`. Command 513 timed out while sending
its DFU download, before that chunk's `MEMC` request could execute. The device
remained in DFU as `05ac:1227`; no trampoline or `EXEC` was sent.

The boundary is exact: 512 commands at `0x400` bytes each total `0x80000`, the
known A7 DFU transfer limit. This independently matches the earlier direct-upload
failure near 77.6% and explains why the uncompressed 661-command route cannot
continue through the normal DFU engine. The correct A7 strategy is the existing
LZ4 loader, whose complete wrapped image is only 337954 bytes.

The current Pongo LZ4 wrapper was rebuilt and round-trip verified:

- `build/Pongo.a7.dfu.bin`
  - 337954 bytes
  - SHA-256 `c66879682e09308f414612f04b46b188463d1fd84af7c09f18cbbabe34bd87e0`

`scripts/upload_dfu_a7.py` was tightened to be dry-run by default, require exactly
one recorded pwned A7 DFU device, validate the wrapper's embedded compressed size,
treat a post-upload `DFU_CLEAR_STATUS` stall/error as non-fatal like upstream
openra1n, and only then wait for `05ac:4141`. Its syntax and dry-run checks passed.

Juan approved the wrapped-image boot, but the attempt stopped before sending any
wrapper data: the device no longer returned a USB string-descriptor language ID.
`lsusb` still showed `05ac:1227`. This is consistent with the preceding low-memory
uncompressed copy having damaged live DFU state before command 513 timed out. Do
not bypass serial validation or blind-send the wrapper to this session. Recover
with a fresh DFU entry, the stock gaster A7 pwn flow, and its documented two
unplug/replug cycles before retrying the already-approved wrapped image.

### Clean-session wrapped-upload result

Juan completed another fresh DFU cycle and stock gaster A7 pwn flow. The serial
again identified the correct `PWND:[gaster]` device. The 337954-byte wrapper then
uploaded successfully through all 166 DFU blocks. `DFU_CLEAR_STATUS` returned an
Input/Output Error, and the device re-enumerated as `05ac:1227` rather than
`05ac:4141`.

Source comparison explains this result: openra1n's automatic wrapper execution is
tied to its separate `yolo` stage-two payloads. Hoolock gaster instead installs
the A7 custom request interface used by `MEMC` and `EXEC`; it does not provide
that automatic normal-DFU execution hook. Therefore a complete upload alone is
expected to remain in DFU under Hoolock gaster.

The bounded route is to stage the same relocatable LZ4 wrapper at
`0x180200000` using `MEMC`, then issue one explicit `EXEC` for a small register
trampoline. That staging range is outside gaster's command buffer, the live DFU
globals, and Pongo's decompression destination. New files implement this path:

- `scripts/pongo_a7_lz4_trampoline.S`
- `scripts/boot_pongo_a7_staged.py`

The staged trampoline is 80 bytes, the complete staged image is 338466 bytes,
and the plan uses 331 bounded `MEMC` commands followed by one `EXEC`. The script
is dry-run by default and all local build/syntax checks passed. Relevant hashes:

```text
scripts/boot_pongo_a7_staged.py
701bba7e93ef1c2236a70df5666fddf2cc19315737fe7a23378111cd4bd89fcb

build/Pongo.a7.lz4.trampoline.bin
4f4f8e30d6b179cda6afe2ce7b8627c3b562d5878e9784de97c127480d29d85f

build/Pongo.a7.dfu.bin
c66879682e09308f414612f04b46b188463d1fd84af7c09f18cbbabe34bd87e0
```

Juan approved a no-write custom-request check after the normal DFU wrapper
upload. The serial still identified the correct pwned A7, but the custom request
timed out. Thus the wrapper upload left the DFU serial marker intact but replaced
or displaced the live custom request command buffer. A fresh stock gaster
pwn/replug cycle is required before the staged `MEMC`/`EXEC` route; do not send
that route to the current session.

Juan then completed another fresh DFU cycle and stock gaster A7 pwn/replug
sequence. `lsusb` showed exactly one `05ac:1227`, and the no-write custom-request
gate succeeded again with the expected command-buffer bytes. The device is ready
for the staged `MEMC`/`EXEC` route, subject to explicit approval.

### First staged LZ4 execution result

Juan ran the staged route after approval. All 331 `MEMC` commands succeeded, the
80-byte trampoline was executed, but `05ac:4141` did not appear within 30 seconds.
The device remained at the same DFU enumeration. This proved that staging outside
the DFU transfer limit works; the remaining failure was in the loader itself.

Disassembly of openra1n's shellcode found the precise mismatch. Its loader hard
codes a `0x7fe00`-byte decompression capacity, while the current Pongo image is
`0xa5060` bytes:

```text
loader capacity: 0x7fe00 = 523776 bytes
Pongo image:     0xa5060 = 675936 bytes
```

An offline `LZ4_decompress_safe` check confirmed that the wrapped stream fails at
the old capacity and round-trips exactly at a two-MiB capacity:

```text
capacity 0x7fe00: failure
capacity 0x200000: returns 0xa5060 and matches Pongo.bin byte-for-byte
```

`scripts/prepare_staged_pongo_wrapper.py` now creates
`build/Pongo.a7.staged.dfu.bin` by changing only the loader capacity instruction
from `0x7fe00` to `0x200000`. The staged boot helper rejects the unpatched normal
DFU wrapper. Local syntax, build, dry-run, patch validation, and negative-check
tests passed. Current hashes:

```text
scripts/prepare_staged_pongo_wrapper.py
9e936c2fefdc767adc6521e011b7d9491dc4b2b8ffa9fb6bd79104e5270cb9f7

scripts/boot_pongo_a7_staged.py
6f9beeba6a2a1af343ec41744124009f9864a4f3269f9e753d546a7e328d40e3

build/Pongo.a7.staged.dfu.bin
08cdfdc2147bd5e1438778f39470c9e2c06ef55872c40a271c4a884a72430c74
```

Juan returned through Recovery Mode, re-entered fresh DFU, and ran stock gaster
again. Only one physical replug was needed for that enumeration. The serial
identified the correct `PWND:[gaster]` device, and the no-write custom-request
gate succeeded with the expected command-buffer bytes, confirming that this
session is ready for the corrected two-MiB staged loader.

### Corrected staged execution result

Juan ran the corrected two-MiB staged loader after approval. All 331 `MEMC`
commands succeeded and the trampoline executed, but `05ac:4141` was not observed
during the helper's 30-second window. The device then enumerated stably as the
normal iPad product `05ac:12ab`; a further 30 seconds of read-only USB polling
showed no transition to `05ac:4141`. This indicates that execution advanced far
enough to leave DFU but Pongo did not retain control of USB. The current prime
suspect is the incoming Pongo argument contract: the staged trampoline currently
zeroes both `x0` and `x8`, while openra1n's shellcode preserves its caller `x0`
for Pongo. Do not retry until that register contract is reconciled with a known
A7 boot path.

### Source-consistent pivot to the known A7 Pongo path

The staged custom-`EXEC` route is now locally diagnosed rather than transfer-bound:
the vendored 2.5.1 Pongo entry consumes a boot-image pointer in `x8`, but the
openra1n loader follows the newer 2.6 ABI in which `x30` is the next-stage image
and `x0` is its argument. Calling that loader through gaster's custom `EXEC`
handler cannot reconstruct those original SecureROM arguments; zeroing them makes
the old Pongo dereference a null boot image. Another staged attempt would only
repeat this failure.

Hoolock's Linux A7 documentation instead uses palera1n/checkra1n to boot Pongo,
and palera1n's `-p -k Pongo.bin` mode stops at a clean Pongo shell. This path
uses checkra1n's tested handoff rather than our synthetic register contract.
The following locally prepared, network-only artifacts were recorded without
opening USB:

```text
build/Pongo.2.6.2-d068ec60.bin
  254224 bytes
  SHA-256 c0dcc468ea3e5aff09933aed2963b88d39f12dc4a7a661148ec277eab5961fb6

build/hello-juan.2.6.2-d068ec60
  67000 bytes
  SHA-256 c4afaff3a31c9dcd41b95a8c2da332960768a58cd6ae9dd6213fd7a62ee72da5

build/palera1n/palera1n-v2.1-beta.2
  5139072 bytes
  SHA-256 d0ba1cc315523703a7f61e6ba6687ee166e7ac319d36f71b1e79f273180d0738
```

The module was compiled in the pinned network-isolated container against the
exact Pongo source commit `d068ec602bd039feb5f38b8c70e4bbf6272a2fdb` and stripped.
The resulting module retains legacy `_dt_parse`/`_dt_prop` imports; both names
are present in the selected Pongo payload alongside the 64-bit variants. The
palera1n binary identifies itself as v2.1-beta.2, embeds checkra1n 0.1337.3,
and uses libusb. Running its `--help` and `--version` did not open the iPad.

The next hardware attempt should therefore be one explicitly approved
`palera1n --cli -p -k build/Pongo.2.6.2-d068ec60.bin` cycle, followed by the
existing read-only Pongo shell/module helpers. Do not combine that cycle with
restore, downgrade, storage writes, or the staged gaster `EXEC` route.
