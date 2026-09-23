import Foundation
import MacCleanKit

/// Pure helpers turning Smart Scan's per-module results into the inputs
/// `CleanActions.executeUserClean` expects. SwiftUI-free for testing.
enum SmartScanCleanup {
    /// One module's contribution to the post-clean "Recently cleaned" list (#4).
    struct RecentlyCleanedRow: Equatable, Sendable {
        let moduleID: String
        let moduleName: String
        let itemCount: Int
        let size: UInt64
    }

    struct FindingSummary: Equatable, Sendable {
        let cleanupBytes: UInt64
        let malwareCount: Int
        let privacyCount: Int
        let totalBytes: UInt64
        let totalItemCount: Int

        static let empty = FindingSummary(
            cleanupBytes: 0,
            malwareCount: 0,
            privacyCount: 0,
            totalBytes: 0,
            totalItemCount: 0
        )
    }

    struct ExecutionSummary: Equatable, Sendable {
        let movedToTrashCount: Int
        let permanentlyDeletedCount: Int
        let thinnedInPlaceCount: Int

        static let empty = ExecutionSummary(
            movedToTrashCount: 0,
            permanentlyDeletedCount: 0,
            thinnedInPlaceCount: 0
        )

        var totalCount: Int {
            movedToTrashCount + permanentlyDeletedCount + thinnedInPlaceCount
        }

        var hasIrreversibleDelete: Bool {
            permanentlyDeletedCount > 0
        }

        var hasInPlaceMutation: Bool {
            thinnedInPlaceCount > 0
        }
    }

    private enum ExecutionKind: Int {
        case moveToTrash = 0
        case thinInPlace = 1
        case permanentDelete = 2
    }

    static func allResults(from modules: [ModuleScanResult]) -> [ScanResult] {
        modules.flatMap(\.categories).filter { !$0.items.isEmpty }
    }

    static func findingSummary(from modules: [ModuleScanResult]) -> FindingSummary {
        var totalSizeByURL: [URL: UInt64] = [:]
        var cleanupSizeByURL: [URL: UInt64] = [:]
        var malwareURLs: Set<URL> = []
        var privacyURLs: Set<URL> = []

        func recordSize(_ item: FileItem, in map: inout [URL: UInt64]) {
            map[item.url] = max(map[item.url] ?? 0, item.size)
        }

        for module in modules {
            for result in module.categories {
                for item in result.items {
                    recordSize(item, in: &totalSizeByURL)

                    switch result.category {
                    case .malware:
                        malwareURLs.insert(item.url)
                    case .browserPrivacy, .systemPrivacy:
                        privacyURLs.insert(item.url)
                    default:
                        recordSize(item, in: &cleanupSizeByURL)
                    }
                }
            }
        }

        return FindingSummary(
            cleanupBytes: cleanupSizeByURL.values.reduce(0, +),
            malwareCount: malwareURLs.count,
            privacyCount: privacyURLs.count,
            totalBytes: totalSizeByURL.values.reduce(0, +),
            totalItemCount: totalSizeByURL.count
        )
    }

    /// Delegate default selection to MacCleanKit's single safety policy.
    static func defaultSelection(from modules: [ModuleScanResult]) -> Set<URL> {
        ScanSelectionPolicy.defaultSelection(from: modules)
    }

    /// Classifies the selected URLs by the same category routing used by
    /// CleanActions. If a URL somehow appears in multiple categories, the most
    /// destructive semantics win: permanent delete > in-place thinning > Trash.
    static func executionSummary(
        from modules: [ModuleScanResult],
        selectedItems: Set<URL>
    ) -> ExecutionSummary {
        guard !selectedItems.isEmpty else { return .empty }

        var kindByURL: [URL: ExecutionKind] = [:]
        for module in modules {
            for result in module.categories {
                let kind: ExecutionKind
                switch result.category {
                case .trashBins:
                    kind = .permanentDelete
                case .universalBinaries:
                    kind = .thinInPlace
                default:
                    kind = .moveToTrash
                }

                for item in result.items where selectedItems.contains(item.url) {
                    if let current = kindByURL[item.url], current.rawValue >= kind.rawValue {
                        continue
                    }
                    kindByURL[item.url] = kind
                }
            }
        }

        var moved = 0
        var permanent = 0
        var thinned = 0
        for kind in kindByURL.values {
            switch kind {
            case .moveToTrash: moved += 1
            case .permanentDelete: permanent += 1
            case .thinInPlace: thinned += 1
            }
        }

        return ExecutionSummary(
            movedToTrashCount: moved,
            permanentlyDeletedCount: permanent,
            thinnedInPlaceCount: thinned
        )
    }

    /// Per-module size/count of the user's selection, in module scan order.
    /// URLs that appear in more than one category inside a module are counted once.
    static func recentlyCleanedBreakdown(
        from modules: [ModuleScanResult],
        selectedItems: Set<URL>
    ) -> [RecentlyCleanedRow] {
        guard !selectedItems.isEmpty else { return [] }
        return modules.compactMap { module in
            var seen = Set<URL>()
            var count = 0
            var size: UInt64 = 0
            for result in module.categories {
                for item in result.items where selectedItems.contains(item.url) {
                    guard seen.insert(item.url).inserted else { continue }
                    count += 1
                    size += item.size
                }
            }
            guard count > 0 else { return nil }
            return RecentlyCleanedRow(
                moduleID: module.moduleID,
                moduleName: module.moduleName,
                itemCount: count,
                size: size
            )
        }
    }
}
