#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$SCRIPT_DIR/PointerAutomation.app"
APP_BIN="$APP_PATH/Contents/MacOS/PointerAutomation"

if [ ! -d "$APP_PATH" ] || [ ! -x "$APP_BIN" ]; then
  echo "App not built yet. Building now..."
  bash "$SCRIPT_DIR/build_app.sh"
fi

if [ -f "$APP_BIN" ]; then
  chmod +x "$APP_BIN"
fi

xattr -d com.apple.quarantine "$APP_PATH" 2>/dev/null || true

pkill -f "$APP_BIN" 2>/dev/null || true
sleep 1

open "$APP_PATH"

osascript -e 'display notification "Look for the icon at the top-right menu bar." with title "Pointer Automation launched"'
