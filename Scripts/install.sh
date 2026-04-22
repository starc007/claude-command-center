#!/usr/bin/env bash
# Builds a release binary, wraps it in a minimal .app bundle, code-signs ad-hoc,
# and installs it into /Applications. Re-run to upgrade in place.
set -euo pipefail

APP_NAME="Claude Command Center"
BUNDLE_ID="com.saurabh.claude-command-center"
BIN_NAME="ClaudeCommandCenter"
VERSION="1.0.0"
MIN_MACOS="14.0"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
APP_DIR="$BUILD_DIR/${APP_NAME}.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RES_DIR="$CONTENTS/Resources"

echo "==> Building release binary (takes ~30s first time)"
cd "$ROOT"
swift build -c release

echo "==> Assembling ${APP_NAME}.app"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"

cp ".build/release/${BIN_NAME}" "${MACOS_DIR}/${BIN_NAME}"

if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$RES_DIR/AppIcon.icns"
fi

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>          <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>                <string>${BIN_NAME}</string>
    <key>CFBundleDisplayName</key>         <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>          <string>${BIN_NAME}</string>
    <key>CFBundleIconFile</key>            <string>AppIcon</string>
    <key>CFBundleVersion</key>             <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>  <string>${VERSION}</string>
    <key>CFBundlePackageType</key>         <string>APPL</string>
    <key>LSMinimumSystemVersion</key>      <string>${MIN_MACOS}</string>
    <key>NSHighResolutionCapable</key>     <true/>
    <key>LSUIElement</key>                 <false/>
    <key>NSSupportsAutomaticTermination</key> <true/>
    <key>NSAppleEventsUsageDescription</key>
        <string>Claude Command Center needs to control Terminal / iTerm / Ghostty to resume your Claude Code sessions.</string>
    <key>NSUserNotificationUsageDescription</key>
        <string>Claude Command Center fires a notification when a Claude Code session finishes working.</string>
</dict>
</plist>
PLIST

echo "==> Ad-hoc code signing"
codesign --force --deep --sign - "$APP_DIR"

echo "==> Installing to /Applications"
if [ -d "/Applications/${APP_NAME}.app" ]; then
    rm -rf "/Applications/${APP_NAME}.app"
fi
cp -R "$APP_DIR" "/Applications/"

echo
echo "OK: Installed to /Applications/${APP_NAME}.app"
echo
echo "Launch from Spotlight (Cmd+Space, type 'Claude Command Center')."
echo "First launch Gatekeeper will block unsigned binary. Either:"
echo "  - right-click the app in Finder -> Open -> Open"
echo "  - or: xattr -dr com.apple.quarantine \"/Applications/${APP_NAME}.app\""
