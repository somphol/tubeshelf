#!/usr/bin/env bash
# One command that proves the project is healthy:
#   unit tests → headless checks → release app bundle → bundle sanity.
set -euo pipefail

cd "$(dirname "$0")/.."

echo "== 1/4  unit tests =="
swift test

echo
echo "== 2/4  headless checks =="
swift run -c debug tubeshelf-check

echo
echo "== 3/4  release build =="
CONFIG=release ./scripts/build-app.sh

echo
echo "== 4/4  bundle sanity =="
APP="dist/TubeShelf.app"
test -x "$APP/Contents/MacOS/TubeShelf" || { echo "missing executable"; exit 1; }
test -f "$APP/Contents/Resources/AppIcon.icns" || { echo "missing icon"; exit 1; }
plutil -lint "$APP/Contents/Info.plist"
codesign --verify --deep --strict "$APP" && echo "signature ok"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Contents/Info.plist")
echo "bundle id: $BUNDLE_ID"
echo
echo "All checks passed. Launch with: open $APP"
