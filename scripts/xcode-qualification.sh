#!/bin/bash
# One-shot local qualification after a full Xcode installation becomes available.
#
# This script is intentionally local-only:
# - never changes global xcode-select
# - never configures Git remotes
# - never imports signing identities
# - never notarizes or publishes
#
# Exit codes:
#   0  Full local Xcode qualification passed.
#   64 Invalid arguments.
#   78 Full/usable Xcode is not available.

set -euo pipefail

MODE="${1:---full}"
case "$MODE" in
  --quick|--full) ;;
  *)
    echo "Usage: $0 [--quick|--full]" >&2
    exit 64
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$ROOT"

DEVELOPER_DIR="$("${SCRIPT_DIR}/resolve-xcode.sh")"
export DEVELOPER_DIR

if [[ "$MODE" == "--full" ]]; then
  dirty="$(git status --porcelain)"
  if [[ -n "$dirty" ]]; then
    echo "ERROR: --full qualification requires a clean Git working tree." >&2
    printf '%s\n' "$dirty" >&2
    exit 65
  fi
fi

echo "CatCleaner Xcode qualification"
echo "repo=$ROOT"
echo "mode=$MODE"
echo "developer_dir=$DEVELOPER_DIR"
echo

echo "== toolchain =="
xcodebuild -version
swift --version | head -2

echo
echo "== preflight =="
"${SCRIPT_DIR}/build-preflight.sh" --app
"${SCRIPT_DIR}/build-preflight.sh" --tests

echo
echo "== static release/security contracts =="
python3 "${SCRIPT_DIR}/check-release-contract.py"
python3 "${SCRIPT_DIR}/check-network-surface.py"
bash "${SCRIPT_DIR}/check-runtime-identity.sh"
bash "${SCRIPT_DIR}/check-version-sync.sh"
python3 "${SCRIPT_DIR}/check-process-pipe-order.py"

echo
echo "== XCTest with coverage =="
"${SCRIPT_DIR}/test.sh" --enable-code-coverage

PROF="$(find .build -name '*.profdata' -type f -print -quit)"
if [[ -z "$PROF" ]]; then
  echo "ERROR: XCTest completed without a coverage .profdata file." >&2
  exit 1
fi
echo "coverage_profile=$PROF"

if [[ "$MODE" == "--full" ]]; then
  echo
  echo "== full local feature readiness =="
  "${SCRIPT_DIR}/feature-readiness.sh" --full
fi

echo
echo "== app bundle build =="
if [[ "$MODE" == "--quick" ]]; then
  BUILD_ARCHS="--arch $(uname -m)" "${SCRIPT_DIR}/build-dmg.sh" --app-only
else
  "${SCRIPT_DIR}/build-dmg.sh" --app-only
fi

echo
echo "== app bundle identity =="
if [[ "$MODE" == "--quick" ]]; then
  "${SCRIPT_DIR}/verify-app-bundle.sh" --native
else
  "${SCRIPT_DIR}/verify-app-bundle.sh" --universal
fi
if [[ "$MODE" == "--full" ]]; then
  echo
  echo "== qualification receipt =="
  python3 - <<'PY'
import hashlib
import json
import os
import subprocess
from datetime import datetime, timezone
from pathlib import Path

root = Path.cwd()
if subprocess.check_output(
    ["git", "status", "--porcelain"], cwd=root, text=True
).strip():
    raise SystemExit("ERROR: Git working tree became dirty during qualification")

def run(*args):
    return subprocess.check_output(args, cwd=root, text=True).strip()

def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

main_exe = root / ".build/dmg/CatCleaner.app/Contents/MacOS/MacClean"
menu_exe = (
    root
    / ".build/dmg/CatCleaner.app/Contents/Library/LoginItems/MacCleanMenu.app/Contents/MacOS/MacCleanMenu"
)

receipt = {
    "schema": "catcleaner.xcode-qualification/v1",
    "mode": "full",
    "qualified_at_utc": datetime.now(timezone.utc).isoformat(),
    "head": run("git", "rev-parse", "HEAD"),
    "tree": run("git", "rev-parse", "HEAD^{tree}"),
    "developer_dir": str(Path(os.environ["DEVELOPER_DIR"]).resolve()),
    "xcode_version": subprocess.check_output(
        ["xcodebuild", "-version"],
        cwd=root,
        env=os.environ.copy(),
        text=True,
    ).strip().splitlines(),
    "app_version": (root / "VERSION").read_text(encoding="utf-8").strip(),
    "main_sha256": sha256(main_exe),
    "menu_sha256": sha256(menu_exe),
}

receipt_dir = root / ".build/qualification"
receipt_dir.mkdir(parents=True, exist_ok=True)
receipt_path = receipt_dir / "xcode-qualification-v1.json"
tmp_path = receipt_path.with_suffix(".tmp")
tmp_path.write_text(
    json.dumps(receipt, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
tmp_path.replace(receipt_path)
print(f"receipt={receipt_path}")
PY
fi

echo
echo "CATCLEANER_XCODE_QUALIFICATION_PASS mode=$MODE"
