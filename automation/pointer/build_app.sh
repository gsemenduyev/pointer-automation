#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="PointerAutomation"
APP_PATH="$SCRIPT_DIR/${APP_NAME}.app"
EXECUTABLE_PATH="$APP_PATH/Contents/MacOS/${APP_NAME}"
PLIST_PATH="$APP_PATH/Contents/Info.plist"
SOURCE_PATH="$SCRIPT_DIR/PointerAutomation.swift"

echo "Building ${APP_NAME}.app"

mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

swiftc -O "$SOURCE_PATH" -o "$EXECUTABLE_PATH"
chmod +x "$EXECUTABLE_PATH"

cat > "$PLIST_PATH" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>PointerAutomation</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.pointer-automation</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Pointer Automation</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc sign for more stable macOS permission handling across rebuilds.
codesign --force --deep --sign - "$APP_PATH" >/dev/null 2>&1 || true

echo "Built: $APP_PATH"
