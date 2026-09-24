#!/bin/bash
# Local-only install for the current CatCleaner checkout.
#
# This path intentionally does NOT require Developer ID, notarization, an Apple
# Developer Program membership, App Store distribution, or a GitHub release.
# It uses CatCleaner's dedicated self-signed local code-signing identity so
# TCC/FDA identity remains stable across rebuilds on this Mac.
#
# Usage: ./scripts/dev-install.sh

set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="CatCleaner"
APP_BUNDLE=".build/dmg/${APP_NAME}.app"
DEST="/Applications/${APP_NAME}.app"

BRANCH="$(git branch --show-current 2>/dev/null || echo "detached")"
DIRTY="$(git status --porcelain 2>/dev/null | head -1 | grep -q . && echo " + uncommitted changes" || true)"
VERSION="$(tr -d '[:space:]' < VERSION)"

echo "=== Local install: current checkout [${BRANCH}${DIRTY}] v${VERSION} ($(uname -m)) ==="

# Native-arch release build for this Mac.
BUILD_ARCHS="--arch $(uname -m)" ./scripts/build-dmg.sh --app-only

# Replace the ad-hoc build signature with CatCleaner's stable local identity.
./scripts/local-signing-identity.sh --ensure
./scripts/local-signing-identity.sh --sign "$APP_BUNDLE"
./scripts/verify-app-bundle.sh --native

# Quit the running app and its menu bar helper before swapping the bundle.
osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
pkill -x MacCleanMenu 2>/dev/null || true
pkill -x MacClean 2>/dev/null || true
sleep 1

echo "Installing to ${DEST}..."
rm -rf "$DEST"
ditto "$APP_BUNDLE" "$DEST"

# A local build copied from our own workspace should not acquire quarantine.
xattr -d com.apple.quarantine "$DEST" >/dev/null 2>&1 || true

codesign --verify --deep --strict "$DEST"
installed_authority="$(
  codesign -dv --verbose=4 "$DEST" 2>&1 |
    sed -n 's/^Authority=//p' |
    head -1
)"
[[ "$installed_authority" == "CatCleaner Local Code Signing" ]] || {
  echo "ERROR: installed app has unexpected signing authority: ${installed_authority:-none}" >&2
  exit 1
}

echo "Launching..."
open "$DEST"

# Launch smoke: allow AppKit a few seconds to initialize.
running=false
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if pgrep -x MacClean >/dev/null 2>&1; then
    running=true
    break
  fi
  sleep 1
done
[[ "$running" == "true" ]] || {
  echo "ERROR: CatCleaner did not remain running after launch" >&2
  exit 1
}

echo
echo "CATCLEANER_LOCAL_INSTALL_PASS"
echo "app=$DEST"
echo "version=$VERSION"
echo "signing_authority=$installed_authority"
echo "process=MacClean"
echo
echo "For the final exact-source gate, run:"
echo "  ./scripts/local-app-readiness.sh"
