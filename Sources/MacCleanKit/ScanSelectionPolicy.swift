import Foundation

/// Single source of truth for default cleanup selection.
///
/// Scan modules decide whether a category is review-only through
/// `ScanResult.autoSelect` (normally inherited from `ScanCategory.autoSelect`).
/// Views must not reconstruct their own "select everything" policy, because
/// that can silently bypass safety changes made at the category layer.
public enum ScanSelectionPolicy {
    /// Returns only URLs belonging to scan results explicitly allowed to be
    /// preselected. Duplicate URLs are naturally collapsed.
    public static func defaultSelection(from results: [ScanResult]) -> Set<URL> {
        var selected: Set<URL> = []
        for result in results where result.autoSelect {
            selected.formUnion(result.items.map(\.url))
        }
        return selected
    }

    /// Convenience overload for Smart Scan's per-module result model.
    public static func defaultSelection(from modules: [ModuleScanResult]) -> Set<URL> {
        defaultSelection(from: modules.flatMap(\.categories))
    }
}
