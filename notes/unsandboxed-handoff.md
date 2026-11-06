# Unsandboxed hardware-session handoff

## Objective and hardware state

Reach the first MVP on the iPad mini 2 Wi-Fi (`iPad4,4`, A7, CPID `0x8960`, iOS 12.5.8): pwned DFU, plain PongoOS, explicit `hello-juan` load, and captured `juan help` output. Normal USB is `05ac:12ab`, DFU is `05ac:1227`, and expected Pongo is `05ac:4141`. The current Codex process cannot open raw USB; start an unsandboxed session in this repository.

## Confirmed state

The pinned container builds both `src/pongoOS/build/Pongo.bin` and `modules/hello-juan/build/hello-juan`. The A7 `gaster` exploit succeeds repeatedly and prints `Now you can boot untrusted images.` The A7 signature-check patch is present in `src/hoolock/gaster/payload_A7.S`. PyUSB works in `.venv`. Direct and wrapped uploads can reach 100%, but the device remains in DFU rather than enumerating as Pongo.

## Artifacts

- `src/pongoOS/build/Pongo.bin`: 675936 bytes, SHA-256 `c580b3179f312770a8ccdf0b93ee70d59ab8db7acd89ad3d42a02f8e058157e8`.
- `modules/hello-juan/build/hello-juan`: 67136 bytes, SHA-256 `bb662501c5071f52e26e5b856fbfcacd08b256854a6e7ca9d01d622b9b8672e0`.
- `build/Pongo.a7.dfu.bin`: 337954 bytes, SHA-256 `c66879682e09308f414612f04b46b188463d1fd84af7c09f18cbbabe34bd87e0`.
- `/tmp/openra1n/payloads/Pongo.bin`: 254224 bytes, SHA-256 `c0dcc468ea3e5aff09933aed2963b88d39f12dc4a7a661148ec277eab5961fb6`.

## Failed paths and interpretation

Direct upload of the 675936-byte Pongo image stops near 77.6%, consistent with the A7 `0x80000` DFU boundary. The 337954-byte LZ4 wrapper and the 254224-byte upstream Pongo image both reach 100%, but USB remains `05ac:1227`. `scripts/upload_dfu_a7.py` sends every chunk, then receives Input/Output Error on `DFU_CLEAR_STATUS`; treat it as experimental. After failed uploads, `gaster pwn` immediately recognizes pwned DFU, so checkm8 and signature patching work while the transfer-to-entry handoff does not.

## Next technical step

Do not retry blindly with `irecovery`. Compare this local custom request interface with a known A7 Pongo booter and implement an explicit bounded upload/copy/execute path. Start with `src/hoolock/gaster/gaster.c` (`gaster_command()` near line 1532), `payload_handle_checkm8_request.S`, and `src/pongoOS/src/boot/entry.S`. The handler can call a function with `x0` through `x7` but does not directly initialize Pongo's expected incoming `x8`; determine the register/address contract or add a small register-setup trampoline.

## Safety and success criteria

Keep DFU entry, cable actions, and payload execution explicit and manual. Do not automate USB passthrough or device entry, and do not run restore, downgrade, `readmem`, `writemem`, or persistent-storage commands. Success is `05ac:4141`, followed by explicit module load and readable output from `juan help`; record exact output in a dated note under `notes/`.
