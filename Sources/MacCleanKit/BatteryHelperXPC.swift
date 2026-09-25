import Foundation

@objc public protocol BatteryHelperXPCProtocol {
    /// Returns a property-list dictionary describing helper identity and whether
    /// the fixed SMC probe backend is available. This method never writes SMC.
    func status(withReply reply: @escaping (NSDictionary) -> Void)

    /// Bounded capability probe only. The helper reads CHIE, writes back the
    /// exact same byte sequence, then reads it again and requires equality.
    /// The caller cannot choose a key or value.
    func probeSameValueWrite(withReply reply: @escaping (NSDictionary) -> Void)
}

public enum BatteryHelperResponseKey {
    public static let ok = "ok"
    public static let message = "message"
    public static let helperEUID = "helperEUID"
    public static let helperPID = "helperPID"
    public static let clientValidated = "clientValidated"
    public static let smcToolPath = "smcToolPath"
    public static let beforeValue = "beforeValue"
    public static let afterValue = "afterValue"
    public static let writeExitCode = "writeExitCode"
}

public enum BatteryHelperProbePolicy {
    public static let fixedProbeKey = "CHIE"

    /// Keep the first privileged milestone semantically inert. A successful
    /// probe proves only that root can write the existing value back and read
    /// it consistently; it does not authorize real battery-control writes.
    public static func isSameValueProbe(before: String, after: String) -> Bool {
        normalizedHexByte(before) == normalizedHexByte(after)
    }

    public static func normalizedHexByte(_ value: String) -> String? {
        let compact = value
            .trimmingCharacters(
                in: .whitespacesAndNewlines.union(.punctuationCharacters)
            )
            .lowercased()
            .replacingOccurrences(of: "0x", with: "")
        guard compact.count == 2,
              compact.allSatisfy({ $0.isHexDigit }) else {
            return nil
        }
        return compact
    }
}
