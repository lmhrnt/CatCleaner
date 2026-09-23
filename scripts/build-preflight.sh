#!/bin/bash
# CatCleaner build environment preflight.
#
# Usage:
#   ./scripts/build-preflight.sh --app       # SwiftUI app/menu build
#   ./scripts/build-preflight.sh --tests     # XCTest suite
#   ./scripts/build-preflight.sh --core-only # Foundation/core package work
#
# This script never changes xcode-select and never installs Xcode.

set -euo pipefail

MODE="${1:---app}"
case "$MODE" in
  --app|--tests|--core-only) ;;
  *)
    echo "Usage: $0 [--app|--tests|--core-only]" >&2
    exit 64
    ;;
esac

SELECTED_DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || true)}"

if [[ "$MODE" == "--core-only" ]]; then
  if ! command -v swift >/dev/null 2>&1; then
    echo "ERROR: Swift toolchain not found." >&2
    exit 69
  fi
  echo "CatCleaner preflight: CORE_OK"
  echo "developer_dir=${SELECTED_DEVELOPER_DIR:-unknown}"
  swift --version | head -2
  exit 0
fi

is_full_xcode_dir() {
  local dir="$1"
  [[ -n "$dir" ]] || return 1
  [[ "$dir" == *.app/Contents/Developer ]] || return 1
  [[ -x "$dir/usr/bin/xcodebuild" ]] || return 1
  [[ -d "$dir/Platforms/MacOSX.platform" ]] || return 1
}

find_full_xcode() {
  local candidate
  for candidate in     "/Applications/Xcode.app/Contents/Developer"     "/Applications/Xcode-beta.app/Contents/Developer"     "$HOME/Applications/Xcode.app/Contents/Developer"
  do
    if is_full_xcode_dir "$candidate"; then
      printf '%s
' "$candidate"
      return 0
    fi
  done
  return 1
}

if ! is_full_xcode_dir "$SELECTED_DEVELOPER_DIR"; then
  FOUND_XCODE="$(find_full_xcode || true)"
  echo "ERROR: CatCleaner SwiftUI app builds require full Xcode." >&2
  echo "Current developer directory: ${SELECTED_DEVELOPER_DIR:-<none>}" >&2
  if [[ -n "$FOUND_XCODE" ]]; then
    echo "Full Xcode was found at: $FOUND_XCODE" >&2
    echo "Re-run without changing global xcode-select:" >&2
    echo "  DEVELOPER_DIR=\"$FOUND_XCODE\" $0 $MODE" >&2
  else
    echo "No full Xcode installation was found in /Applications or ~/Applications." >&2
    echo "Apple Command Line Tools alone do not ship the SwiftUIMacros plugin used by SwiftUI." >&2
    if [[ "$MODE" == "--tests" ]]; then
      echo "The test suite also requires XCTest from full Xcode." >&2
    fi
  fi
  echo "Core-only work remains available:" >&2
  echo "  $0 --core-only" >&2
  echo "  swift build --target MacCleanKit" >&2
  exit 78
fi

SWIFT_UI_MACRO="$SELECTED_DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib"
if [[ ! -f "$SWIFT_UI_MACRO" ]]; then
  echo "ERROR: Full Xcode is selected, but SwiftUIMacros is missing:" >&2
  echo "  $SWIFT_UI_MACRO" >&2
  echo "The Xcode installation may be incomplete or incompatible." >&2
  exit 78
fi

if [[ "$MODE" == "--tests" ]]; then
  XCTEST_FRAMEWORK="$SELECTED_DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework"
  if [[ ! -d "$XCTEST_FRAMEWORK" ]]; then
    echo "ERROR: XCTest framework is missing:" >&2
    echo "  $XCTEST_FRAMEWORK" >&2
    echo "The Xcode installation may be incomplete." >&2
    exit 78
  fi
fi

echo "CatCleaner preflight: ${MODE#--}_OK"
echo "developer_dir=$SELECTED_DEVELOPER_DIR"
DEVELOPER_DIR="$SELECTED_DEVELOPER_DIR" xcodebuild -version
