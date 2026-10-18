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

# Ad-hoc signature so macOS treats it as a proper app (notifications, permissions).
codesign --force --sign - "$APP" >/dev/null

echo "Built $APP"
