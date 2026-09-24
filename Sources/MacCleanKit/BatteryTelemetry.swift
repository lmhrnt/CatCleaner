import Foundation
import IOKit
import IOKit.ps

public enum BatteryTelemetry {
    public struct Snapshot: Sendable, Equatable {
        public let levelPercent: Int?
        public let isCharging: Bool
        public let externalPowerConnected: Bool
        public let cycleCount: Int?
        public let temperatureCelsius: Double?

        public init(
            levelPercent: Int?,
            isCharging: Bool,
            externalPowerConnected: Bool,
            cycleCount: Int?,
            temperatureCelsius: Double?
        ) {
            self.levelPercent = levelPercent
            self.isCharging = isCharging
            self.externalPowerConnected = externalPowerConnected
            self.cycleCount = cycleCount
            self.temperatureCelsius = temperatureCelsius
        }
    }

    public static func current() -> Snapshot {
        let registry = smartBatteryRegistryValues()
        let temperature = HardwareSensorNormalizer.batteryTemperatureCelsius(
            from: registry.compactMapValues { $0 as? NSNumber }
        )
        let cycleCount = (registry["CycleCount"] as? NSNumber)?.intValue

        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [Any],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(
                info,
                source as CFTypeRef
              )?.takeUnretainedValue() as? [String: Any] else {
            return Snapshot(
                levelPercent: nil,
                isCharging: false,
                externalPowerConnected: false,
                cycleCount: cycleCount,
                temperatureCelsius: temperature
            )
        }

        let current = description[kIOPSCurrentCapacityKey] as? Int
        let maximum = description[kIOPSMaxCapacityKey] as? Int
        let level: Int?
        if let current, let maximum, maximum > 0 {
            level = Int((Double(current) / Double(maximum) * 100).rounded())
        } else {
            level = nil
        }

        let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
        let sourceState = description[kIOPSPowerSourceStateKey] as? String
        let externalPower = sourceState == (kIOPSACPowerValue as String)

        return Snapshot(
            levelPercent: level,
            isCharging: isCharging,
            externalPowerConnected: externalPower,
            cycleCount: cycleCount,
            temperatureCelsius: temperature
        )
    }

    private static func smartBatteryRegistryValues() -> [String: Any] {
        guard let matching = IOServiceMatching("AppleSmartBattery") else { return [:] }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return [:] }
        defer { IOObjectRelease(service) }

        var values: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(
            service,
            &values,
            kCFAllocatorDefault,
            0
        ) == KERN_SUCCESS,
        let dictionary = values?.takeRetainedValue() as? [String: Any] else {
            return [:]
        }
        return dictionary
    }
}
