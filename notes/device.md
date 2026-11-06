# Target device (read over USB, 2026-11-03)

| Field | Value |
|---|---|
| Model | iPad mini 2, Wi-Fi (ME277, `iPad4,4`) |
| SoC | Apple A7 "Cyclone", arm64 |
| iOS | 12.5.8 (build 16H88) — terminal version for this device |
| UDID | `<redacted for public repository>` |
| State | Activated, no passcode, pairs with this laptop |
| Owner | Juan (confirmed) |

A7 is in the checkm8 BootROM range (A5–A11), so unsigned code can run at the
earliest boot stage over USB. A bad boot just reboots back into iOS.

Host: Ubuntu 26.04.1, x86_64, clang 21. usbmuxd present.
