#!/bin/bash
# Verify that CatCleaner runtime/release execution surfaces do not regress to
# upstream Mac Sai identifiers. Policy/test/checker files are intentionally not
# scanned because they must be allowed to name the forbidden markers they guard.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$ROOT"

if ! command -v rg >/dev/null 2>&1; then
  echo "CATCLEANER_RUNTIME_IDENTITY_FAIL reason=ripgrep_missing" >&2
  exit 127
fi

forbidden="$(
  rg -n     'com\.macclean|macclean://|brew upgrade --cask mac-sai|Mac Sai\.app|MacSai-'     Sources     Package.swift     scripts/build-dmg.sh     scripts/dev-install.sh     scripts/install.sh     scripts/uninstall.sh     scripts/setup-homebrew-tap.sh     2>/dev/null || true
)"

if [[ -n "$forbidden" ]]; then
  printf '%s\n' "$forbidden" >&2
  echo "CATCLEANER_RUNTIME_IDENTITY_FAIL" >&2
  exit 1
fi

echo "CATCLEANER_RUNTIME_IDENTITY_PASS"
