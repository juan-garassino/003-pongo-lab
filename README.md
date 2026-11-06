# 003-pongo-lab

Brings Juan's iPad mini 2 (A7) back to life with Linux, booted from RAM. Builds
PongoOS, the checkra1n pre-boot environment, plus a read-only diagnostic module that
registers a `juan` console command, and a Hoolock Linux kernel with our own initramfs.

## Layout

```
src/pongoOS/             vendored upstream source; Newlib is pinned but not in Git
modules/hello-juan/       our custom module
initramfs/init            first program Linux runs; initramfs/test_init.sh tests it
initramfs/touch-test.c    fullscreen RAM-only touch canvas and input-event reader
linux-apps/               portable RAM-only Linux application core and adapters
simulator/                fake framebuffer/touch/audio boundary for no-hardware tests
scripts/
  lab.sh                normal entry point: build/test/doctor/report/boot
  build-j85-lab.sh      complete local no-USB build of m1n1/kernel/initramfs
  install-toolchain.sh   builds the toolchain container image only
  build-container.sh     builds the image and runs the laptop-only build
  build.sh               builds inside the prepared environment
  build-j85-initramfs.sh builds the RAM-only BusyBox initramfs for J85 Linux
  palera1n-a7-hoolock-pongo.sh  boots Hoolock Pongo 2.6.3 (has bootm); needs sudo and DFU
  boot-m1n1-j85.sh --approve    uploads the packaged payload and runs bootm
  j85-sh.py              runs one command on the iPad's Linux over USB serial
native-ipad/             native UIKit/AVKit app with offline movie storage
notes/                   sanitized reproducibility and bring-up records
notes/source-versions.md upstream revisions
```

## Build

Requires Docker with permission to use its daemon. From the project root:

```bash
bash scripts/build-container.sh
```

The first run downloads a Debian 11 image and build packages. Subsequent runs
reuse Docker's cache. The build runs as your user, with networking disabled
and no USB devices passed through. The project's directory is mounted at
`/work` and receives the build artifacts.

The container supplies Clang 11, LLVM, ld64, and cctools-strip. This avoids
installing older libssl/libxml libraries onto Ubuntu 26.04. The base image
is pinned by digest and the Mach-O package downloads have SHA-256 checks.
Debian package updates are resolved when the image is built.

Produces:

- `src/pongoOS/build/Pongo` — core Mach-O binary
- `src/pongoOS/build/Pongo.bin` — core boot image
- `src/pongoOS/build/checkra1n-kpf-pongo` — upstream kernel patchfinder module
- `src/pongoOS/build/PongoConsolidated.bin` — core plus upstream patchfinder
- `modules/hello-juan/build/hello-juan` — our loadable module
- `build/Pongo.a7.trampoline.bin` — explicit A7 register/copy trampoline

For native builds with a compatible toolchain, run `bash scripts/build.sh`.
The previous host installer failed on Ubuntu 26.04; the installer script now
builds the container image instead of changing host packages.

## Running it on the iPad

Building does not communicate with the iPad. Linux runs from RAM only and is gone
after a restart, so every boot repeats these steps:

```bash
scripts/lab.sh build                    # complete local build; never opens USB
scripts/lab.sh boot --approve           # guided manual DFU → Pongo → RAM Linux
scripts/lab.sh shell 'uname -a'
scripts/lab.sh report
scripts/lab.sh touch-report
scripts/lab.sh host-restore
```

The guided boot still requires the physical DFU button sequence. It does not automate
device entry. Equivalent low-level commands remain:

```bash
sudo scripts/prepare-pongo-host.sh
# Enter DFU manually.
sudo scripts/palera1n-a7-hoolock-pongo.sh
scripts/boot-m1n1-j85.sh --approve
```

The iPad first shows a status page, with a color band below it: green means the USB
shell is connected, yellow means waiting, and red means failed. Once USB setup has
finished, `/bin/touch-test` takes over the complete display with four touch zones,
crosshairs, and a tap-count strip. Run commands from the laptop with
`scripts/j85-sh.py 'uname -a'`, which refuses commands that could change persistent
device state. Run `sudo scripts/restore-pongo-host.sh` when finished.
After the touch-diagnostic payload boots, `scripts/lab.sh touch-report` records the
bounded read-only evidence needed for the next bring-up decision.

Hold Home + Power for 10 seconds to force a restart. Details of the first boot are in
[`notes/2026-11-05-a7-linux-first-boot.md`](notes/2026-11-05-a7-linux-first-boot.md).

To test `initramfs/init` and the serial tool without an iPad, run
`bash initramfs/test_init.sh` and `bash scripts/test_j85_sh.sh`.
For the complete local build/test gate, use `scripts/lab.sh build`.

## Two application lanes

The lab now separates a stable stock-iPad lane from a custom RAM-only Linux lane:

```text
native-ipad/   stable iPadOS applications built with Xcode on the Mac
linux-apps/    portable framebuffer/touch/audio application cores
simulator/     deterministic fake framebuffer, pointer, and audio boundary
initramfs/     selected Linux applications bundled into the RAM payload
```

`native-ipad/JuanPad` is the current stable lane: it imports user-owned movies
and plays them offline with AVKit. `linux-apps/hello-juan` is the first custom
lane application. Its portable core is compiled for both the host simulator and
the A7 initramfs; only `linux-apps/linux-hello-juan.c` knows about Linux
framebuffer and evdev devices. Run the local application gate with:

