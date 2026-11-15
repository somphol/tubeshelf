#!/usr/bin/env bash
# Installs a LaunchAgent that starts `fm serve` at login, so the opt-in local AI
# endpoint still answers after a reboot.
#
# This agent targets the on-device `system` model. Private Cloud Compute (PCC)
# refuses to run outside Terminal.app, so it cannot be launched this way; use
# `fm serve` in a Terminal window for PCC, or Ollama via `brew services`.
set -euo pipefail

LABEL="studio.somphol.tubeshelf.fm-serve"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/TubeShelf"
PORT="${1:-1976}"

if ! command -v fm >/dev/null 2>&1; then
  echo "fm was not found. It ships with macOS 27, so there is nothing to install." >&2
  exit 1
fi

mkdir -p "$HOME/Library/LaunchAgents" "$LOG_DIR"

cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/fm</string>
    <string>serve</string>
    <string>--port</string>
    <string>$PORT</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
  <key>StandardOutPath</key>
  <string>$LOG_DIR/fm-serve.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/fm-serve.log</string>
</dict>
</plist>
PLIST_EOF

plutil -lint "$PLIST" >/dev/null
launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$UID" "$PLIST"

echo "Installed $LABEL → http://127.0.0.1:$PORT/v1"
echo "Logs: $LOG_DIR/fm-serve.log"
echo "Remove with: launchctl bootout gui/$UID/$LABEL && rm \"$PLIST\""
echo "Note: PCC needs Terminal.app; this agent is for the on-device system model."
