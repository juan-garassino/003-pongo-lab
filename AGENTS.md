# Repository Guidelines

## Project Structure & Module Organization

- `src/pongoOS/` contains the vendored PongoOS and Newlib sources; avoid unrelated upstream cleanup here.
- `modules/hello-juan/` contains the custom PongoOS module.
- `initramfs/` contains the RAM-only Linux `init` and its host test.
- `scripts/` contains reproducible build and local test-server helpers; `toolchain/` defines the Docker build environment.
- `screen-share/`, `native-ipad/`, and `build/` hold companion experiments, iOS app source, and generated artifacts respectively.
- `notes/` records device and source-version information.

## Build, Test, and Development Commands

- `bash scripts/build-container.sh` — builds the pinned Linux toolchain image and runs the isolated PongoOS/module build with networking and USB disabled.
- `bash scripts/install-toolchain.sh` — builds only the Docker toolchain image.
- `bash scripts/build.sh` — builds PongoOS and `hello-juan` using a compatible host toolchain; use `JOBS=8` to override parallelism.
- `make -C modules/hello-juan clean` — removes module build products.
- `bash scripts/build-j85-initramfs.sh` then `bash scripts/package-m1n1-j85-ram.sh` — builds and checks the RAM-only Linux payload. These never open USB.
- `bash initramfs/test_init.sh` and `bash scripts/test_j85_sh.sh` — test `init` and the serial tool against fakes, with no device.
- `scripts/j85-sh.py 'command'` — runs one command on the iPad's Linux over USB serial; it refuses commands that could change persistent state.
- `bash scripts/serve-video-test.sh [port]` — generates an HLS test and serves `build/video-test/` on the LAN.
- `python3 screen-share/server.py` — runs the local WebRTC sharing prototype.

## Coding Style & Naming Conventions

- Preserve surrounding formatting: C/Objective-C and Python use 4-space indentation; shell scripts use 2-space continuation alignment.
- Keep shell scripts POSIX-safe where practical, enable `set -euo pipefail`, and resolve the project root from `$0`.
- Use lowercase hyphenated executable and module names, descriptive Python names, and explicit Make variables.
- Existing C builds treat warnings as errors; keep interfaces small and document device-visible behavior in the relevant README.

## Testing Guidelines

There is no automated suite or configured formatter. Before requesting review:

1. Run the applicable build command above.
2. Exercise script behavior locally without connecting a device.
3. For web changes, test sender/viewer or HLS playback in the targeted browser and iPad Safari when possible.
4. Record any remaining device-only verification gaps explicitly.

## Commit & Pull Request Guidelines


Use Conventional Commits (for example, `build(toolchain): build module in isolated container`) and add body details for toolchain, security, or device-behavior changes. Work on feature branches off `main`.

Pull requests must state the purpose, commands run, generated artifacts, and remaining manual testing. Link related issues and include screenshots or pairing URLs for UI work. Never commit credentials, signing identities, provisioning profiles, or generated `build/` output.

## Safety & Configuration

Do not add automatic device entry, USB passthrough, restore, downgrade, or persistent-write behavior. Keep container builds network-isolated and treat all pre-boot payloads as capable of affecting hardware.
