import Foundation
import AppKit
import MacCleanKit

public struct UninstallerModule: ScanModule {
    public let id = "uninstaller"
    public var name: String { L10n.tr("卸载器", "Uninstaller", "Удаление приложений") }
    public let category = ModuleCategory.applications
    public let includedInSmartScan = false

    public init() {}

    public func scan() async -> [ScanResult] {
        // The uninstaller doesn't produce traditional scan results.
        // It provides an app list with associated files.
        []
    }
}

// MARK: - App Path Finder (system-side wrapper around MacCleanKit.AppMatching)

public struct AppPathFinder: Sendable {
    public typealias MatchLevel = AppMatching.MatchLevel

    public let maxLevel: MatchLevel

    // Default stops at .versionStripped: the .companyName level matches the bare
    // vendor token and would flag sibling apps from the same vendor (issue #98).
    public init(maxLevel: MatchLevel = .versionStripped) {
        self.maxLevel = maxLevel
    }

    public func findAssociatedFiles(for app: AppInfo) -> [FileItem] {
        let patterns = AppMatching.generatePatterns(for: app, maxLevel: maxLevel)
        var found: [FileItem] = []
        let fm = FileManager.default

        for subdir in AppMatching.librarySubdirectories {
            let dirURL = MCConstants.userLibrary.appending(path: subdir)
            guard let contents = try? fm.contentsOfDirectory(
                at: dirURL,
                includingPropertiesForKeys: [.fileSizeKey, .totalFileAllocatedSizeKey, .isDirectoryKey]
            ) else { continue }

            for itemURL in contents {
                if AppMatching.filenameMatches(itemURL.lastPathComponent, patterns: patterns) {
                    if let fileItem = makeFileItem(from: itemURL) {
                        found.append(fileItem)
                    }
                }
            }
        }

        // Also check system Library for launch daemons
        let systemDirs = [MCConstants.systemLaunchDaemons, MCConstants.systemLaunchAgents]
        for dirURL in systemDirs {
            guard let contents = try? fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil)
            else { continue }

            for itemURL in contents where itemURL.pathExtension == "plist" {
                if AppMatching.filenameMatches(itemURL.lastPathComponent, patterns: patterns) {
                    if let fileItem = makeFileItem(from: itemURL) {
                        found.append(fileItem)
                    }
                }
            }
        }

        return found
    }

    private func makeFileItem(from url: URL) -> FileItem? {
        let values = try? url.resourceValues(forKeys: [
            .fileSizeKey, .totalFileAllocatedSizeKey, .isDirectoryKey,
            .contentModificationDateKey, .nameKey,
        ])
        let isDir = values?.isDirectory ?? false
        var size = UInt64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)

        if isDir {
            size = directorySize(url)
        }

        return FileItem(
            url: url,
            name: values?.name ?? url.lastPathComponent,
            size: size,
            allocatedSize: size,
            isDirectory: isDir,
            modificationDate: values?.contentModificationDate
        )
    }

    private func directorySize(_ url: URL) -> UInt64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
            options: []
        ) else { return 0 }
        var total: UInt64 = 0
        while let fileURL = enumerator.nextObject() as? URL {
            let v = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
            total += UInt64(v?.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
