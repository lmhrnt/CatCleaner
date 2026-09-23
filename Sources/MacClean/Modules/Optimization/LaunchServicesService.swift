import Foundation
import AppKit
import MacCleanKit

public enum LaunchServicesError: LocalizedError, Sendable {
    case backupFailed(Error)
    case invalidBackup(String)
    case restoreFailed(Error)
    case deleteFailed(String)

    public var errorDescription: String? {
        switch self {
        case .backupFailed(let error):
            return L10n.tr(
                "备份失败：\(error.localizedDescription)",
                "Backup failed: \(error.localizedDescription)",
                "Не удалось создать резервную копию: \(error.localizedDescription)"
            )
        case .invalidBackup(let reason):
            return L10n.tr(
                "备份文件无效：\(reason)",
                "Invalid backup file: \(reason)",
                "Недопустимый файл резервной копии: \(reason)"
            )
        case .restoreFailed(let error):
            return L10n.tr(
                "恢复失败：\(error.localizedDescription)",
                "Restore failed: \(error.localizedDescription)",
                "Не удалось восстановить копию: \(error.localizedDescription)"
            )
        case .deleteFailed(let message):
            return L10n.tr(
                "删除失败：\(message)",
                "Delete failed: \(message)",
                "Не удалось удалить: \(message)"
            )
        }
    }
}

public final class LaunchServicesService: @unchecked Sendable {
    public static let shared = LaunchServicesService()

