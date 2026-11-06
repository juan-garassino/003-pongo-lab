#!/bin/bash
# Builds an unsigned app bundle. Signing/provisioning is a separate required step.
set -euo pipefail
cd "$(dirname "$0")"
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'Requires macOS with Xcode and its iPhoneOS SDK. No app was built.' >&2
  exit 1
fi
sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
mkdir -p build/JuanPad.app
xcrun --sdk iphoneos clang -target arm64-apple-ios12.0 -isysroot "$sdk" \
  -fobjc-arc -fmodules -O2 -Wall -framework UIKit -framework Foundation \
  -framework AVKit -framework AVFoundation main.m -o build/JuanPad.app/JuanPad
cp Info.plist build/JuanPad.app/Info.plist
printf '%s\n' 'Unsigned app: build/JuanPad.app. A valid signing identity and device provisioning profile are required before installation.'
