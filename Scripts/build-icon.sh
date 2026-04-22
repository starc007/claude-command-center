#!/usr/bin/env bash
# Regenerates Resources/AppIcon.icns from the Swift icon generator.
# Commit the resulting .icns so normal installs never have to run this.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
ICONSET="$BUILD_DIR/AppIcon.iconset"
OUT_DIR="$ROOT/Resources"
OUT="$OUT_DIR/AppIcon.icns"

mkdir -p "$OUT_DIR"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

echo "==> Rendering iconset PNGs"
swift "$ROOT/Scripts/generate-icon.swift" "$ICONSET"

echo "==> Packing .icns"
iconutil -c icns "$ICONSET" -o "$OUT"

echo "OK: wrote $OUT"
