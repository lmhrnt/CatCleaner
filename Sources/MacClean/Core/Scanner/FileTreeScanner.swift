import Foundation
import Darwin
import MacCleanKit

public actor FileTreeScanner {
    private let resourceKeys: Set<URLResourceKey> = [
        .fileSizeKey, .fileAllocatedSizeKey,
        .totalFileSizeKey, .totalFileAllocatedSizeKey,
        .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey,
        .contentModificationDateKey, .creationDateKey,
        .contentTypeKey, .nameKey, .isHiddenKey,
    ]

    public init() {}

    public nonisolated func scan(root: URL, skipHidden: Bool = false) -> AsyncStream<FileItem> {
        let keys = resourceKeys

        return AsyncStream { continuation in
            let options: FileManager.DirectoryEnumerationOptions = skipHidden
                ? [.skipsHiddenFiles, .skipsPackageDescendants]
                : [.skipsPackageDescendants]

            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: options
            ) else {
                continuation.finish()
                return
            }

            while let obj = enumerator.nextObject() {
                if Task.isCancelled { break }
                guard let fileURL = obj as? URL else { continue }
                guard let item = Self.makeFileItem(from: fileURL, keys: keys) else { continue }
                continuation.yield(item)
            }

            continuation.finish()
        }
    }

    public func scanWithSizeAggregation(
        root: URL,
        onProgress: @Sendable (Int) -> Void = { _ in }
    ) async -> FileNode {
        let keys = resourceKeys
        let standardizedRoot = root.standardizedFileURL
        let rootNode = FileNode(
            url: standardizedRoot,
            name: standardizedRoot.lastPathComponent
        )
        let rootDeviceID = Self.filesystemDeviceID(of: standardizedRoot)

        guard let enumerator = FileManager.default.enumerator(
            at: standardizedRoot,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsPackageDescendants]
        ) else {
            return rootNode
        }

        // Normalize: strip any trailing slash so root and child-derived
        // parent paths line up. `URL.deletingLastPathComponent()` on a file
        // URL returns a directory URL whose `path(percentEncoded:)` ends
        // in "/" — that mismatched the root key unconditionally and
        // silently produced an empty tree.
        func key(_ url: URL) -> String {
            var p = url.path(percentEncoded: false)
            if p.hasSuffix("/") && p.count > 1 { p = String(p.dropLast()) }
            // Canonicalize macOS firmlinks as a pure string op: enumerator
            // child URLs resolve through /private/var even when the root is
            // the /var symlink (temp dir, firmlinked volumes), so map
            // /private/{var,tmp,etc} back to /{var,tmp,etc} on both sides.
            for firmlink in ["/private/var", "/private/tmp", "/private/etc"] {
                if p == firmlink || p.hasPrefix(firmlink + "/") {
                    return String(p.dropFirst("/private".count))
                }
            }
            return p
        }

        var nodeMap: [String: FileNode] = [key(standardizedRoot): rootNode]
        var iterationCount = 0

        while let obj = enumerator.nextObject() {
            if Task.isCancelled { break }

            iterationCount += 1
            if iterationCount % 200 == 0 {
                onProgress(iterationCount)
                await Task.yield()
            }

            guard let fileURL = obj as? URL else { continue }
            guard let values = try? fileURL.resourceValues(forKeys: keys) else { continue }
            let size = UInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
            let isDir = values.isDirectory ?? false

            if isDir {
                let childDeviceID = Self.filesystemDeviceID(of: fileURL)
                if Self.shouldPruneMountedDirectory(
                    root: standardizedRoot,
                    child: fileURL,
                    rootDeviceID: rootDeviceID,
                    childDeviceID: childDeviceID
                ) {
                    enumerator.skipDescendants()
                    continue
                }
            }

            let ext = values.name?.components(separatedBy: ".").last?.lowercased() ?? fileURL.pathExtension.lowercased()

            let node = FileNode(
                url: fileURL,
                name: values.name ?? fileURL.lastPathComponent,
                size: isDir ? 0 : size,
                isDirectory: isDir,
                fileExtension: ext
            )

            let parentPath = key(fileURL.deletingLastPathComponent())
            if let parent = nodeMap[parentPath] {
                parent.addChild(node)
            }

            if isDir {
                nodeMap[key(fileURL)] = node
            }
        }

        onProgress(iterationCount)
        rootNode.computeTotalSize()
        return rootNode
    }

    static func shouldPruneMountedDirectory(
        root: URL,
        child: URL,
        rootDeviceID: UInt64?,
        childDeviceID: UInt64?
    ) -> Bool {
        let rootPath = root.standardizedFileURL.path(percentEncoded: false)
        let childPath = child.standardizedFileURL.path(percentEncoded: false)

        // A root-volume scan must never descend into other mounted-volume
        // namespaces. /Volumes contains external disks/disk images, while
        // /System/Volumes contains APFS helper volumes such as Data. On modern
        // macOS the root volume and /System/Volumes/Data can report the same
        // st_dev, so device-ID checks alone do not prevent counting the same
        // logical user data again through the Data mount.
        if rootPath == "/" {
            if childPath == "/Volumes" || childPath.hasPrefix("/Volumes/") {
                return true
            }
            if childPath == "/System/Volumes"
                || childPath.hasPrefix("/System/Volumes/")
            {
                return true
            }
        }

        // For all other nested mount points, a different filesystem device is
        // a clear boundary. This also keeps a Home-folder scan from silently
        // traversing a FUSE/network/external mount nested below the home tree.
        if let rootDeviceID, let childDeviceID, rootDeviceID != childDeviceID {
            return true
        }

        return false
    }

    private static func filesystemDeviceID(of url: URL) -> UInt64? {
        var metadata = stat()
        guard lstat(url.path(percentEncoded: false), &metadata) == 0 else {
            return nil
        }
        return UInt64(metadata.st_dev)
    }

    private static func makeFileItem(from url: URL, keys: Set<URLResourceKey>) -> FileItem? {
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }

        return FileItem(
            url: url,
            name: values.name ?? url.lastPathComponent,
            size: UInt64(values.totalFileSize ?? values.fileSize ?? 0),
            allocatedSize: UInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0),
            isDirectory: values.isDirectory ?? false,
            isSymlink: values.isSymbolicLink ?? false,
            isPackage: values.isPackage ?? false,
            contentType: values.contentType,
            creationDate: values.creationDate,
            modificationDate: values.contentModificationDate
        )
    }
}

public final class FileNode: @unchecked Sendable {
    public let url: URL
    public let name: String
    public private(set) var size: UInt64
    public let isDirectory: Bool
    public let fileExtension: String
    public private(set) var children: [FileNode] = []
    public private(set) var totalSize: UInt64 = 0

    public init(url: URL, name: String, size: UInt64 = 0, isDirectory: Bool = true, fileExtension: String = "") {
        self.url = url
        self.name = name
        self.size = size
        self.isDirectory = isDirectory
        self.fileExtension = fileExtension
        self.totalSize = size
    }

    public func addChild(_ child: FileNode) {
        children.append(child)
    }

    @discardableResult
    public func computeTotalSize() -> UInt64 {
        if children.isEmpty {
            totalSize = size
        } else {
            totalSize = size + children.reduce(0) { $0 + $1.computeTotalSize() }
        }
        return totalSize
    }

    public var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file)
    }
}
