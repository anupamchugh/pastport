#!/bin/bash
# Build release artifacts without installing or publishing them.
set -euo pipefail
cd "$(dirname "$0")"
preview=false
use_asc=false
identity=""
profile=""
output=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --unsigned-preview) preview=true; shift ;;
    --asc) use_asc=true; shift ;;
    --sign|--notary-profile|--output)
      [[ $# -ge 2 && -n "$2" ]] || { echo "Missing value for $1" >&2; exit 2; }
      case "$1" in
        --sign) identity="$2" ;;
        --notary-profile) profile="$2" ;;
        --output) output="$2" ;;
      esac
      shift 2 ;;
    --help)
      echo "Usage: $0 (--unsigned-preview | --sign IDENTITY (--asc | --notary-profile PROFILE)) [--output DIRECTORY]"
      exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done
if $preview; then
  [[ -z "$identity" && -z "$profile" && "$use_asc" == false ]] || { echo "Preview cannot use distribution credentials." >&2; exit 2; }
else
  [[ "$identity" == 'Developer ID Application: '* ]] || {
    echo "Distribution requires a Developer ID Application identity." >&2; exit 2;
  }
  if $use_asc; then
    [[ -z "$profile" ]] || { echo "Choose --asc or --notary-profile, not both." >&2; exit 2; }
    command -v asc >/dev/null
  else
    [[ -n "$profile" ]] || { echo "Choose --asc or --notary-profile for notarization." >&2; exit 2; }
  fi
fi
notarize() {
  if $use_asc; then
    asc notarization submit --file "$1" --wait --timeout 30m
  else
    xcrun notarytool submit "$1" --keychain-profile "$profile" --wait
  fi
}
command -v xcodegen >/dev/null
xcodegen generate
source_root=$(pwd -P)
args=(-project Pastport.xcodeproj -scheme Pastport -configuration Release -destination generic/platform=macOS -derivedDataPath .build/release-build build ONLY_ACTIVE_ARCH=NO "ARCHS=arm64 x86_64")
args+=("OTHER_SWIFT_FLAGS=-file-prefix-map \"$source_root=/Pastport\" -file-compilation-dir /Pastport" SWIFT_SERIALIZE_DEBUGGING_OPTIONS=NO DEPLOYMENT_POSTPROCESSING=YES STRIP_INSTALLED_PRODUCT=YES COPY_PHASE_STRIP=YES)
if $preview; then
  args+=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual)
else
  args+=("CODE_SIGN_IDENTITY=$identity" CODE_SIGN_STYLE=Manual 'OTHER_CODE_SIGN_FLAGS=--timestamp')
fi
xcodebuild "${args[@]}"
app=".build/release-build/Build/Products/Release/Pastport.app"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
build=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$app/Contents/Info.plist")
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$build" =~ ^[0-9]+$ ]] || { echo "Invalid app version." >&2; exit 1; }
name="Pastport-$version"
$preview && name="$name-unsigned-preview"
output="${output:-.build/releases/$version}"
mkdir -p "$output"
output=$(cd "$output" && pwd)
for artifact in "$name.dmg" "$name.zip" "$name-SHA256SUMS.txt"; do
  [[ ! -e "$output/$artifact" ]] || { echo "Refusing to overwrite $output/$artifact" >&2; exit 1; }
done
stage=$(mktemp -d .build/pastport-package.XXXXXX)
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/Pastport.app"
app="$stage/Pastport.app"
if $preview; then
  # Xcode may retain a framework identity from an earlier build. Re-sign the
  # complete local preview consistently so dyld library validation can load it.
  codesign --force --deep --sign - "$app"
fi
codesign --verify --deep --strict "$app"
# Fail before any upload if release metadata contains local build paths or a
# debugging entitlement. Neither belongs in a public distribution.
/usr/bin/python3 - "$app" <<'PY_CHECK'
from pathlib import Path
import plistlib, subprocess, sys
app = Path(sys.argv[1])
for path in app.rglob('*'):
    if path.is_file() and not path.is_symlink() and b'/Users/' in path.read_bytes():
        raise SystemExit(f"Private build path found in {path.relative_to(app)}")
result = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(app)], capture_output=True)
if result.returncode:
    raise SystemExit('Unable to inspect app entitlements')
entitlements = plistlib.loads(result.stdout) if result.stdout else {}
if entitlements.get('com.apple.security.get-task-allow'):
    raise SystemExit('Release app must not permit debugger attachment')
print('Release privacy and entitlement checks passed')
PY_CHECK
if ! $preview; then
  ditto -c -k --keepParent "$app" "$stage/$name-notarize.zip"
  notarize "$stage/$name-notarize.zip"
  xcrun stapler staple "$app"
  ./release-preflight.sh "$app"
fi
ditto -c -k --keepParent "$app" "$output/$name.zip"
unzip -t "$output/$name.zip"
mkdir "$stage/dmg"
ditto "$app" "$stage/dmg/Pastport.app"
ln -s /Applications "$stage/dmg/Applications"
if $preview; then
  printf '%s\n' 'LOCAL PREVIEW: ad-hoc signed, not notarized. Do not distribute as a trusted release.' > "$stage/dmg/UNSIGNED-PREVIEW.txt"
fi
hdiutil create -volname "Pastport $version" -srcfolder "$stage/dmg" -ov -format UDZO "$output/$name.dmg"
hdiutil verify "$output/$name.dmg"
if ! $preview; then
  codesign --force --timestamp --sign "$identity" "$output/$name.dmg"
  notarize "$output/$name.dmg"
  xcrun stapler staple "$output/$name.dmg"
  xcrun stapler validate "$output/$name.dmg"
  spctl -a -vv --type open --context context:primary-signature "$output/$name.dmg"
fi
(cd "$output" && shasum -a 256 "$name.dmg" "$name.zip" > "$name-SHA256SUMS.txt")
printf 'Artifacts ready: %s (version %s, build %s)\n' "$output" "$version" "$build"
