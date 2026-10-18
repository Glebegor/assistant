#!/usr/bin/env bash
# Builds a release version of RightHand and installs it into /Applications.
# Usage: scripts/install.sh
set -euo pipefail

cd "$(dirname "$0")/.."

scripts/build-app.sh release

DEST="/Applications"
# Fall back to ~/Applications if /Applications is not writable for this user.
if [ ! -w "$DEST" ]; then
    DEST="$HOME/Applications"
    mkdir -p "$DEST"
fi

# Quit the running copy (debug or installed) so it can be replaced.
osascript -e 'quit app "RightHand"' 2>/dev/null || true
pkill -x RightHand 2>/dev/null || true
sleep 1

rm -rf "$DEST/RightHand.app"
ditto build/RightHand.app "$DEST/RightHand.app"
echo "Installed $DEST/RightHand.app"

open "$DEST/RightHand.app"
