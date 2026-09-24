import Foundation

public enum BatteryCarePreferences {
    public static let chargeLimitKey = "batteryCareChargeLimit"
    public static let automaticDischargeKey = "batteryCareAutomaticDischarge"
    public static let clamshellDischargeKey = "batteryCareClamshellDischarge"
    public static let heatProtectionKey = "batteryCareHeatProtection"
    public static let heatLimitKey = "batteryCareHeatLimit"
    public static let sailingModeKey = "batteryCareSailingMode"
    public static let sailingRangeKey = "batteryCareSailingRange"
    public static let magsafeLEDKey = "batteryCareMagSafeLED"
    public static let menuBarStyleKey = "batteryCareMenuBarStyle"
    public static let compactPopupKey = "batteryCareCompactPopup"

    public static var chargeLimit: Int {
        get {
            let stored = SharedAppState.defaults.object(forKey: chargeLimitKey) as? Int ?? 80
            return BatteryCarePolicy.clampedChargeLimit(stored)
        }
        set {
            SharedAppState.defaults.set(
                BatteryCarePolicy.clampedChargeLimit(newValue),
                forKey: chargeLimitKey
            )
        }
    }
}

public enum BatteryCareMenuBarStyle: String, CaseIterable, Identifiable, Sendable {
    case battery
    case percent
    case temperature
    case minimal

    public var id: String { rawValue }

    public var localizedName: String {
        switch self {
        case .battery: "電池"
        case .percent: "百分比"
        case .temperature: "溫度"
        case .minimal: "極簡"
        }
    }

    public static func resolve(_ rawValue: String?) -> Self {
        rawValue.flatMap(Self.init(rawValue:)) ?? .battery
    }
}

public enum BatteryControlCapability: String, CaseIterable, Sendable, Codable {
    case chargeLimit
    case inhibitCharge
    case forceDischarge
    case magsafeLED
    case batteryTemperature
}

public struct BatteryCareSnapshot: Sendable, Equatable {
    public let levelPercent: Int?
    public let isCharging: Bool
    public let externalPowerConnected: Bool
    public let temperatureCelsius: Double?
    public let cycleCount: Int?
    public let capabilities: Set<BatteryControlCapability>
    public let hardwareControlEnabled: Bool
    public let controlStatus: String

    public init(
        levelPercent: Int?,
        isCharging: Bool,
        externalPowerConnected: Bool,
        temperatureCelsius: Double?,
        cycleCount: Int?,
        capabilities: Set<BatteryControlCapability>,
        hardwareControlEnabled: Bool,
        controlStatus: String
    ) {
        self.levelPercent = levelPercent
        self.isCharging = isCharging
        self.externalPowerConnected = externalPowerConnected
        self.temperatureCelsius = temperatureCelsius
        self.cycleCount = cycleCount
        self.capabilities = capabilities
        self.hardwareControlEnabled = hardwareControlEnabled
        self.controlStatus = controlStatus
    }
}

public enum BatteryCareAction: String, CaseIterable, Identifiable, Sendable {
    case chargeLimiter
    case discharge
    case automaticDischarge
    case clamshellDischarge
    case heatProtection
    case sailingMode
    case magsafeLED
    case topUp
    case calibration
    case shortcuts
    case menuBarCustomization
    case popupCustomization

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .chargeLimiter: "充電上限"
        case .discharge: "放電"
        case .automaticDischarge: "自動放電"
        case .clamshellDischarge: "闔蓋模式放電"
        case .heatProtection: "過熱保護"
        case .sailingMode: "航行模式"
        case .magsafeLED: "MagSafe 指示燈控制"
        case .topUp: "充到 100%"
        case .calibration: "校正模式"
        case .shortcuts: "Apple 捷徑"
        case .menuBarCustomization: "自訂選單列圖示"
        case .popupCustomization: "自訂彈出視窗"
        }
    }

    public var requiresHardwareWrite: Bool {
        switch self {
        case .shortcuts, .menuBarCustomization, .popupCustomization:
            false
        default:
            true
        }
    }
}

public struct BatteryCarePolicy: Sendable, Equatable {
    public static let chargeLimitRange = 20...100
    public static let heatProtectionRange = 30...50
    public static let sailingRange = 1...20

    public static func clampedChargeLimit(_ value: Int) -> Int {
        min(max(value, chargeLimitRange.lowerBound), chargeLimitRange.upperBound)
    }

    public static func clampedHeatLimit(_ value: Int) -> Int {
        min(max(value, heatProtectionRange.lowerBound), heatProtectionRange.upperBound)
    }

    public static func clampedSailingRange(_ value: Int) -> Int {
        min(max(value, sailingRange.lowerBound), sailingRange.upperBound)
    }

    public static func shouldPauseCharging(
        levelPercent: Int,
        chargeLimit: Int,
        temperatureCelsius: Double?,
        heatProtectionEnabled: Bool,
        heatLimitCelsius: Int
    ) -> Bool {
        if levelPercent >= clampedChargeLimit(chargeLimit) { return true }
        if heatProtectionEnabled,
           let temperatureCelsius,
           temperatureCelsius >= Double(clampedHeatLimit(heatLimitCelsius)),
           levelPercent >= 15 {
            return true
        }
        return false
    }

    public static func shouldResumeCharging(
        levelPercent: Int,
        chargeLimit: Int,
        sailingEnabled: Bool,
        sailingRange: Int
    ) -> Bool {
        let limit = clampedChargeLimit(chargeLimit)
        guard sailingEnabled else { return levelPercent < limit }
        return levelPercent <= max(0, limit - clampedSailingRange(sailingRange))
    }

    public static func shouldAutomaticallyDischarge(
        levelPercent: Int,
        chargeLimit: Int,
        automaticDischargeEnabled: Bool,
        externalPowerConnected: Bool
    ) -> Bool {
        automaticDischargeEnabled
            && externalPowerConnected
            && levelPercent > clampedChargeLimit(chargeLimit)
    }
}
