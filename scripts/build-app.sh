#!/usr/bin/env bash
# Builds TubeShelf.app into dist/. Idempotent; safe to re-run.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${CONFIG:-release}"
APP="dist/TubeShelf.app"

swift build -c "$CONFIG" --product TubeShelf

mkdir -p "dist"
if [[ ! -f Support/AppIcon.icns ]]; then
    echo "Rendering icon…"
    swift scripts/make-icon.swift Support
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp ".build/$CONFIG/TubeShelf" "$APP/Contents/MacOS/TubeShelf"
cp "Support/Info.plist" "$APP/Contents/Info.plist"
cp "Support/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

chmod +x "$APP/Contents/MacOS/TubeShelf"

# Ad-hoc signature: enough for a locally built app, no developer account needed.
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "warning: ad-hoc signing failed; the app still runs locally"

echo "Built $APP"
