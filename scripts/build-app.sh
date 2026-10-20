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

# Release builds pass VERSION=x.y.z (see scripts/package.sh). Local builds use the latest
# release tag, so the update check only offers versions that are really newer.
if [ -z "${VERSION:-}" ]; then
    # Tags made by the release workflow live on GitHub; fetch them quietly (offline is fine).
    git fetch --tags --quiet 2>/dev/null &
    FETCH=$!; ( sleep 5; kill $FETCH 2>/dev/null ) & wait $FETCH 2>/dev/null || true
    NEXT="$("$(dirname "$0")/next-version.sh" 2>/dev/null || true)"
    LATEST="$(git tag -l 'v[0-9]*' --sort=-v:refname | head -1 | sed 's/^v//')"
    # The higher of "what this code would be released as" and "the newest release".
    VERSION="$(printf '%s\n%s\n' "$NEXT" "$LATEST" | grep . | sort -V | tail -1)"
fi
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

# Sign with the local certificate, so macOS keeps permissions (Desktop folder, browser control,
# Keychain) between builds. It is created on the first build; CI uses an ad-hoc signature.
IDENTITY="RightHand Local Signing"
if [ -z "${CI:-}" ] && ! security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    "$(dirname "$0")/setup-signing.sh"
fi
if [ -z "${CI:-}" ] && security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    codesign --force --sign "$IDENTITY" "$APP" >/dev/null
else
    codesign --force --sign - "$APP" >/dev/null
fi

echo "Built $APP"
