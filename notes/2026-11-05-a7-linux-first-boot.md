# iPad mini 2 A7 first Linux boot

Date: 2026-11-05

## Result

Linux reached our initramfs `/init` from RAM on the iPad mini 2:

```text
fresh A7 DFU
→ palera1n v2.1-beta.2 (checkra1n 0.1337.3, checkm8)
→ Hoolock PongoOS 2.6.3-bb492b00
→ upload m1n1 + bootargs + J85 DTB + Image.gz + initramfs (10657589 bytes)
→ bootm
→ m1n1
→ Linux 7.3.0-rc1-g6831bc701a6c
→ /init
```

Text on the iPad display, typed from the screen by Juan with small transcription
differences (e.g. `RAN-only`) corrected here:

```text
hello-juan: Linux 7.3.0-rc1-g6831bc701a6c on Apple iPad mini 2 (Wi-Fi)
hello-juan: RAM-only initramfs, no storage mounted
earlycon keep_boot_con console=tty0 ignore_loglevel loglevel=8 rdinit=/init panic=0 cpufreq.off=1
```

## Not working yet

The first boot's USB serial shell did not appear. The host saw Pongo disconnect
at 13:42:23, then `usb 1-5: new high-speed USB device number 20` at 13:42:28 with
no descriptor afterwards. No `/dev/ttyACM*` appeared. There was no interactive
access to that first Linux session; touch was not expected to work.

## Second boot: interactive USB shell works

After improving the initramfs gadget setup, the second RAM-only boot reached an
interactive shell. Juan explicitly approved sending the rebuilt payload. The host
observed:

```text
1d6b:0104 Linux Foundation Multifunction Composite Gadget
Product: iPad mini 2 Linux
Manufacturer: hello-juan
cdc_acm → /dev/ttyACM0
```

The device also exposed an NCM USB network interface. Exact kernel identity:

```text
Linux (none) 7.3.0-rc1-g6831bc701a6c #1 SMP PREEMPT
Thu Nov 5 11:54:10 UTC 2026 aarch64 GNU/Linux
```

The safe host-side shell worked:

```bash
scripts/j85-sh.py 'uname -a'
```

The initramfs diagnostic trace showed:

```text
ok console quiet
ok found UDC 20c100000.usbdev after 0s
ok gadget prepared
ok function acm.usb0
ok function ncm.usb0
ok UDC bound (acm+ncm)
ok usb0 172.16.42.1
```

Further read-only observations:

```text
CPU count: 2 Apple A7 cores
Memory: 954096 KiB total
Framebuffer: 1536x2048, stride 6144, x8r8g8b8
Device USB IPv4: 172.16.42.1/24 on usb0
Root filesystem: RAM rootfs plus devtmpfs/proc/sysfs/tmpfs/configfs/debugfs/devpts
```

No block device or persistent storage mount was present in `/proc/mounts`.
`/proc/partitions` was empty, confirming that no storage device had been
registered by this intentionally minimal kernel/initramfs.

Kernel log confirmed the important Linux drivers:

```text
simpledrm on 83d000000.framebuffer
dwc2 on 20c100000.usbdev
configfs-gadget.j85
Apple GPIO buttons
apple_cyclone_pmu
Apple PMIC RTC
```

Current verified payload:

```text
build/m1n1-j85-ram-only.bin
Size: 10660821 bytes
SHA-256: 94bc1430053e9adb1e81f18abc79372ea72a847cdc0f13c578330be7f88408fb

build/linux-j85/initramfs.gz
Build ID: 97657e16
SHA-256: eb488071009cf7704631defc98195c039fb1097fd137b3d03e89695e46f3a1db
```

## Artifacts

```text
build/m1n1-j85-ram-only.bin
  SHA-256 b8ec376cf9e9d46804f10fecc1046666a8e65fea5aa1e6db10e8089d0efe000f
build/linux-j85/manifest.sha256    component hashes
build/sources/hoolock-docs/binaries/Pongo.bin
  SHA-256 1e5543fd8e6dbd84c334b87d71aa473f4d347c2ba8a5e863b6e10f18461c7575
```

Sources: m1n1 `d5a10ac5`, Hoolock Linux `6831bc70` (4K pages), docs `23ebe1fb`.

## Commands

```bash
bash scripts/build-hoolock-j85-linux.sh
bash scripts/build-j85-initramfs.sh
bash scripts/package-m1n1-j85-ram.sh
sudo scripts/prepare-pongo-host.sh
# enter DFU by hand
sudo scripts/palera1n-a7-hoolock-pongo.sh
scripts/boot-m1n1-j85.sh --approve
```

## Lessons learned

- PongoOS `3c6a76da` cannot boot m1n1. `bootm` arrived in `e1313a7`, and
  `bb492b00` also moved m1n1 to the top of kernel data.
- Overriding Pongo through palera1n worked first try with Hoolock's image, whereas
  the earlier `d068ec60` override never reached `05ac:4141`.
- `pongo_transact.py` can return a truncated `help`, so its output does not prove a
  command is missing.

## Safety record

Nothing was intentionally written to storage. The initramfs mounts only devtmpfs,
proc, sysfs and tmpfs.

## Force restart and battery

Holding Home + Power restarted the iPad from Linux. iPadOS came back and appeared as
`05ac:12ab` at about 14:36, after Linux was started at 13:42. That is about 54 minutes
powered on, but liveness during that time was not measured.

`ideviceinfo -q com.apple.mobile.battery` then reported 11% and `BatteryIsCharging:
false` while connected to the laptop, which offered `bMaxPower=500mA`. The level before
the boot was not recorded, so no drain rate can be derived. `scripts/prepare-pongo-host.sh`
blacklists `apple_mfi_fastcharge`, which may be why the laptop port does not charge it;
this is not confirmed. Charge from a wall charger before DFU work.

## Device facts read from iPadOS

From `ideviceinfo` and `idevicediagnostics ioregentry AppleARMPMUCharger` at 14:37:

```text
ProductType iPad4,4, HardwareModel J85AP, iOS 12.5.8 (16H88)
Disk 32 GB, 16.6 GB free
CycleCount 466, DesignCapacity 6274, AppleRawMaxCapacity 4861
Cable connected: InstantAmperage -104, IsCharging false, Temperature 3470
```

Units are not stated by the tools; these look like mAh, mA and hundredths of a degree C.
The negative current suggests the iPad was discharging while connected to the laptop.
These commands work only while iPadOS is running, and give a way to read the battery
before and after a Linux session.
