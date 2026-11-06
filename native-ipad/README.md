# JuanPad native iPad app — work in progress

Our Objective-C/UIKit app targets iOS 12 on arm64 iPads. No web view or third-party
app framework. Two tabs:

- Second Display receives JPEG frames from our laptop companion's virtual monitor.
- Movies plays local MP4/M4V/MOV files through Apple's AVPlayer. Imported files
  are copied into the app Documents directory and do not need the laptop, Wi-Fi,
  or the internet to play. The app selects the iOS playback audio session, keeps
  the display awake while its player is presented, shows saved file sizes, and
  supports deletion from the movie list.

The + button imports from Files. `public.movie` handling and **Open in JuanPad**
copy a selected file into JuanPad's Documents storage. USB file sharing is
enabled for a one-time Finder/iTunes transfer after the app is installed. Once
import is complete, playback is an airplane-mode test: enable Airplane Mode and
play directly from JuanPad.
The `juanpad://HOST:PORT/KEY` URL scheme fills the pairing field. The user presses
Connect to create the monitor. Disconnect, leaving the tab, and backgrounding the
app stop the laptop monitor. The laptop also expires idle monitor sessions.

This source has NOT been compiled or installed: this Ubuntu host has no iOS SDK
or signing credentials. `bash build-macos.sh` builds an unsigned bundle on a Mac
with Xcode. A matching Apple signing identity and provisioning profile must be
supplied before it can be installed on stock iOS. Free provisioning has periodic
renewal requirements; do not assume this is a permanent install.

Open the prepared project in Xcode:

```text
native-ipad/JuanPad.xcodeproj
```

Select the JuanPad target, choose your Apple Development team, connect the iPad
mini 2, and use Run. Xcode itself is macOS-only. The app targets iOS 12.0 and
arm64, so iPad mini 2 / iPhoneOS 12.5.8 is in range at the application level;
very new Xcode installations may nonetheless refuse such an old physical device;
Xcode 14.x is the known-comfortable choice.

The equivalent unsigned command-line build is:

```bash
bash build-macos.sh
bash sign-macos.sh 'Apple Development: ...' JuanPad.mobileprovision
```

The signing helper extracts the profile entitlements, embeds the profile, signs
the bundle, and packages `build/JuanPad.ipa`. Install it through Xcode/Finder;
the Linux lab does not send an installation command to the iPad.

The Linux lab intentionally does not automate iPad app installation or persistent
USB file transfer. Use Xcode/Finder on a Mac, or explicitly copy a file into
Files before using JuanPad's import picker.

Local HTTP is allowed for the trusted Wi-Fi connection to the companion. This
prototype uses JPEG polling for compatibility, not a high-performance video codec.
Actual frame rate, battery use, movie compatibility, and lifecycle behavior need
testing on the device. The first native milestone is: install JuanPad, import
one user-owned movie, enable Airplane Mode, and play it with audible sound.
Building these features does not replace iOS.
