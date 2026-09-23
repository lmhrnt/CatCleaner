#!/bin/bash
# CatCleaner core smoke gate for machines that have Apple Command Line Tools
# but not full Xcode.
#
# Usage:
#   ./scripts/core-smoke.sh          # quick, bounded gate
#   ./scripts/core-smoke.sh --full   # also run the real Large Files scanner
#
# Safety:
# - never calls a cleanup executor on real user data
# - real-home probes are read-only scanners
# - mutation tests operate only inside a mktemp directory
# - does not change xcode-select or install/download toolchains

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

TMP="$(mktemp -d "${TMPDIR:-/tmp}/catcleaner-core-smoke.XXXXXX")"
cleanup_tmp() {
  case "$TMP" in
    "${TMPDIR:-/tmp}"/catcleaner-core-smoke.*)
      find "$TMP" -depth -delete 2>/dev/null || true
      ;;
    *)
      echo "WARN: refusing unexpected temp cleanup path: $TMP" >&2
      ;;
  esac
}
trap cleanup_tmp EXIT

say() {
  printf '\n== %s ==\n' "$1"
}

say "preflight"
"$SCRIPT_DIR/build-preflight.sh" --core-only
python3 "$SCRIPT_DIR/check-process-pipe-order.py"
"$SCRIPT_DIR/check-version-sync.sh"

say "MacCleanKit build"
swift build --target MacCleanKit

PRODUCT_DIR=".build/out/Products/Debug"
if [[ ! -f "$PRODUCT_DIR/MacCleanKit.swiftmodule" || ! -f "$PRODUCT_DIR/MacCleanKit.o" ]]; then
  MODULE_PATH="$(find .build -name MacCleanKit.swiftmodule -print -quit)"
  OBJECT_PATH="$(find .build -name MacCleanKit.o -print -quit)"
  if [[ -z "$MODULE_PATH" || -z "$OBJECT_PATH" ]]; then
    echo "ERROR: MacCleanKit build products not found after successful build." >&2
    exit 70
  fi
  PRODUCT_DIR="$(dirname "$MODULE_PATH")"
  MACCLEANKIT_OBJECT="$OBJECT_PATH"
else
  MACCLEANKIT_OBJECT="$PRODUCT_DIR/MacCleanKit.o"
fi

say "Swift syntax parser"
parsed=0
while IFS= read -r -d '' file; do
  /Library/Developer/CommandLineTools/usr/bin/swiftc -frontend -parse "$file"
  parsed=$((parsed + 1))
done < <(
  find Sources/MacClean Sources/MacCleanMenu     -type f -name '*.swift' -print0
)
echo "parsed_swift_files=$parsed"

say "semantic pipeline typechecks"
xcrun swiftc -typecheck   -I "$PRODUCT_DIR"   Sources/MacClean/Core/Scanner/TargetedScanner.swift   Sources/MacClean/Modules/Duplicates/SimilarPhotosModule.swift

xcrun swiftc -typecheck   -I "$PRODUCT_DIR"   Sources/MacClean/Core/Cleaner/CleaningEngine.swift   Sources/MacClean/Modules/DeveloperCleanup/DeveloperCleanupExecutor.swift

xcrun swiftc -typecheck   -I "$PRODUCT_DIR"   Sources/MacClean/Modules/Uninstaller/AppDiscovery.swift   Sources/MacClean/Modules/SystemJunk/AppLeftoversScanner.swift

xcrun swiftc -typecheck   -I "$PRODUCT_DIR"   Sources/MacClean/Core/Scanner/ScanCoordinator.swift   Sources/MacClean/Core/Scanner/TargetedScanner.swift   Sources/MacClean/Modules/LargeOldFiles/LargeFileSpecialDiscovery.swift   Sources/MacClean/Modules/LargeOldFiles/LargeOldFilesModule.swift

xcrun swiftc -typecheck   -I "$PRODUCT_DIR"   Sources/MacClean/Core/Scanner/ScanCoordinator.swift   Sources/MacClean/Core/Scanner/TargetedScanner.swift   Sources/MacClean/Modules/Duplicates/DuplicatesModule.swift

echo "semantic_typechecks=PASS"

say "Smart Scan catalog contract"

for source in   Sources/MacClean/Modules/Uninstaller/UninstallerModule.swift   Sources/MacClean/Modules/Updater/UpdaterModule.swift   Sources/MacClean/Modules/Optimization/OptimizationModule.swift   Sources/MacClean/Modules/Maintenance/MaintenanceModule.swift
do
  if ! rg -q 'includedInSmartScan = false' "$source"; then
    echo "FAIL: action-only module is not explicitly excluded from Smart Scan: $source" >&2
    exit 71
  fi
