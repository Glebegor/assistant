#!/usr/bin/env bash
# Releases everything on dev: merges dev into master and pushes it.
# GitHub Actions then builds RightHand and publishes the GitHub release
# (see .github/workflows/release.yml).
set -euo pipefail

cd "$(dirname "$0")/.."

if [ -n "$(git status --porcelain)" ]; then
    echo "Commit or stash your changes first." >&2
    exit 1
fi

git fetch --tags origin
git checkout -q dev
git pull -q --ff-only

VERSION="$(scripts/next-version.sh)"
if [ -z "$VERSION" ]; then
    echo "Nothing to release: no Feature/Enhancement/Fix/HotFix/Feet/Breaking commits since the last release."
    exit 0
fi

echo "Releasing v$VERSION:"
echo
scripts/next-version.sh --notes

git checkout -q master
git pull -q --ff-only
git merge -q --no-ff dev -m "Build: Release v$VERSION."
git push -q origin master

# Bring the release merge back to dev, so the release tag is part of dev's history too.
git checkout -q dev
git merge -q --ff-only master
git push -q origin dev

echo "Pushed master. GitHub Actions is now building and publishing v$VERSION."