```bash
bash scripts/test-linux-apps.sh
```

After a separately approved RAM-only boot, the bundled app can be launched from
the USB shell:

```sh
hello-juan /dev/fb0 /dev/input/event0
```

### Native offline movie milestone

`native-ipad/` is a no-web-view Objective-C UIKit app. Its `Offline Movies` tab
imports user-owned MP4/M4V/MOV files into the app Documents directory and plays
them through AVKit/AVPlayer. After the one-time import, playback is designed for
Airplane Mode with no laptop, Wi-Fi, or internet connection.

This Linux host cannot produce a signed stock-iOS installation because Apple's
iPhoneOS SDK and provisioning credentials are unavailable. Build and sign the app
on a Mac with Xcode, install it, then import a movie through Files or USB file
sharing. The Linux lab does not automate iPad app installation or persistent
iPad file writes.

### Touch status

The current RAM-only payload is the J85 fullscreen touch diagnostic build. It adds
the A7 SPI1 controller, the mini 2 multitouch node, GPIO 71 chip-select, the Apple
Z2 driver path, the pinned firmware extracted from Apple's J85 IPSW, and a static
`/bin/touch-test` canvas. Hardware boot successfully displayed the full
1536×2048 canvas and registered `iPad mini 2 Touchscreen`, but Apple Z2 probe
bring-up timed out with error `-110` and no touch events were observed.

The static ADT string is an unresolved `syscfg/MtCl/...` reference, but the live
Linux device tree contained a real 1,024-byte `apple,z2-cal-blob`; calibration is
therefore not the current blocker. The remaining suspects are the touch power
rails, 32.768 kHz touch clock, reset sequence, and pre-firmware SPI exchange.
The staged diagnostic and PMU-research plan is recorded in
[`notes/2026-11-06-j85-touch-and-movie-lane.md`](notes/2026-11-06-j85-touch-and-movie-lane.md).
Do not read NAND or arbitrary memory to solve touch bring-up.

No restore, downgrade, or persistent device changes are authorized by this build
workflow. RAM-loaded code can still issue hardware or storage writes, so review
payloads before running them. The `hello-juan` module only prints diagnostic values,
and it only loads on the Pongo build it was compiled for. The earlier gaster boot
experiments are recorded in
[`notes/2026-11-04-a7-gaster-boot-path.md`](notes/2026-11-04-a7-gaster-boot-path.md).

### `juan` diagnostics

After manually booting plain `Pongo.bin` and manually loading
`modules/hello-juan/build/hello-juan`, the module offers:

- `juan` or `juan help` — command help
- `juan info` — identity, boot arguments, memory, framebuffer, and tree summary
- `juan bootargs` — the complete boot-arguments layout used by this milestone
- `juan display` — framebuffer geometry and size
- `juan dt <node> [property]` — direct properties of a node, or one property;
  binary values are capped at the first 64 bytes

All subcommands are read-only. They are intended to collect the A7 hardware map
needed for later display, touch, storage, and Linux bootstrap research.

## Video playback test on stock iOS

This does not need PongoOS, a jailbreak, or an App Store installation.
With `ffmpeg` and Python 3 available on the laptop, run:

```bash
bash scripts/serve-video-test.sh
```

On the same Wi-Fi, open `http://YOUR-LAPTOP-WIFI-IP:8765` in iPad Safari and
tap Play. The generated six-second H.264/AAC stream tests video and sound.
Stop the server with Ctrl-C. It serves only the generated test directory.
Playback on the actual iPad has not yet been verified. This is a local
playback test, not support for commercial streaming services or a second
screen implementation.

For a locally owned movie file, use the fullscreen Safari movie lane:

```bash
scripts/serve-movie.sh /path/to/movie-you-may-legally-view.mp4
```

The script transcodes the source to H.264/AAC HLS under ignored `build/`, prints
the laptop Wi-Fi URL, and serves a viewport-filling player. It does not download,
commit, or redistribute copyrighted media. `scripts/test-movie-lane.sh` validates
the pipeline with generated SMPTE bars and a tone; it does not contact the iPad.

## Status

- [x] Source vendored and exact upstream revisions recorded
- [x] Matching Newlib dependency populated
- [x] Container toolchain scripted
- [x] Core, patchfinder, consolidated image, and custom module build verified
- [x] Explicit bounded A7 Pongo copy/execute path implemented and dry-run tested
- [x] Module loaded on device (see `notes/2026-11-05-a7-pongo-mvp.md`)
- [x] Linux booted from RAM to `/init` via Hoolock Pongo and m1n1 (see `notes/2026-11-05-a7-linux-first-boot.md`)
- [x] USB serial and USB network under RAM-only Linux
- [x] Local fullscreen RAM-only touch-test application packaged
- [x] Portable Linux application core and deterministic simulator scaffolded
- [ ] J85 touch controller initialized on hardware
- [ ] Fullscreen touch input verified on hardware
- [x] Video test generated and served successfully on the laptop
- [x] User-supplied movie HLS lane scaffolded and locally tested
- [ ] Video playback verified on the iPad
- [ ] Second-screen compatibility tested
