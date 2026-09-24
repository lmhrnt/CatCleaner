#!/bin/bash
# Verify a locally built CatCleaner.app bundle without modifying it.
#
# Usage:
#   ./scripts/verify-app-bundle.sh --native
#   ./scripts/verify-app-bundle.sh --universal
#
# The bundle is expected at .build/dmg/CatCleaner.app.

set -euo pipefail

MODE="${1:---native}"
case "$MODE" in
  --native|--universal) ;;
  *)
    echo "Usage: $0 [--native|--universal]" >&2
    exit 64
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$ROOT"

APP=".build/dmg/CatCleaner.app"
MENU="$APP/Contents/Library/LoginItems/MacCleanMenu.app"
MAIN_EXE="$APP/Contents/MacOS/MacClean"
MENU_EXE="$MENU/Contents/MacOS/MacCleanMenu"

for path in "$APP" "$MENU" "$MAIN_EXE" "$MENU_EXE"; do
  [[ -e "$path" ]] || {
    echo "ERROR: expected app artifact missing: $path" >&2
    exit 1
  }
done

main_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
menu_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$MENU/Contents/Info.plist")"
[[ "$main_bundle_id" == "com.catcleaner.app" ]] || {
  echo "ERROR: unexpected main bundle id: $main_bundle_id" >&2
  exit 1
}
[[ "$menu_bundle_id" == "com.catcleaner.menu" ]] || {
  echo "ERROR: unexpected menu bundle id: $menu_bundle_id" >&2
  exit 1
}

/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes:0' "$APP/Contents/Info.plist" |
  grep -Fx 'catcleaner' >/dev/null

/usr/libexec/PlistBuddy -c 'Print :CFBundleLocalizations' "$APP/Contents/Info.plist" |
  grep -F 'zh-Hant-TW' >/dev/null

app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
source_version="$(tr -d '[:space:]' < VERSION)"
[[ "$app_version" == "$source_version" ]] || {
  echo "ERROR: app bundle version drift: app=$app_version source=$source_version" >&2
  exit 1
}

codesign --verify --deep --strict "$APP"

main_archs="$(lipo -archs "$MAIN_EXE")"
menu_archs="$(lipo -archs "$MENU_EXE")"

case "$MODE" in
  --native)
    native_arch="$(uname -m)"
    grep -Eq "(^| )${native_arch}( |$)" <<<"$main_archs" || {
      echo "ERROR: main executable missing native arch $native_arch: $main_archs" >&2
      exit 1
    }
    grep -Eq "(^| )${native_arch}( |$)" <<<"$menu_archs" || {
      echo "ERROR: menu executable missing native arch $native_arch: $menu_archs" >&2
      exit 1
    }
    ;;
  --universal)
    for arch in arm64 x86_64; do
      grep -Eq "(^| )${arch}( |$)" <<<"$main_archs" || {
        echo "ERROR: main executable missing $arch: $main_archs" >&2
        exit 1
      }
      grep -Eq "(^| )${arch}( |$)" <<<"$menu_archs" || {
        echo "ERROR: menu executable missing $arch: $menu_archs" >&2
        exit 1
      }
    done
    ;;
esac

if find "$APP" -type f -print0 |
   xargs -0 strings 2>/dev/null |
   grep -E 'com\.macclean|macclean://|brew upgrade --cask mac-sai'
then
  echo "ERROR: upstream runtime identity leaked into CatCleaner.app" >&2
  exit 1
fi

echo "CATCLEANER_APP_BUNDLE_VERIFY_PASS mode=$MODE"
echo "app_version=$app_version"
echo "main_archs=$main_archs"
echo "menu_archs=$menu_archs"
echo "codesign=PASS"
