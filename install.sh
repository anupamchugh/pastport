#!/bin/sh
# Build, install, and launch Pastport (native macOS menu-bar app).
#
# The post-install `codesign --force --deep` is REQUIRED, not optional:
# xcodebuild's framework re-sign step preserves an old Team ID that no longer matches
# the app binary, and dyld aborts at launch ("different Team IDs"). A deep ad-hoc
# re-sign of the installed bundle gives the app and its embedded framework one identity.
set -e
cd "$(dirname "$0")"

APP="/Applications/Pastport.app"
BUILT=".build/xcode/Build/Products/Release/Pastport.app"

echo "› Generating project + building (Release)…"
xcodegen generate
xcodebuild -project Pastport.xcodeproj -scheme Pastport \
  -configuration Release -derivedDataPath .build/xcode clean build \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)"

echo "› Installing to /Applications…"
killall "Pastport" 2>/dev/null || true
ditto "$BUILT" "$APP"

echo "› Deep re-signing (fixes the Team-ID launch crash)…"
codesign --force --deep --sign - "$APP"
codesign --verify --deep "$APP" && echo "  signature valid ✓"

echo "› Launching…"
if [ "${1:-}" = "--demo" ]; then
  open -a "Pastport" --args --demo
else
  open "$APP"
fi
echo "Done. If it can't read history, grant Full Disk Access to Pastport"
echo "in System Settings › Privacy & Security › Full Disk Access."
