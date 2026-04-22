#!/usr/bin/env bash
# Builds the release .app bundle and packages it for distribution as both a
# .zip (universal) and a .dmg (nicer UX on download). Artifacts land in dist/.
#
# Usage:
#   bash Scripts/release.sh
#   → dist/ClaudeCommandCenter.zip
#   → dist/ClaudeCommandCenter.dmg
set -euo pipefail

APP_NAME="Claude Command Center"
BIN_NAME="ClaudeCommandCenter"
BUNDLE_ID="com.saurabh.claude-command-center"
VERSION="${VERSION:-1.0.0}"
MIN_MACOS="14.0"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
DIST_DIR="$ROOT/dist"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RES_DIR="$CONTENTS/Resources"

echo "▶ Building release binary…"
cd "$ROOT"
swift build -c release

echo "▶ Assembling $APP_NAME.app…"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"
cp ".build/release/$BIN_NAME" "$MACOS_DIR/$BIN_NAME"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>          <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>                <string>$BIN_NAME</string>
    <key>CFBundleDisplayName</key>         <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>          <string>$BIN_NAME</string>
    <key>CFBundleVersion</key>             <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>  <string>$VERSION</string>
    <key>CFBundlePackageType</key>         <string>APPL</string>
    <key>LSMinimumSystemVersion</key>      <string>$MIN_MACOS</string>
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

echo "▶ Ad-hoc code signing…"
codesign --force --deep --sign - "$APP_DIR"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

echo "▶ Creating zip…"
# `ditto` preserves resource forks + extended attributes correctly on macOS.
ditto -c -k --keepParent "$APP_DIR" "$DIST_DIR/ClaudeCommandCenter.zip"

echo "▶ Creating dmg…"
DMG_STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_DIR" "$DMG_STAGING/"
# Symlink /Applications into the DMG so users can drag-and-drop.
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$DIST_DIR/ClaudeCommandCenter.dmg" \
    > /dev/null

echo
echo "✓ Artifacts ready in dist/"
ls -lh "$DIST_DIR"
echo
echo "Next steps:"
echo "  1. Create a GitHub release: gh release create v$VERSION dist/* --generate-notes"
echo "  2. Share the release URL or the remote-install one-liner from Scripts/remote-install.sh"
