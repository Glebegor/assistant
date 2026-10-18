#!/usr/bin/env bash
# Builds the app, stops any running copy and launches the new one.
set -euo pipefail

cd "$(dirname "$0")/.."

scripts/build-app.sh "${1:-debug}"
pkill -x RightHand 2>/dev/null || true
open build/RightHand.app
