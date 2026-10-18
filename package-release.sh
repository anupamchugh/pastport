#!/bin/bash
# Build release artifacts without installing or publishing them.
set -euo pipefail
cd "$(dirname "$0")"
preview=false
identity=""
profile=""
output=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --unsigned-preview) preview=true; shift ;;
    --sign|--notary-profile|--output)
      [[ $# -ge 2 && -n "$2" ]] || { echo "Missing value for $1" >&2; exit 2; }
      case "$1" in
        --sign) identity="$2" ;;
        --notary-profile) profile="$2" ;;
        --output) output="$2" ;;
      esac
      shift 2 ;;
    --help)
      echo "Usage: $0 (--unsigned-preview | --sign IDENTITY --notary-profile PROFILE) [--output DIRECTORY]"
      exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done
if $preview; then
  [[ -z "$identity" && -z "$profile" ]] || { echo "Preview cannot use distribution credentials." >&2; exit 2; }
else
  [[ "$identity" == 'Developer ID Application: '* && -n "$profile" ]] || {
    echo "Distribution requires --sign Developer-ID-identity and --notary-profile; use --unsigned-preview for a local preview." >&2
    exit 2
  }
fi
command -v xcodegen >/dev/null
xcodegen generate
args=(-project Pastport.xcodeproj -scheme Pastport -configuration Release -destination generic/platform=macOS -derivedDataPath .build/release-build build ONLY_ACTIVE_ARCH=NO "ARCHS=arm64 x86_64")
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
if ! $preview; then
  ditto -c -k --keepParent "$app" "$stage/notarize.zip"
  xcrun notarytool submit "$stage/notarize.zip" --keychain-profile "$profile" --wait
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
  xcrun notarytool submit "$output/$name.dmg" --keychain-profile "$profile" --wait
  xcrun stapler staple "$output/$name.dmg"
  xcrun stapler validate "$output/$name.dmg"
  spctl -a -vv --type open --context context:primary-signature "$output/$name.dmg"
fi
(cd "$output" && shasum -a 256 "$name.dmg" "$name.zip" > "$name-SHA256SUMS.txt")
printf 'Artifacts ready: %s (version %s, build %s)\n' "$output" "$version" "$build"
