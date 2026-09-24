#!/bin/bash
# CatCleaner local feature-readiness gate.
#
# This intentionally separates product functionality from public-release
# infrastructure. A machine can be FEATURE_COMPLETE_LOCAL while public release
# remains HOLD because Xcode/signing/origin/notarization are not configured.
#
# Read-only: no cleanup execution, no Git mutation, no xcode-select changes.
#
# Usage:
#   ./scripts/feature-readiness.sh          # bounded quick gate
#   ./scripts/feature-readiness.sh --full   # includes real Large Files scan

set -euo pipefail

MODE="${1:---quick}"
case "$MODE" in
  --quick|--full) ;;
  *)
    echo "Usage: $0 [--quick|--full]" >&2
    exit 64
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

failures=0

pass()  { printf 'PASS      %-30s %s\n' "$1" "$2"; }
block() { printf 'BLOCK     %-30s %s\n' "$1" "$2"; failures=$((failures + 1)); }
info()  { printf 'INFO      %-30s %s\n' "$1" "$2"; }

echo "CatCleaner local feature readiness"
echo "repo=$ROOT"
echo "mode=$MODE"
echo

if [[ ! -f docs/BUHOCLEANER_PARITY.md ]]; then
  block "parity_matrix" "docs/BUHOCLEANER_PARITY.md is missing"
else
  parity_result="$(
    python3 - <<'PY'
from pathlib import Path

text = Path("docs/BUHOCLEANER_PARITY.md").read_text()
infra = {
    "CatCleaner 自有主圖示/視覺品牌",
    "正式 Developer ID 簽章",
    "Notarization",
    "自動更新",
    "Homebrew cask",
}

rows = []
in_matrix = False
for line in text.splitlines():
    stripped = line.strip()

    if stripped == "## 功能矩陣":
        in_matrix = True
        continue

    if in_matrix and stripped.startswith("## "):
        break

    if not in_matrix or not line.startswith("|"):
        continue

    cells = [c.strip() for c in line.strip().strip("|").split("|")]
    if len(cells) < 3:
        continue

    feature, status = cells[0], cells[1]
    if feature == "BuhoCleaner 類功能":
        continue
    if feature.startswith("---") or status.startswith("---"):
        continue

    rows.append((feature, status))

feature_rows = [(f, s) for f, s in rows if f not in infra]
bad = [(f, s) for f, s in feature_rows if s not in {"✅", "🛡️"}]

if not rows:
    print("ERROR|no feature-matrix rows parsed")
elif bad:
    print("ERROR|" + "; ".join(f"{f}={s}" for f, s in bad))
else:
    print(
        f"OK|rows={len(rows)} feature_rows={len(feature_rows)} "
        f"infra_rows={len(rows)-len(feature_rows)}"
    )
PY
  )"

  parity_kind="${parity_result%%|*}"
  parity_message="${parity_result#*|}"
  if [[ "$parity_kind" == "OK" ]]; then
    pass "buho_feature_parity" "$parity_message"
  else
    block "buho_feature_parity" "$parity_message"
  fi
fi

extension_result="$(
  python3 - <<'PYEXT'
from pathlib import Path

required_files = [
    "Sources/MacCleanKit/BatteryCare.swift",
    "Sources/MacCleanKit/BatteryTelemetry.swift",
    "Sources/MacClean/Modules/BatteryCare/BatteryCareMonitor.swift",
    "Sources/MacClean/Views/Battery/BatteryCareView.swift",
    "Sources/MacClean/App/BatteryCareIntents.swift",
    "Sources/MacCleanKit/CleaningAutomation.swift",
    "Sources/MacClean/Services/CleaningAutomationService.swift",
    "Tests/MacCleanKitTests/BatteryCareTests.swift",
    "Tests/MacCleanTests/BatterySMCCapabilityTests.swift",
    "Tests/MacCleanKitTests/CleaningAutomationTests.swift",
]
missing = [path for path in required_files if not Path(path).is_file()]
if missing:
    print("ERROR|missing=" + ",".join(missing))
    raise SystemExit

checks = {
    "battery_policy": (
        "Sources/MacCleanKit/BatteryCare.swift",
        ["chargeLimitRange", "shouldPauseCharging", "shouldAutomaticallyDischarge"],
    ),
    "m5_capability": (
        "Sources/MacClean/Modules/BatteryCare/BatteryCareMonitor.swift",
        ["CHTE", "CHIE", "ACLC", "CompetingBatteryControllerProbe"],
    ),
    "shortcuts": (
        "Sources/MacClean/App/BatteryCareIntents.swift",
        ["AppShortcutsProvider", "CatCleanerBatteryStatusIntent", "CatCleanerSetChargeLimitIntent"],
    ),
    "browser_automation": (
        "Sources/MacClean/Services/CleaningAutomationService.swift",
        ["didTerminateApplicationNotification", "mode: .trash", "emptyAgedTrashIfEnabled"],
    ),
    "automation_policy": (
        "Sources/MacCleanKit/CleaningAutomation.swift",
        ["moveSafeCachesToTrash", "safeCacheRoots", "shouldEmptyTrashItem"],
    ),
}

bad = []
for name, (path, needles) in checks.items():
    text = Path(path).read_text()
    missing_needles = [needle for needle in needles if needle not in text]
    if missing_needles:
        bad.append(f"{name}:{','.join(missing_needles)}")

if bad:
    print("ERROR|" + "; ".join(bad))
else:
    print(
        "OK|battery-care/read-only-hardware-gate + shortcuts + "
        "menu customization + cleaning-automation contracts present"
    )
PYEXT
)"

extension_kind="${extension_result%%|*}"
extension_message="${extension_result#*|}"
if [[ "$extension_kind" == "OK" ]]; then
  pass "product_extensions" "$extension_message"
else
  block "product_extensions" "$extension_message"
fi

if "$SCRIPT_DIR/core-smoke.sh" "$MODE"; then
  pass "core_smoke" "$MODE"
else
  block "core_smoke" "$MODE failed"
fi

# Release readiness is informative here, never a feature blocker.
set +e
"$SCRIPT_DIR/release-readiness.sh" --quiet >/dev/null 2>&1
release_rc=$?
set -e
case "$release_rc" in
  0) info "public_release" "READY" ;;
  2) info "public_release" "HOLD (separate infrastructure gate)" ;;
  *) info "public_release" "UNKNOWN rc=$release_rc" ;;
esac

echo
echo "feature_blockers=$failures"
if (( failures > 0 )); then
  echo "verdict=FEATURE_HOLD"
  exit 2
fi

echo "verdict=FEATURE_COMPLETE_LOCAL"
exit 0
