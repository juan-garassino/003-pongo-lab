# J85 touch and movie-lane plan

Date: 2026-11-06

## Verified baseline

The J85 RAM-only path is already working from manual DFU through Hoolock Pongo,
m1n1, Linux, USB serial, USB networking, framebuffer, physical buttons, and the
fullscreen touch-test application. The next hardware blocker is the Apple Z2
touch-controller probe: Linux registers `iPad mini 2 Touchscreen`, but the
controller times out during pre-firmware bring-up with error `-110`.

The previous assumption that live calibration was absent is incorrect. Although
the static Apple ADT string is `syscfg/MtCl/0x400,zeroes/0x400`, the live Linux
device-tree probe found a real 1,024-byte `apple,z2-cal-blob`. Calibration is
therefore not the current blocker. The remaining suspects are touch power rails,
the 32.768 kHz touch clock, reset sequencing, and the pre-firmware SPI exchange.

## Corellium reference sequence

The public Corellium Sandcastle kernel and user daemon provide the best known
working sequence:

1. assert reset;
2. enable `hv-supply`;
3. wait 2–5 ms;
4. enable `core-supply`;
5. wait 2–5 ms;
6. deassert chip select;
7. enable the touch clock;
8. wait 1–2 ms;
9. enable IRQ;
10. issue one reset pulse;
11. exchange a four-byte zero command over SPI;
12. reinitialize the IRQ completion;
13. issue a second reset pulse;
14. wait up to 500 ms for boot IRQ;
15. perform another four-byte zero exchange;
16. upload firmware with explicit chip-select boundaries;
17. mark the controller ready.

References:

- Corellium `hx-touch.c`:
  <https://github.com/corellium/linux-sandcastle/blob/sandcastle-5.4/drivers/input/touchscreen/hx-touch.c>
- Corellium `hx-touchd.c`:
  <https://github.com/corellium/projectsandcastle/blob/master/hx-touchd/hx-touchd.c>

The A10 DTS cannot be copied directly to A7. In particular, its PMU register
masks belong to a different PMU. The captured J85 ADT identifies the touch power
functions as D2089 selectors 525 and 529, while its touch clock is the
`grape-clk` 32,768 Hz output. Exact A7 masks and enable values remain unknown.

## Safe bring-up phases

### Phase C — diagnostic-only reset/handshake

Implement and locally build the subset that cannot change persistent state:

- identify the J85 Gen-1 path;
- log and count IRQ activity;
- issue two explicit reset pulses;
- perform the four-byte full-duplex zero exchange;
- log received bytes and timeout state;
- leave PMU and clock registers untouched.

This phase changes only volatile peripheral state during Linux probe.

### Phase D — one approved hardware observation

After explicit approval, boot the diagnostic payload and collect read-only
evidence with `scripts/lab.sh touch-report`: input devices, interrupts, relevant
kernel logs, device-tree properties, GPIO state, and a five-second bounded
`/dev/input/event0` read. If IRQ still never arrives, power and clock are the
primary remaining suspects.

### Phase E — J85 PMU/clock model

Only after source evidence establishes the exact D2089 semantics:

1. represent selectors 525 and 529 as volatile RAM-only regulators;
2. use read-modify-write only with verified masks;
3. model `grape-clk` at 32,768 Hz;
4. attach them as J85 `hv-supply`, `core-supply`, and touch clock;
5. request another explicit hardware review before boot.

Do not copy A10 masks, write NAND/NVRAM, or introduce persistence.

## Movie lane

The first visible/audio milestone is deliberately independent of custom Linux
audio drivers. A user-supplied, legally accessible movie can be transcoded on
the laptop into iPad-compatible H.264/AAC HLS and opened in iPad Safari over the
same Wi-Fi network:

```bash
scripts/serve-movie.sh /path/to/movie-you-may-legally-view.mp4
```

The generated player fills the browser viewport, preserves aspect ratio, and
uses HLS with AAC audio. Generated media is written only under ignored
`build/movie-lane/`. The repository neither downloads nor commits a copyrighted
film.

The lane is locally tested with generated SMPTE bars and a tone:

```bash
scripts/test-movie-lane.sh
```

This confirms Safari-compatible media packaging, but does not test the Linux
audio driver. A later juanOS milestone should first identify and enable the A7
audio path, then use this same HLS asset as a hardware playback test.
