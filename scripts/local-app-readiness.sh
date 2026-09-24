#!/bin/bash
# Final readiness gate for CatCleaner's local-only /Applications install.
# No Apple Developer Program, Developer ID, notarization, App Store, or GitHub
# release is required by this gate.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

APP="/Applications/CatCleaner.app"
MAIN="$APP/Contents/MacOS/MacClean"
MENU="$APP/Contents/Library/LoginItems/MacCleanMenu.app/Contents/MacOS/MacCleanMenu"
EXPECTED_IDENTITY="CatCleaner Local Code Signing"

failures=0
pass() { printf 'PASS  %-24s %s\n' "$1" "$2"; }
block() { printf 'BLOCK %-24s %s\n' "$1" "$2"; failures=$((failures + 1)); }
info() { printf 'INFO  %-24s %s\n' "$1" "$2"; }

if [[ -n "$(git status --porcelain)" ]]; then
  block git_worktree "working tree is not clean"
else
  pass git_worktree "$(git rev-parse --short=12 HEAD)"
fi

if "$SCRIPT_DIR/check-xcode-qualification.py" >/dev/null 2>&1; then
  pass xcode_qualification "full Xcode receipt matches current HEAD/tree"
else
  block xcode_qualification "run ./scripts/xcode-qualification.sh --full on this exact clean source"
fi

if "$SCRIPT_DIR/local-signing-identity.sh" --check >/dev/null 2>&1; then
  pass local_signing_identity "$EXPECTED_IDENTITY"
else
  block local_signing_identity "CatCleaner local code-signing identity unavailable"
fi

if [[ -d "$APP" && -x "$MAIN" && -x "$MENU" ]]; then
  pass installed_app "$APP"
else
  block installed_app "expected installed app/helper missing"
fi

if [[ -d "$APP" ]]; then
  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null || true)"
  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || true)"
  expected_version="$(tr -d '[:space:]' < VERSION)"

  if [[ "$bundle_id" == "com.catcleaner.app" ]]; then
    pass bundle_identity "$bundle_id"
  else
    block bundle_identity "unexpected bundle id: ${bundle_id:-missing}"
  fi

  if [[ "$version" == "$expected_version" ]]; then
    pass app_version "$version"
  else
    block app_version "installed=${version:-missing} source=$expected_version"
  fi

  if codesign --verify --deep --strict "$APP" >/dev/null 2>&1; then
    authority="$(codesign -dv --verbose=4 "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
    if [[ "$authority" == "$EXPECTED_IDENTITY" ]]; then
      pass codesign "$authority"
    else
      block codesign "unexpected authority: ${authority:-none}"
    fi
  else
    block codesign "codesign --verify --deep --strict failed"
  fi

  native_arch="$(uname -m)"
  main_archs="$(lipo -archs "$MAIN" 2>/dev/null || true)"
  menu_archs="$(lipo -archs "$MENU" 2>/dev/null || true)"
  if grep -Eq "(^| )$native_arch( |$)" <<<"$main_archs" &&
     grep -Eq "(^| )$native_arch( |$)" <<<"$menu_archs"; then
    pass native_architecture "main=[$main_archs] menu=[$menu_archs]"
  else
    block native_architecture "native=$native_arch main=[$main_archs] menu=[$menu_archs]"
  fi

  if xattr -p com.apple.quarantine "$APP" >/dev/null 2>&1; then
    block quarantine "local install unexpectedly has com.apple.quarantine"
  else
    pass quarantine "absent"
  fi
fi

if pgrep -x MacClean >/dev/null 2>&1; then
  pass launch_smoke "MacClean process is running"
else
  block launch_smoke "MacClean is not running"
fi

info public_distribution "NOT_REQUIRED for local-only use"
info developer_id "NOT_REQUIRED"
info notarization "NOT_REQUIRED"
info app_store "NOT_REQUIRED"

echo
echo "required_blockers=$failures"
if [[ "$failures" -eq 0 ]]; then
  echo "verdict=LOCAL_APP_READY"
  exit 0
fi
echo "verdict=HOLD"
exit 2
