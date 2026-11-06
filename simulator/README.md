# Juan application simulator

The simulator is the no-hardware development loop for `linux-apps`. It models
only the device boundary:

- deterministic framebuffer dimensions;
- scripted pointer events;
- PPM frame capture;
- an audio-intent recorder instead of hardware playback.

It intentionally does not emulate A7 hardware, PongoOS, Linux drivers, USB, or
iPadOS. That keeps application bugs separable from bring-up bugs.

## Run

```bash
python3 simulator/run-hello.py --build-dir build/linux-apps
bash scripts/test-linux-apps.sh
```

`fake_device.py` is a small Python model used by tests and tools. Add new fake
capabilities there rather than making an application depend on the simulator.
