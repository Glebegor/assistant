#!/usr/bin/env bash
# Works out the next version from commit messages since the last v* tag (semantic release).
#   Breaking:                  → MAJOR  (2.3.5 → 3.0.0)
#   Feature: / Enhancement:    → MINOR  (1.4.6 → 1.5.0)
#   Feet: / Fix: / HotFix:     → PATCH  (1.1.1 → 1.1.2)
#   Perf: Refactor: Test: Docs: CI: Build: → no release on their own
#
# Usage: scripts/next-version.sh           prints the version, or nothing if there is nothing to release
#        scripts/next-version.sh --notes   prints release notes (Markdown)
set -euo pipefail

cd "$(dirname "$0")/.."

LAST_TAG="$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)"
SUBJECTS="$(git log --no-merges --format=%s "${LAST_TAG:+$LAST_TAG..}HEAD")"

# Commit subjects of one type, without the "Type: " prefix.
subjects_of() {
    grep -E "^($1): " <<<"$SUBJECTS" | sed -E 's/^[A-Za-z]+: //' || true
}

if [ "${1:-}" = "--notes" ]; then
    section() {
        local lines
        lines="$(subjects_of "$2")"
        [ -n "$lines" ] && printf '### %s\n\n%s\n\n' "$1" "$(sed 's/^/- /' <<<"$lines")"
        return 0
    }
    section "Breaking changes" "Breaking"
    section "Features" "Feature"
    section "Enhancements" "Enhancement"
    section "Fixes" "HotFix|Fix"
    section "Other changes" "Feet|Perf|Refactor"
    exit 0
fi

CURRENT="${LAST_TAG#v}"
IFS=. read -r MAJOR MINOR PATCH <<<"${CURRENT:-0.0.0}"

if [ -n "$(subjects_of "Breaking")" ]; then
    echo "$((MAJOR + 1)).0.0"
elif [ -n "$(subjects_of "Feature|Enhancement")" ]; then
    echo "$MAJOR.$((MINOR + 1)).0"
elif [ -n "$(subjects_of "Feet|Fix|HotFix")" ]; then
    echo "$MAJOR.$MINOR.$((PATCH + 1))"
fi
