#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${TMPDIR:-/tmp}/Hex-local-build}"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
APP="$DERIVED_DATA_PATH/Build/Products/Release/Hex.app"
TARGET="$INSTALL_DIR/Hex.app"

cd "$ROOT"

# Build with the project's DEVELOPMENT_TEAM and automatic signing so the app
# gets a stable, team-anchored code signature. A stable signature keeps TCC
# grants (Accessibility, Input Monitoring, Microphone) valid across reinstalls,
# unlike ad-hoc signing whose cdhash changes on every build.
xcodebuild \
  -project Hex.xcodeproj \
  -scheme Hex \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -skipMacroValidation \
  build

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
