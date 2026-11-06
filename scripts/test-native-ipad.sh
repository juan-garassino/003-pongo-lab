#!/usr/bin/env bash
# Local source checks for the native iPad app. This does not require Xcode.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source="$ROOT/native-ipad/main.m"
plist="$ROOT/native-ipad/Info.plist"
project="$ROOT/native-ipad/JuanPad.xcodeproj/project.pbxproj"
scheme="$ROOT/native-ipad/JuanPad.xcodeproj/xcshareddata/xcschemes/JuanPad.xcscheme"

[[ -s "$source" && -s "$plist" && -s "$project" && -s "$scheme" ]]

python3 - "$plist" <<'PY'
from pathlib import Path
import plistlib
import sys

path = Path(sys.argv[1])
with path.open("rb") as handle:
    info = plistlib.load(handle)

assert info["CFBundleIdentifier"] == "com.juan.JuanPad"
assert info["MinimumOSVersion"] == "12.0"
assert info["UIFileSharingEnabled"] is True
assert info["LSSupportsOpeningDocumentsInPlace"] is True
assert "audio" in info["UIBackgroundModes"]
document_types = info["CFBundleDocumentTypes"]
assert any("public.movie" in item.get("LSItemContentTypes", []) for item in document_types)
print("native-ipad Info.plist checks passed")
PY

python3 - "$project" "$scheme" <<'PY'
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

project = Path(sys.argv[1]).read_text(encoding="utf-8")
scheme = Path(sys.argv[2]).read_text(encoding="utf-8")
ET.fromstring(scheme)

for setting in (
    "IPHONEOS_DEPLOYMENT_TARGET = 12.0",
    "ARCHS = arm64",
    "INFOPLIST_FILE = Info.plist",
    "PRODUCT_BUNDLE_IDENTIFIER = com.juan.JuanPad",
    "TARGETED_DEVICE_FAMILY = 2",
):
    assert setting in project, setting

object_ids = set(re.findall(r"^\t\t([0-9A-F]{24}) ", project, re.MULTILINE))
assert object_ids
for object_id in re.findall(r"([0-9A-F]{24})", project):
    assert object_id in object_ids, object_id
assert project.count("4A10000626C64C1200B3AB3A") >= 3
assert "BlueprintName = \"JuanPad\"" in scheme
print("native-ipad Xcode project checks passed")
PY

grep -q 'AVAudioSessionCategoryPlayback' "$source"
grep -q 'UIDocumentPickerModeImport' "$source"
grep -q 'importOpenedMovieAtURL' "$source"
grep -q 'AVPlayer playerWithURL' "$source"
grep -q 'Airplane-ready' "$source"
if grep -qE 'WKWebView|UIApplication sharedApplication].openURL' "$source"; then
  echo "Unexpected web-view or external URL playback in native movie app" >&2
  exit 1
fi

echo "native-ipad offline movie source checks passed"
