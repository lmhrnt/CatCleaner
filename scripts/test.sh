#!/bin/bash
# Run CatCleaner XCTest only after verifying a complete Xcode test toolchain.
# This script never changes xcode-select and never installs Xcode.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

python3 "${SCRIPT_DIR}/check-process-pipe-order.py"
export DEVELOPER_DIR="$("${SCRIPT_DIR}/resolve-xcode.sh")"
"${SCRIPT_DIR}/build-preflight.sh" --tests

exec swift test "$@"
