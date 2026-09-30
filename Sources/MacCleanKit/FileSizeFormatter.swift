import Foundation

public enum FileSizeFormatter {
    public static func format(_ bytes: UInt64) -> String {
        format(Int64(clamping: bytes))
    }

    public static func format(_ bytes: Int64) -> String {
        if let small = smallByteParts(bytes) {
            return "\(small.value) \(small.unit)"
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    public static func shortFormat(_ bytes: UInt64) -> (value: String, unit: String) {
        if let small = smallByteParts(Int64(clamping: bytes)) {
            return small
        }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.includesUnit = false
        let value = formatter.string(fromByteCount: Int64(bytes))

        let unitFormatter = ByteCountFormatter()
        unitFormatter.countStyle = .file
        unitFormatter.includesCount = false
        let unit = unitFormatter.string(fromByteCount: Int64(bytes))

        return (value, unit)
    }

    /// Sub-kilobyte sizes, pluralized in the app's UI language.
    ///
    /// `ByteCountFormatter` follows the macOS system locale rather than
    /// CatCleaner's own language setting, so on a Chinese system with the app
    /// in English it printed "395 byte". Chinese keeps the system formatter's
    /// output (nil here); English and Russian get proper plural forms.
    static func smallByteParts(_ bytes: Int64) -> (value: String, unit: String)? {
        guard bytes > 0, bytes < 1000 else { return nil }
        switch AppLanguage.current.resolved {
        case .system, .en:
            return ("\(bytes)", bytes == 1 ? "byte" : "bytes")
        case .ru:
            return ("\(bytes)", L10n.russianPlural(Int(bytes), one: "байт", few: "байта", many: "байт"))
        case .zhHans, .zhHantTW:
            return nil
        }
    }
}
