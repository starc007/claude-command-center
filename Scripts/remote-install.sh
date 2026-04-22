#!/usr/bin/env bash
# Remote installer — users run this directly from GitHub, no clone needed:
#
#   curl -fsSL https://raw.githubusercontent.com/<user>/<repo>/main/Scripts/remote-install.sh | bash
#
# Edit GITHUB_REPO below to point at your fork before publishing.
set -euo pipefail

APP_NAME="Claude Command Center"
GITHUB_REPO="${GITHUB_REPO:-saurabh/claude-command-center}"   # user/repo
ASSET="ClaudeCommandCenter.zip"

URL="https://github.com/$GITHUB_REPO/releases/latest/download/$ASSET"

echo "▶ Downloading $APP_NAME from $GITHUB_REPO…"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if ! curl -fsSL "$URL" -o "$TMP/app.zip"; then
    echo "✗ Download failed: $URL"
    echo "  Double-check that a release exists at https://github.com/$GITHUB_REPO/releases/latest"
    exit 1
fi

echo "▶ Unpacking…"
# `ditto -x -k` is the macOS-native inverse of `ditto -c -k`.
ditto -x -k "$TMP/app.zip" "$TMP/unpacked"

SRC="$TMP/unpacked/$APP_NAME.app"
if [ ! -d "$SRC" ]; then
    echo "✗ Couldn't find $APP_NAME.app inside the downloaded zip."
    exit 1
fi

echo "▶ Installing to /Applications…"
if [ -d "/Applications/$APP_NAME.app" ]; then
    rm -rf "/Applications/$APP_NAME.app"
fi
cp -R "$SRC" "/Applications/"

echo "▶ Clearing quarantine flag so Gatekeeper won't block first launch…"
xattr -dr com.apple.quarantine "/Applications/$APP_NAME.app" 2>/dev/null || true

echo
echo "✓ Installed to /Applications/$APP_NAME.app"
echo "  Launch it from Spotlight (⌘Space → \"Claude Command Center\")"
