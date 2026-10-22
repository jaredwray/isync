#!/usr/bin/env bash
# Build build/iSync.app from the ISyncApp product, then sign it with the hardened runtime.
#
# Environment:
#   CONFIGURATION  debug or release (default: release)
#   SIGN_IDENTITY  a codesign identity (default: "-", an ad-hoc signature)
#
# macOS keeps privacy permissions for each code signature. With an ad-hoc
# signature, each new build asks for Full Disk Access and Contacts again.
# Use a stable identity, such as "Developer ID Application: <name>", to keep them.
set -euo pipefail

cd "$(dirname "$0")/.."

configuration="${CONFIGURATION:-release}"
identity="${SIGN_IDENTITY:--}"
app="build/iSync.app"

swift build --configuration "$configuration" --product ISyncApp
bin_dir="$(swift build --configuration "$configuration" --show-bin-path)"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/ISyncApp" "$app/Contents/MacOS/iSync"
cp Resources/Info.plist "$app/Contents/Info.plist"
plutil -lint "$app/Contents/Info.plist" >/dev/null

sign_args=(--force --options runtime --entitlements Resources/iSync.entitlements --sign "$identity")
if [[ "$identity" != "-" ]]; then
  sign_args+=(--timestamp)
fi
codesign "${sign_args[@]}" "$app"
codesign --verify --strict --verbose=2 "$app"

echo "Built $app"
