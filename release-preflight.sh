#!/usr/bin/env bash
set -euo pipefail

app_path="${1:-.build/xcode/Build/Products/Release/Pastport.app}"
if [[ ! -d "$app_path" ]]; then
  echo "missing app: $app_path" >&2
  exit 1
fi

details="$(codesign -dv --verbose=4 "$app_path" 2>&1)"
printf '%s\n' "$details" | grep -E '^(Identifier|TeamIdentifier|Signature|Runtime Version)=' || true
if grep -q '^Signature=adhoc' <<<"$details"; then
  echo "release preflight failed: ad-hoc signature is not distributable" >&2
  exit 1
fi
if ! grep -q 'Authority=Developer ID Application:' <<<"$details"; then
  echo "release preflight failed: direct distribution requires Developer ID Application" >&2
  exit 1
fi
codesign --verify --deep --strict --verbose=2 "$app_path"
xcrun stapler validate "$app_path"
spctl -a -vv --type execute "$app_path"
