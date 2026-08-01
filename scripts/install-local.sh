#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${TMPDIR:-/tmp}/Hex-local-build}"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
APP="$DERIVED_DATA_PATH/Build/Products/Release/Hex.app"
TARGET="$INSTALL_DIR/Hex.app"
ENTITLEMENTS="$(mktemp "${TMPDIR:-/tmp}/Hex-entitlements.XXXXXX")"

cleanup() {
  rm -f "$ENTITLEMENTS"
}
trap cleanup EXIT

cd "$ROOT"

xcodebuild \
  -project Hex.xcodeproj \
  -scheme Hex \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -skipMacroValidation \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
cp Hex/Hex.entitlements "$ENTITLEMENTS"
/usr/libexec/PlistBuddy -c "Set :com.apple.security.temporary-exception.mach-lookup.global-name:0 $BUNDLE_ID-spks" "$ENTITLEMENTS"
/usr/libexec/PlistBuddy -c "Set :com.apple.security.temporary-exception.mach-lookup.global-name:1 $BUNDLE_ID-spki" "$ENTITLEMENTS"

# Ad-hoc signing keeps this local build independent from any Apple Developer team.
codesign --force --deep --sign - --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

# Quit the running copy before replacement so `open` starts this build rather
# than leaving the previous executable in memory.
osascript -e 'tell application id "me.aliou.Hex" to quit' >/dev/null 2>&1 || true
for _ in {1..20}; do
  pgrep -x Hex >/dev/null || break
  sleep 0.25
done
if pgrep -x Hex >/dev/null; then
  echo "Hex did not quit; close it and run this command again." >&2
  exit 1
fi

rm -rf "$TARGET"
ditto "$APP" "$TARGET"
codesign --verify --deep --strict --verbose=2 "$TARGET"
open "$TARGET"

echo "Installed and launched $TARGET"
