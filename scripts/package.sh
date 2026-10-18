#!/usr/bin/env bash
# Builds a release RightHand.app with the given version and zips it for download.
# Usage: scripts/package.sh [version]   (default: next version from commit messages)
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-$(scripts/next-version.sh)}"
VERSION="${VERSION:-0.0.0}"

VERSION="$VERSION" scripts/build-app.sh release

ZIP="build/RightHand-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent build/RightHand.app "$ZIP"
echo "Packaged $ZIP"