    private let plistPath: String
    private let backupDir: URL

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        plistPath = "\(home)/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist"
        backupDir = URL(fileURLWithPath: home)
            .appending(path: "Library/Application Support/CatCleaner/LaunchServicesBackups")
        try? FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
    }

    /// Testing override: inject a custom plist path so tests don't touch the real file.
    internal init(plistPath: String) {
        self.plistPath = plistPath
        backupDir = URL(fileURLWithPath: plistPath).deletingLastPathComponent()
            .appending(path: ".launchservices-backups")
        try? FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
    }

    // MARK: - Read

    public func loadHandlers() -> [HandlerEntry] {
        guard FileManager.default.fileExists(atPath: plistPath),
              let plistData = NSDictionary(contentsOfFile: plistPath),
              let handlers = plistData["LSHandlers"] as? [[String: Any]] else {
            return []
        }
        return handlers.compactMap { dict -> HandlerEntry? in
            var entry = HandlerEntry(id: UUID())
            entry.contentType = dict["LSHandlerContentType"] as? String
            entry.contentTag = dict["LSHandlerContentTag"] as? String
            entry.contentTagClass = dict["LSHandlerContentTagClass"] as? String
            entry.roleAll = dict["LSHandlerRoleAll"] as? String
            entry.urlScheme = dict["LSHandlerURLScheme"] as? String
            if let ts = dict["LSHandlerModificationDate"] as? Double {
                entry.modificationDate = Date(timeIntervalSince1970: ts)
            }
            if entry.roleAll == nil && entry.urlScheme == nil { return nil }
            return entry
        }
    }

    // MARK: - Safe Delete (in-place with backup)

    /// Delete a single entry from LSHandlers.  Before mutating it backs up the
    /// current plist so every change is reversible.
    public func deleteHandler(_ entry: HandlerEntry) throws {
        // 1. Backup first — always.
        try backup()

        // 2. Read as mutable dictionary so unknown keys are preserved.
        guard let plistData = NSMutableDictionary(contentsOfFile: plistPath) else {
            throw LaunchServicesError.deleteFailed(
                L10n.tr("无法读取 plist", "Cannot read plist", "Не удалось прочитать plist")
            )
        }

        if let handlers = plistData["LSHandlers"] as? NSMutableArray {
            let indices = (0 ..< handlers.count)
                .filter { i in
                    guard let dict = handlers[i] as? [String: Any] else { return false }
                    return entryMatches(entry, dict)
                }
                .reversed()
            for idx in indices {
                handlers.removeObject(at: idx)
            }
        }

        guard plistData.write(toFile: plistPath, atomically: true) else {
            throw LaunchServicesError.deleteFailed(
                L10n.tr("无法写入 plist", "Cannot write plist", "Не удалось записать plist")
            )
        }
    }

    // MARK: - Backup / Restore

    private static let maxBackups = 20

    /// Snapshot the current plist to the backup directory, then trim to
    /// `maxBackups` so the folder doesn't grow unbounded.
    public func backup() throws {
        let src = URL(fileURLWithPath: plistPath)
        guard FileManager.default.fileExists(atPath: plistPath) else { return }
        let fm = ISO8601DateFormatter()
        fm.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let ts = fm.string(from: Date())
            // Replace colons with underscores so the name is filesystem-safe
            // and trivially reversible for display.
            .replacingOccurrences(of: ":", with: "_")
        var dst = backupDir.appending(path: "launchservices-\(ts).plist")
        // If two backups happen in the same fractional second, append a uniquifier.
        if FileManager.default.fileExists(atPath: dst.path) {
            dst = backupDir.appending(path: "launchservices-\(ts)-\(UUID().uuidString.prefix(8)).plist")
        }
        do {
            try FileManager.default.copyItem(at: src, to: dst)
        } catch {
            throw LaunchServicesError.backupFailed(error)
        }
        // Prune old backups beyond the cap.
        trimBackups()
    }

    /// Remove backups beyond `maxBackups`, keeping the newest ones.
    private func trimBackups() {
        let all = listBackups()
        guard all.count > Self.maxBackups else { return }
        for stale in all[Self.maxBackups...] {
            try? FileManager.default.removeItem(at: stale)
        }
    }

    /// List available backups newest-first (sorted by filename timestamp).
    public func listBackups() -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: backupDir,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        ) else {
            return []
        }

        return contents
            .filter { isValidBackupPath($0, requireValidPlist: true) }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Restore a CatCleaner-created backup to the live plist path using an
    /// atomic swap. The actuator independently validates the backup source;
    /// it does not trust the UI to pass a URL returned by the backup list.
    /// The current live plist is backed up once more before replacement so a
    /// restore itself remains reversible.
    public func restoreBackup(from url: URL) throws {
        guard isValidBackupPath(url, requireValidPlist: true) else {
            throw LaunchServicesError.invalidBackup(
                "source must be a regular, non-symlink CatCleaner LaunchServices backup"
            )
        }

        // Snapshot the source bytes before backup(): at the retention cap,
        // adding the current state may prune the selected historical file.
        let sourceData: Data
        do {
            sourceData = try Data(contentsOf: url)
        } catch {
            throw LaunchServicesError.restoreFailed(error)
        }

        // Keep the pre-restore live state reversible.
        try backup()

        let dst = URL(fileURLWithPath: plistPath)
        let tmpDir = dst.deletingLastPathComponent()
        let tmpURL = tmpDir.appending(path: ".launchservices-restore-tmp.plist")
        try? FileManager.default.removeItem(at: tmpURL)

        do {
            try sourceData.write(to: tmpURL, options: [.atomic])

            guard isValidLaunchServicesPlist(at: tmpURL) else {
                throw LaunchServicesError.invalidBackup(
                    "staged backup no longer parses as a LaunchServices plist"
                )
            }

            _ = try FileManager.default.replaceItemAt(dst, withItemAt: tmpURL)
        } catch let error as LaunchServicesError {
            try? FileManager.default.removeItem(at: tmpURL)
            throw error
        } catch {
            try? FileManager.default.removeItem(at: tmpURL)
            throw LaunchServicesError.restoreFailed(error)
        }
    }

    /// True only for CatCleaner-created backup files inside this service's
    /// backup directory. Rejects symlinks and traversal or alias escapes.
    private func isValidBackupPath(
        _ url: URL,
        requireValidPlist: Bool
    ) -> Bool {
        let candidate = url.standardizedFileURL
        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
        let root = backupDir.standardizedFileURL
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL

        func canonicalizeMacOSFirmlink(_ path: String) -> String {
            for name in ["var", "tmp", "etc"] {
                let privatePrefix = "/private/\(name)"
                if path == privatePrefix {
                    return "/\(name)"
                }
                if path.hasPrefix(privatePrefix + "/") {
                    return "/\(name)" + path.dropFirst(privatePrefix.count)
                }
            }
            return path
        }

        guard canonicalizeMacOSFirmlink(candidate.path(percentEncoded: false))
                == canonicalizeMacOSFirmlink(resolved.path(percentEncoded: false))
        else {
            return false
        }

        func isStrictDescendant(_ child: URL, of root: URL) -> Bool {
            let childPath = canonicalizeMacOSFirmlink(
                child.path(percentEncoded: false)
            )
            let rootPath = canonicalizeMacOSFirmlink(
                root.path(percentEncoded: false)
            ).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let normalizedRoot = rootPath.isEmpty ? "/" : "/" + rootPath
            guard childPath != normalizedRoot else { return false }
            let prefix = normalizedRoot == "/" ? "/" : normalizedRoot + "/"
            return childPath.hasPrefix(prefix)
        }

        guard isStrictDescendant(candidate, of: root),
              isStrictDescendant(resolved, of: resolvedRoot),
              candidate.pathExtension.lowercased() == "plist",
              candidate.lastPathComponent.hasPrefix("launchservices-")
        else {
            return false
        }

        guard let values = try? candidate.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        ),
        values.isRegularFile == true,
        values.isSymbolicLink != true
        else {
            return false
        }

        return !requireValidPlist || isValidLaunchServicesPlist(at: candidate)
    }

    private func isValidLaunchServicesPlist(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              ) as? [String: Any],
              plist["LSHandlers"] is [[String: Any]]
        else {
            return false
        }
        return true
    }

    // MARK: - Helpers

    /// Check whether a plist dictionary matches a HandlerEntry.
    private func entryMatches(_ entry: HandlerEntry, _ dict: [String: Any]) -> Bool {
        // Match on URL scheme when present.
        if let scheme = entry.urlScheme {
            return dict["LSHandlerURLScheme"] as? String == scheme
        }
        // Match on content-type + roleAll when present.
        if let ct = entry.contentType {
            return dict["LSHandlerContentType"] as? String == ct
                && dict["LSHandlerRoleAll"] as? String == entry.roleAll
        }
        // Fallback: match on content-tag + tag-class + roleAll.
        if let tag = entry.contentTag {
            return dict["LSHandlerContentTag"] as? String == tag
                && dict["LSHandlerContentTagClass"] as? String == entry.contentTagClass
                && dict["LSHandlerRoleAll"] as? String == entry.roleAll
        }
        return false
    }

    // MARK: - App Info

    public func getAppInfo(for bundleId: String?) -> (name: String, icon: NSImage)? {
        guard let bid = bundleId, !bid.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) else {
            return nil
        }
        let name = FileManager.default.displayName(atPath: url.path)
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 32, height: 32)
        return (name, icon)
    }

    public func getURLSchemeAppInfo(for scheme: String?) -> (name: String, icon: NSImage)? {
        guard let s = scheme, !s.isEmpty,
              let url = URL(string: "\(s)://test"),
              let appURL = NSWorkspace.shared.urlForApplication(toOpen: url) else {
            return nil
        }
        let name = FileManager.default.displayName(atPath: appURL.path)
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: 32, height: 32)
        return (name, icon)
    }
}
