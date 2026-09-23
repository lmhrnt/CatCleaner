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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

MODE="${1:---app}"
if [[ "$MODE" == "--test" ]]; then
  MODE="--tests"
fi
case "$MODE" in
  --app|--tests|--core-only) ;;
  *)
    echo "Usage: $0 [--app|--test|--tests|--core-only]" >&2
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

if ! RESOLVED_DEVELOPER_DIR="$("$SCRIPT_DIR/resolve-xcode.sh")"; then
  if [[ "$MODE" == "--tests" ]]; then
    echo "The CatCleaner test suite also requires XCTest from full Xcode." >&2
  fi
  exit 78
fi
SELECTED_DEVELOPER_DIR="$RESOLVED_DEVELOPER_DIR"

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
