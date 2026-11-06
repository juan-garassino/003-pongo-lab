# Portable Linux applications

This directory is the custom Linux application lane for the RAM-only J85
payload. It deliberately separates an application from the device adapters:

- `include/juan/core.h` defines the portable 32-bits-per-pixel surface API.
- `juan-core.c` implements the renderer without libc allocation or file I/O.
- `include/juan/hello.h` and `hello-juan.c` implement the first app state machine.
- `linux-hello-juan.c` is the only file here that opens Linux framebuffer and
  input devices.
- `apps.list` records the binaries that the initramfs build bundles.

The same application core is compiled for the host simulator and for the A7
initramfs. Device-specific code may not call into app logic directly; it feeds
events and calls `juan_hello_frame()`.

The Linux adapter currently supports framebuffer and pointer/touch input. The
portable API also describes an audio intent, but there is no A7 audio backend
yet. Until that backend exists, an adapter may only log the intent; it must not
guess hardware register writes.

## Local simulation

```bash
python3 simulator/run-hello.py --build-dir build/linux-apps
```

The simulator compiles the portable core with the host C compiler, emits binary
PPM frames under an ignored build directory, and validates scripted pointer
input. The complete no-hardware gate is:

```bash
bash scripts/test-linux-apps.sh
```

No command in this directory opens USB. The bundled app is launched manually
from the USB shell after a separately approved RAM-only boot:

```sh
hello-juan /dev/fb0 /dev/input/event0
```

If touch input is unavailable, the app still renders and exits on `SIGINT`.
That is intentional: display and input bring-up must remain independently
observable.