done

cat >"$TMP/smartscan-catalog-smoke.swift" <<'SWIFT'
import Foundation
import MacCleanKit

struct DummyModule: ScanModule {
    let id: String
    let name: String
    let category: ModuleCategory
    let includedInSmartScan: Bool

    func scan() async -> [ScanResult] { [] }
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct Main {
    static func main() {
        let coordinator = ScanCoordinator()
        coordinator.registerModules([
            DummyModule(id: "cleanup-a", name: "Cleanup A", category: .cleanup, includedInSmartScan: true),
            DummyModule(id: "action-only", name: "Action Only", category: .performance, includedInSmartScan: false),
            DummyModule(id: "privacy-b", name: "Privacy B", category: .protection, includedInSmartScan: true),
        ])

        let descriptors = coordinator.smartScanModuleDescriptors
        require(descriptors.map(\.id) == ["cleanup-a", "privacy-b"], "excluded module leaked into Smart Scan catalog")
        require(descriptors.map(\.name) == ["Cleanup A", "Privacy B"], "registration order/name drift")
        require(descriptors.allSatisfy(\.includedInSmartScan), "descriptor included flag must be true")
        require(descriptors.map(\.category) == [.cleanup, .protection], "category drift")
        print("SMART_SCAN_CATALOG_SMOKE_PASS ids=\(descriptors.map(\.id).joined(separator: ","))")
    }
}
SWIFT

xcrun swiftc -parse-as-library   -I "$PRODUCT_DIR"   Sources/MacClean/Core/Scanner/ScanCoordinator.swift   "$TMP/smartscan-catalog-smoke.swift"   "$MACCLEANKIT_OBJECT"   -o "$TMP/smartscan-catalog-smoke"
"$TMP/smartscan-catalog-smoke"

say "synthetic duplicate pipeline"
cat >"$TMP/duplicate-smoke.swift" <<'SWIFT'
import Foundation
import MacCleanKit

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct Main {
    static func main() async {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let a = root.appendingPathComponent("a.bin")
        let b = root.appendingPathComponent("b.bin")
        let c = root.appendingPathComponent("c.bin")

        let same = Data(repeating: 0x5A, count: 128 * 1024)
        let other = Data(repeating: 0xA5, count: 128 * 1024)
        try! same.write(to: a)
        try! same.write(to: b)
        try! other.write(to: c)

        let files = [a, b, c].map {
            FileItem(
                url: $0,
                name: $0.lastPathComponent,
                size: 128 * 1024,
                allocatedSize: 128 * 1024,
                isDirectory: false
            )
        }

        let groups = await DuplicatesModule().findDuplicates(files)
        require(groups.count == 1, "expected exactly one duplicate group")
        require(groups[0].count == 2, "expected exactly two identical files")
        let names = Set(groups[0].map(\.name))
        require(names == Set(["a.bin", "b.bin"]), "wrong duplicate members: \(names)")
        print("DUPLICATE_SYNTHETIC_SMOKE_PASS groups=\(groups.count)")
    }
}
SWIFT

xcrun swiftc -parse-as-library   -I "$PRODUCT_DIR"   Sources/MacClean/Core/Scanner/ScanCoordinator.swift   Sources/MacClean/Core/Scanner/TargetedScanner.swift   Sources/MacClean/Modules/Duplicates/DuplicatesModule.swift   "$TMP/duplicate-smoke.swift"   "$MACCLEANKIT_OBJECT"   -o "$TMP/duplicate-smoke"
"$TMP/duplicate-smoke" "$TMP"

say "synthetic similar-photo grouping"
cat >"$TMP/similar-smoke.swift" <<'SWIFT'
import Foundation
import MacCleanKit

func asset(_ name: String) -> SimilarPhotoAsset {
    SimilarPhotoAsset(
        url: URL(fileURLWithPath: "/tmp/\(name)"),
        fileSize: 1_000_000,
        pixelWidth: 4000,
        pixelHeight: 3000
    )
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct Main {
    static func main() {
        let a = asset("a.jpg")
        let b = asset("b.jpg")
        let c = asset("c.jpg")

        let groups = SimilarPhotoGrouping.clusters(
            assets: [a, b, c],
            pairs: [
                SimilarPhotoPair(first: a.url, second: b.url, distance: 0.10),
                SimilarPhotoPair(first: b.url, second: c.url, distance: 0.11),
                SimilarPhotoPair(first: a.url, second: c.url, distance: 0.80),
            ],
            maximumDistance: 0.30
        )

        require(groups.count == 1, "expected one conservative review group")
        require(groups[0].count == 2, "transitive bridge must not produce a 3-photo group")

        let assets = (0..<20).map { asset(String(format: "p%02d.jpg", $0)) }
        let plan = SimilarPhotoGrouping.comparisonPlan(
            assets: assets,
            maxPartnersPerAsset: 3,
            maxTotalPairs: 17
        )
        require(plan.count <= 17, "global comparison cap exceeded")

        print("SIMILAR_PHOTO_SYNTHETIC_SMOKE_PASS groups=\(groups.count) pairs=\(plan.count)")
    }
}
SWIFT

xcrun swiftc -parse-as-library   -I "$PRODUCT_DIR"   "$TMP/similar-smoke.swift"   "$MACCLEANKIT_OBJECT"   -o "$TMP/similar-smoke"
"$TMP/similar-smoke"

say "read-only Developer Cleanup scan"
cat >"$TMP/developer-scan.swift" <<'SWIFT'
import Foundation
import MacCleanKit

@main
struct Main {
    static func main() async {
        let start = ContinuousClock.now
        let items = await DeveloperCleanupScanner().scan(maxConcurrentSizeProbes: 4)
        let elapsed = start.duration(to: .now)
        let total = items.reduce(UInt64(0)) { $0 + $1.allocatedSize }
        let active = items.filter(\.ownerActive).count
        let executable = items.filter {
            DeveloperCleanupExecutionPolicy.method(for: $0) != nil
        }.count

        print("DEVELOPER_SCAN_READONLY_PASS count=\(items.count) total_bytes=\(total) active=\(active) executable_now=\(executable) elapsed=\(elapsed)")
    }
}
SWIFT

xcrun swiftc -parse-as-library   -I "$PRODUCT_DIR"   "$TMP/developer-scan.swift"   "$MACCLEANKIT_OBJECT"   -o "$TMP/developer-scan"
"$TMP/developer-scan"

say "read-only removed-app leftovers scan"
cat >"$TMP/leftovers-scan.swift" <<'SWIFT'
import Foundation
import MacCleanKit

@main
struct Main {
    static func main() {
        let start = ContinuousClock.now
        let items = AppLeftoversScanner.scan()
        let elapsed = start.duration(to: .now)
        let total = items.reduce(UInt64(0)) { $0 + $1.size }
        print("LEFTOVERS_SCAN_READONLY_PASS count=\(items.count) total_bytes=\(total) elapsed=\(elapsed)")
    }
}
SWIFT

xcrun swiftc -parse-as-library   -I "$PRODUCT_DIR"   Sources/MacClean/Modules/Uninstaller/AppDiscovery.swift   Sources/MacClean/Modules/SystemJunk/AppLeftoversScanner.swift   "$TMP/leftovers-scan.swift"   "$MACCLEANKIT_OBJECT"   -o "$TMP/leftovers-scan"
"$TMP/leftovers-scan"

if [[ "$MODE" == "--full" ]]; then
  say "read-only Large Files scan"
  cat >"$TMP/large-files-scan.swift" <<'SWIFT'
import Foundation
import MacCleanKit

@main
struct Main {
    static func main() async {
        let start = ContinuousClock.now
        let results = await LargeOldFilesModule().scan()
        let elapsed = start.duration(to: .now)
        let items = results.flatMap(\.items)
        let total = items.reduce(UInt64(0)) { $0 + $1.size }
        print("LARGE_FILES_SCAN_READONLY_PASS results=\(results.count) items=\(items.count) total_bytes=\(total) elapsed=\(elapsed)")
        for item in items.prefix(10) {
            print("\(item.size)|\(item.url.path)")
        }
    }
}
SWIFT

  xcrun swiftc -parse-as-library     -I "$PRODUCT_DIR"     Sources/MacClean/Core/Scanner/ScanCoordinator.swift     Sources/MacClean/Core/Scanner/TargetedScanner.swift     Sources/MacClean/Modules/LargeOldFiles/LargeFileSpecialDiscovery.swift     Sources/MacClean/Modules/LargeOldFiles/LargeOldFilesModule.swift     "$TMP/large-files-scan.swift"     "$MACCLEANKIT_OBJECT"     -o "$TMP/large-files-scan"
  "$TMP/large-files-scan"
fi

say "result"
echo "CATCLEANER_CORE_SMOKE_PASS mode=$MODE"
