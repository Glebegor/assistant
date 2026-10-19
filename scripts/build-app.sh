#!/usr/bin/env bash
# Builds RightHand.app into ./build.
# Usage: scripts/build-app.sh [debug|release]   (default: debug)
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
APP="build/RightHand.app"

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/RightHand" "$APP/Contents/MacOS/RightHand"
cp Support/Info.plist "$APP/Contents/Info.plist"
# Interface translations (en, uk, cs, ru).
cp -R Support/Localization/*.lproj "$APP/Contents/Resources/"

# Release builds pass VERSION=x.y.z (see scripts/package.sh).
if [ -n "${VERSION:-}" ]; then
    plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
    plutil -replace CFBundleVersion -string "$(git rev-list --count HEAD)" "$APP/Contents/Info.plist"
fi

# App icon: turn assets/icon.png into AppIcon.icns with all the sizes macOS needs.
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size assets/icon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) assets/icon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

# Ad-hoc signature so macOS treats it as a proper app (notifications, permissions).
codesign --force --sign - "$APP" >/dev/null

echo "Built $APP"
