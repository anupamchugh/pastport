#!/bin/bash
# Install a local, ad-hoc-signed development build. Public releases use package-release.sh.
set -euo pipefail
cd "$(dirname "$0")"
case "${1:-}" in
  ""|--demo) ;;
  *) echo "Usage: $0 [--demo]" >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { echo "Usage: $0 [--demo]" >&2; exit 2; }
APP="/Applications/Pastport.app"
# Demo mode (fictional data, never reads Safari) exists only in Debug builds.
CONFIG=Release
[[ "${1:-}" == "--demo" ]] && CONFIG=Debug
BUILT=".build/xcode/Build/Products/$CONFIG/Pastport.app"
if pgrep -x Pastport >/dev/null || pgrep -x PastportBar >/dev/null; then
  echo "Quit Pastport before replacing the installed app." >&2
  exit 1
fi
xcodegen generate
xcodebuild -project Pastport.xcodeproj -scheme Pastport \
  -configuration "$CONFIG" -destination 'platform=macOS' -derivedDataPath .build/xcode build
STAGED=$(mktemp -d /Applications/.Pastport-install.XXXXXX)
trap 'rm -rf "$STAGED"' EXIT
ditto "$BUILT" "$STAGED/Pastport.app"
codesign --force --deep --sign - "$STAGED/Pastport.app"
codesign --verify --deep --strict "$STAGED/Pastport.app"
# Preserve the previous installation rather than merging stale bundle contents.
BACKUP=""
if [[ -e "$APP" ]]; then
  BACKUP="/Applications/Pastport.previous-$(date +%Y%m%d%H%M%S)-$$.app"
  mv -f "$APP" "$BACKUP"
fi
if ! mv -f "$STAGED/Pastport.app" "$APP"; then
  [[ -z "$BACKUP" ]] || mv -f "$BACKUP" "$APP"
  exit 1
fi
if [[ "${1:-}" == "--demo" ]]; then
  open "$APP" --args --demo
else
  open "$APP"
fi
[[ -z "$BACKUP" ]] || printf 'Previous installation preserved: %s\n' "$BACKUP"
echo 'Local development app installed. History and Photos stay closed until you choose to read them.'
