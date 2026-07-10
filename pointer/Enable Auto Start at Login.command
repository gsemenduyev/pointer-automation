#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAUNCHER_SCRIPT="$SCRIPT_DIR/Launch Pointer Automation.command"
AGENT_DIR="$HOME/Library/LaunchAgents"
AGENT_PLIST="$AGENT_DIR/com.local.pointerautomation.plist"

if [ ! -f "$LAUNCHER_SCRIPT" ]; then
  echo "Error: launcher script not found at: $LAUNCHER_SCRIPT" >&2
  exit 1
fi

mkdir -p "$AGENT_DIR"

cat > "$AGENT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.local.pointerautomation</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$LAUNCHER_SCRIPT</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
  <key>StandardOutPath</key>
  <string>/tmp/com.local.pointerautomation.out.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/com.local.pointerautomation.err.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)/com.local.pointerautomation" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$AGENT_PLIST"
launchctl kickstart -k "gui/$(id -u)/com.local.pointerautomation"

echo "Auto-start enabled."
echo "LaunchAgent file: $AGENT_PLIST"
echo "Use logs if needed:"
echo "  /tmp/com.local.pointerautomation.out.log"
echo "  /tmp/com.local.pointerautomation.err.log"
