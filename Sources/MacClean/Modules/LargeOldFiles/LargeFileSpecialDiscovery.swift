import Foundation
import MacCleanKit

/// Finds large directory-like assets that the generic file scanner deliberately
/// skips as package descendants or excludes with ~/Library.
///
/// Results are review candidates only. LargeOldFilesModule keeps autoSelect=false
/// and cleanup still goes through CleaningEngine/SafetyGuard.
enum LargeFileSpecialDiscovery {
    private static let vmPackageExtensions: Set<String> = [
        "pvm", "vmwarevm", "utm", "vbox"
    ]

    static func scan(minSize: UInt64) async -> [FileItem] {
        await Task.detached(priority: .utility) {
            var items: [FileItem] = []
            items.append(contentsOf: scanIOSBackups(minSize: minSize))
            items.append(contentsOf: scanVirtualMachinePackages(minSize: minSize))

            var unique: [URL: FileItem] = [:]
            for item in items {
                let key = item.url.standardizedFileURL
                if let existing = unique[key] {
                    if item.size > existing.size { unique[key] = item }
                } else {
                    unique[key] = item
                }
            }

            return unique.values.sorted {
                if $0.size == $1.size {
                    return $0.url.path(percentEncoded: false)
                        < $1.url.path(percentEncoded: false)
                }
                return $0.size > $1.size
            }
        }.value
    }

    private static func scanIOSBackups(minSize: UInt64) -> [FileItem] {
        let root = MCConstants.mobileBackups
        let fm = FileManager.default

        guard let entries = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .contentModificationDateKey,
                .creationDateKey,
            ],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var output: [FileItem] = []
        for entry in entries {
            if Task.isCancelled { break }

            guard let values = try? entry.resourceValues(forKeys: [
                .isDirectoryKey,
                .contentModificationDateKey,
                .creationDateKey,
            ]),
            values.isDirectory == true
            else { continue }

            let size = recursiveAllocatedSize(entry)
            guard size >= minSize else { continue }

            output.append(
                FileItem(
                    url: entry,
                    name: entry.lastPathComponent,
                    size: size,
                    allocatedSize: size,
                    isDirectory: true,
                    isPackage: false,
                    creationDate: values.creationDate,
                    modificationDate: values.contentModificationDate
                )
            )
        }
        return output
    }

    private static func scanVirtualMachinePackages(minSize: UInt64) -> [FileItem] {
        let home = MCConstants.home
        let roots = [
            home.appending(path: "Parallels"),
            home.appending(path: "Documents/Parallels"),
            home.appending(path: "Virtual Machines.localized"),
            home.appending(path: "Documents/Virtual Machines.localized"),
            home.appending(path: "UTM"),
            home.appending(path: "Documents/UTM"),
        ]

        let fm = FileManager.default
        var output: [FileItem] = []
        var seen = Set<URL>()

        for root in roots {
            if Task.isCancelled { break }
            guard fm.fileExists(atPath: root.path(percentEncoded: false)),
                  let enumerator = fm.enumerator(
                    at: root,
                    includingPropertiesForKeys: [
                        .isDirectoryKey,
                        .isPackageKey,
                        .contentModificationDateKey,
                        .creationDateKey,
                    ],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                  )
            else { continue }

            while let url = enumerator.nextObject() as? URL {
                if Task.isCancelled { break }

                let ext = url.pathExtension.lowercased()
                guard vmPackageExtensions.contains(ext) else { continue }

                let standardized = url.standardizedFileURL
                guard seen.insert(standardized).inserted else {
                    enumerator.skipDescendants()
                    continue
                }

                guard let values = try? url.resourceValues(forKeys: [
                    .isDirectoryKey,
                    .isPackageKey,
                    .contentModificationDateKey,
                    .creationDateKey,
                ]),
                values.isDirectory == true
                else { continue }

                // Treat the VM package as one review item. Never enumerate its
                // contents into separate cleanup rows.
                enumerator.skipDescendants()

                let size = recursiveAllocatedSize(url)
                guard size >= minSize else { continue }

                output.append(
                    FileItem(
                        url: url,
                        name: url.lastPathComponent,
                        size: size,
                        allocatedSize: size,
                        isDirectory: true,
                        isPackage: values.isPackage ?? true,
                        creationDate: values.creationDate,
                        modificationDate: values.contentModificationDate
                    )
                )
            }
        }

        return output
    }

    private static func recursiveAllocatedSize(_ root: URL) -> UInt64 {
        let fm = FileManager.default

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .totalFileAllocatedSizeKey,
                .fileAllocatedSizeKey,
                .fileSizeKey,
            ],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: UInt64 = 0
        while let url = enumerator.nextObject() as? URL {
            if Task.isCancelled { break }

            guard let values = try? url.resourceValues(forKeys: [
                .isRegularFileKey,
                .totalFileAllocatedSizeKey,
                .fileAllocatedSizeKey,
                .fileSizeKey,
            ]),
            values.isRegularFile == true
            else { continue }

            let bytes = values.totalFileAllocatedSize
                ?? values.fileAllocatedSize
                ?? values.fileSize
                ?? 0
            if bytes > 0 {
                total += UInt64(bytes)
            }
        }

        return total
    }
}
