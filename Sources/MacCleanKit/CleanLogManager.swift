import Foundation

/// Filesystem-backed façade over `~/Library/Logs/CatCleaner/operations.log`.
/// Used by the UI's log-viewer and by app startup for 30-day retention.
///
/// Pure logic (parsing, pruning) lives in `LogPruner`. This type wraps
/// it with file I/O.
public enum CleanLogManager {

    /// How long a log entry survives before retention drops it.
    public static let retention: TimeInterval = 30 * 24 * 3600 // 30 days

    /// Read the full log file. Returns empty string when missing —
    /// the file isn't created until the first clean operation logs to it.
    public static func readLogFile() -> String {
        let path = MCConstants.operationLogFile.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: MCConstants.operationLogFile),
              let text = String(data: data, encoding: .utf8)
        else { return "" }
        return text
    }

    /// Drop entries older than `retention` (default 30 days). Atomic
    /// via temp-write + rename. No-op (and no write) when nothing
    /// would change — keeps disk untouched on quiet launches.
    ///
    /// Safe to call repeatedly; safe to call on app startup.
    public static func pruneOldEntries(now: Date = Date()) {
        let url = MCConstants.operationLogFile
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else { return }

        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return }

        let cutoff = now.addingTimeInterval(-retention)
        let pruned = LogPruner.pruning(text, olderThan: cutoff)
        if pruned == text { return }

        // Atomic write via temp + replace so we never leave the log in
        // a partial state if the process gets killed mid-write.
        let tempURL = url.deletingLastPathComponent()
            .appending(path: ".operations.log.pruning-\(UUID().uuidString)")
        do {
            try pruned.write(to: tempURL, atomically: false, encoding: .utf8)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
        } catch {
            // Best-effort: failed pruning shouldn't crash the app. The
            // unpruned log on disk is still useful; we'll try again on
            // the next launch.
            try? FileManager.default.removeItem(at: tempURL)
        }
    }
}
