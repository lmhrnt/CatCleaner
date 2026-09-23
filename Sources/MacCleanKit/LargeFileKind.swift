import Foundation

/// User-facing classification for large-file review.
///
/// This is deliberately separate from ScanCategory: ScanCategory describes why
/// an item was discovered ("large" / "old"), while LargeFileKind describes
/// what the user is looking at. Classification never grants cleanup authority.
public enum LargeFileKind: String, CaseIterable, Identifiable, Sendable {
    case video
    case audio
    case images
    case documents
    case archives
    case installers
    case diskImages
    case virtualMachines
    case iosBackups
    case other

    public var id: Self { self }

    public var title: String {
        switch self {
        case .video: L10n.tr("视频", "Video", "Видео")
        case .audio: L10n.tr("音频", "Audio", "Аудио")
        case .images: L10n.tr("图片", "Images", "Изображения")
        case .documents: L10n.tr("文档", "Documents", "Документы")
        case .archives: L10n.tr("压缩包", "Archives", "Архивы")
        case .installers: L10n.tr("安装包", "Installers", "Установщики")
        case .diskImages: L10n.tr("磁盘映像", "Disk Images", "Образы дисков")
        case .virtualMachines: L10n.tr("虚拟机", "Virtual Machines", "Виртуальные машины")
        case .iosBackups: L10n.tr("iPhone / iPad 备份", "iPhone / iPad Backups", "Резервные копии iPhone / iPad")
        case .other: L10n.tr("其他", "Other", "Другое")
        }
    }

    public var systemImage: String {
        switch self {
        case .video: "film"
        case .audio: "waveform"
        case .images: "photo"
        case .documents: "doc.text"
        case .archives: "archivebox"
        case .installers: "shippingbox"
        case .diskImages: "externaldrive"
        case .virtualMachines: "desktopcomputer"
        case .iosBackups: "iphone.gen3"
        case .other: "doc"
        }
    }

    public static func classify(_ item: FileItem) -> LargeFileKind {
        classify(
            url: item.url,
            isDirectory: item.isDirectory,
            isPackage: item.isPackage
        )
    }

    public static func classify(
        url: URL,
        isDirectory: Bool = false,
        isPackage: Bool = false
    ) -> LargeFileKind {
        let standardized = url.standardizedFileURL
        let path = standardized.path(percentEncoded: false).lowercased()
        let ext = standardized.pathExtension.lowercased()

        if isIOSBackupPath(path) {
            return .iosBackups
        }

        if isVirtualMachinePath(path, extension: ext, isDirectory: isDirectory, isPackage: isPackage) {
            return .virtualMachines
        }

        switch ext {
        case "mp4", "mov", "m4v", "avi", "mkv", "wmv", "flv", "webm", "mpeg", "mpg":
            return .video
        case "mp3", "wav", "flac", "aac", "m4a", "ogg", "wma", "aiff", "aif":
            return .audio
        case "jpg", "jpeg", "png", "gif", "bmp", "tif", "tiff", "heic", "heif", "webp", "raw", "dng":
            return .images
        case "pdf", "doc", "docx", "pages", "rtf", "txt", "md",
             "xls", "xlsx", "numbers", "csv", "ppt", "pptx", "key":
            return .documents
        case "zip", "gz", "tgz", "tar", "rar", "7z", "bz2", "xz", "zst":
            return .archives
        case "pkg", "mpkg":
            return .installers
        case "dmg", "iso", "img", "sparseimage", "sparsebundle":
            return .diskImages
        default:
            return .other
        }
    }

    /// De-duplicates by URL, groups by kind, and sorts each group largest-first.
    public static func grouped(
        _ items: [FileItem]
    ) -> [(kind: LargeFileKind, items: [FileItem])] {
        var unique: [URL: FileItem] = [:]
        for item in items {
            let key = item.url.standardizedFileURL
            if let existing = unique[key] {
                if item.size > existing.size {
                    unique[key] = item
                }
            } else {
                unique[key] = item
            }
        }

        var buckets: [LargeFileKind: [FileItem]] = [:]
        for item in unique.values {
            buckets[classify(item), default: []].append(item)
        }

        return LargeFileKind.allCases.compactMap { kind in
            guard var values = buckets[kind], !values.isEmpty else { return nil }
            values.sort {
                if $0.size == $1.size {
                    return $0.url.path(percentEncoded: false)
                        < $1.url.path(percentEncoded: false)
                }
                return $0.size > $1.size
            }
            return (kind, values)
        }
    }

    private static func isIOSBackupPath(_ lowercasedPath: String) -> Bool {
        lowercasedPath.contains(
            "/library/application support/mobilesync/backup/"
        )
    }

    private static func isVirtualMachinePath(
        _ lowercasedPath: String,
        extension ext: String,
        isDirectory: Bool,
        isPackage: Bool
    ) -> Bool {
        let packageExtensions: Set<String> = [
            "pvm", "vmwarevm", "utm", "vbox"
        ]
        if packageExtensions.contains(ext), isDirectory || isPackage {
            return true
        }

        let diskExtensions: Set<String> = [
            "vmdk", "vdi", "qcow2", "hdd", "vhd", "vhdx", "avhdx"
        ]
        if diskExtensions.contains(ext) {
            return true
        }

        // Files inside a known VM package should remain in the VM bucket even
        // when the package itself was not returned by a scanner.
        return lowercasedPath.contains(".pvm/")
            || lowercasedPath.contains(".vmwarevm/")
            || lowercasedPath.contains(".utm/")
    }
}
