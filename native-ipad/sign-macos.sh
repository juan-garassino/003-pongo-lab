#!/bin/bash
# Sign an already-built JuanPad bundle using an Apple provisioning profile.
set -euo pipefail
cd "$(dirname "$0")"

if [[ "$(uname -s)" != Darwin ]]; then
  echo 'Requires macOS with Xcode security tools. No app was signed.' >&2
  exit 1
fi

usage() {
  cat <<'EOF'
Usage: sign-macos.sh SIGNING_IDENTITY PROVISIONING_PROFILE.mobileprovision

Build the app first with build-macos.sh. The profile must cover
com.juan.JuanPad (or a wildcard app ID) and include this iPad.
EOF
}

[[ $# -eq 2 ]] || { usage >&2; exit 2; }
identity=$1
profile=$2
app=build/JuanPad.app

[[ -d "$app" ]] || { echo "Missing $app; run build-macos.sh first" >&2; exit 1; }
[[ -f "$profile" ]] || { echo "Profile not found: $profile" >&2; exit 1; }

mkdir -p build/signing
security cms -D -i "$profile" >build/signing/profile.plist
/usr/libexec/PlistBuddy -x -c 'Print :Entitlements' \
  build/signing/profile.plist >build/signing/JuanPad.entitlements
cp "$profile" "$app/embedded.mobileprovision"

codesign --force --identifier com.juan.JuanPad \
  --sign "$identity" \
  --entitlements build/signing/JuanPad.entitlements \
  --timestamp=none "$app"
codesign --verify --strict --verbose=2 "$app"

rm -rf build/Payload build/JuanPad.ipa
mkdir -p build/Payload
cp -R "$app" build/Payload/
(cd build && zip -qr JuanPad.ipa Payload)

echo "Signed app: $app"
echo "Installable IPA: build/JuanPad.ipa"
echo "Install through Xcode or Finder with the Apple ID that issued the profile."
