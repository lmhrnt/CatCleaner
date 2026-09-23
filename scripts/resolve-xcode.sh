#!/bin/bash
# Resolve a full Xcode developer directory without changing global xcode-select.
#
# Prints exactly one path on success. Exit 78 when no usable full Xcode exists.

set -euo pipefail

is_full_xcode_dir() {
  local dir="$1"
  [[ -n "$dir" ]] || return 1
  [[ "$dir" == *.app/Contents/Developer ]] || return 1
  [[ -x "$dir/usr/bin/xcodebuild" ]] || return 1
  [[ -d "$dir/Platforms/MacOSX.platform" ]] || return 1
}

selected="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || true)}"
if is_full_xcode_dir "$selected"; then
  printf '%s\n' "$selected"
  exit 0
fi

for candidate in \
  "/Applications/Xcode.app/Contents/Developer" \
  "/Applications/Xcode-beta.app/Contents/Developer" \
  "$HOME/Applications/Xcode.app/Contents/Developer"
do
  if is_full_xcode_dir "$candidate"; then
    printf '%s\n' "$candidate"
    exit 0
  fi
done

echo "ERROR: full Xcode is required for CatCleaner SwiftUI/XCTest work." >&2
echo "Current developer directory: ${selected:-<none>}" >&2
echo "No usable Xcode.app was found in /Applications or ~/Applications." >&2
echo "Apple Command Line Tools alone can still build MacCleanKit:" >&2
echo "  swift build --target MacCleanKit" >&2
exit 78
