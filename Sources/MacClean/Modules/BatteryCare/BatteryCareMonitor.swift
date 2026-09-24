import Foundation
import Observation
import MacCleanKit

struct SMCCapabilityReport: Sendable, Equatable {
    let existingKeys: Set<String>

    var capabilities: Set<BatteryControlCapability> {
        var result: Set<BatteryControlCapability> = [.batteryTemperature]

        let hasFirmwareLimit = ["bfD0", "bfE0", "bfF0"].allSatisfy(existingKeys.contains)
        let hasTahoeChargeGate = existingKeys.contains("CHTE")
        let hasLegacyChargeGate = existingKeys.contains("CH0B") || existingKeys.contains("CH0C")

        if hasFirmwareLimit || hasTahoeChargeGate || hasLegacyChargeGate {
            result.insert(.chargeLimit)
        }
        if hasTahoeChargeGate || hasLegacyChargeGate {
            result.insert(.inhibitCharge)
        }
        if existingKeys.contains("CHIE") || existingKeys.contains("CH0I") {
            result.insert(.forceDischarge)
        }
        if existingKeys.contains("ACLC") {
            result.insert(.magsafeLED)
        }
        return result
    }

    var controlFamily: String {
        if ["bfD0", "bfE0", "bfF0"].allSatisfy(existingKeys.contains) {
            return "macOS 27 韌體充電上限"
        }
        if existingKeys.contains("CHTE"), existingKeys.contains("CHIE") {
            return "新式 Apple Silicon（CHTE／CHIE）"
        }
        if (existingKeys.contains("CH0B") || existingKeys.contains("CH0C")),
           existingKeys.contains("CH0I") {
            return "傳統 Apple Silicon（CH0B／CH0C／CH0I）"
        }
        return "僅部分能力／未確認"
    }

    var summary: String {
        guard !existingKeys.isEmpty else { return "未偵測到可用的 SMC 控制鍵" }
        return "\(controlFamily)：\(existingKeys.sorted().joined(separator: "、"))"
    }
}

enum CompetingBatteryControllerProbe {
    private static let knownProcessFragments: [(String, String)] = [
        ("/Applications/AlDente.app/Contents/MacOS/AlDente", "AlDente"),
        ("/Library/PrivilegedHelperTools/com.apphousekitchen.aldente-pro.helper", "AlDente helper"),
        ("/Library/PrivilegedHelperTools/com.chenran.chargewatch.helper", "ChargeWatch"),
    ]

    static func detect() -> String? {
        for (fragment, name) in knownProcessFragments where processExists(matching: fragment) {
            return name
        }
        return nil
    }

    private static func processExists(matching fragment: String) -> Bool {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/pgrep")
        process.arguments = ["-f", fragment]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

enum SMCCapabilityProbe {
    private static let candidateKeys = [
        "bfD0", "bfE0", "bfF0", "CHWA", "CHLS", "CHTE", "CHIE", "CH0I", "CH0C", "CH0K", "CH0B", "ACLC",
        "CH0R", "CH0X", "CHNC", "CHSC", "BSFC", "BUIC", "CHCC", "CHCE",
    ]

    static func probe() -> SMCCapabilityReport {
        guard let smcURL = smcToolURL() else {
            return SMCCapabilityReport(existingKeys: [])
        }

        var keys = Set<String>()
        for key in candidateKeys where keyExists(key, using: smcURL) {
            keys.insert(key)
        }
        return SMCCapabilityReport(existingKeys: keys)
    }

    private static func smcToolURL() -> URL? {
        [
            "/usr/local/bin/smc",
            "/opt/homebrew/bin/smc",
            "/usr/bin/smc",
        ]
        .map { URL(filePath: $0) }
        .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func keyExists(_ key: String, using executable: URL) -> Bool {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = ["-r", "-k", key]
        process.standardOutput = pipe
        process.standardError = pipe

        let data: Data
        do {
            try process.run()
            data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
        } catch {
            return false
        }

        let output = String(decoding: data, as: UTF8.self)

        // The smc utility prints "no data" for existing keys it cannot decode.
        // That is still useful as a capability signal. SMCReadKey error = absent.
        return !output.contains("SMCReadKey()")
            && !output.localizedCaseInsensitiveContains("not found")
    }
}

@MainActor
@Observable
final class BatteryCareMonitor {
    private(set) var competingController: String?

    private(set) var snapshot = BatteryCareSnapshot(
        levelPercent: nil,
        isCharging: false,
        externalPowerConnected: false,
        temperatureCelsius: nil,
        cycleCount: nil,
        capabilities: [],
        hardwareControlEnabled: false,
        controlStatus: "正在讀取電池狀態…"
    )

    private var capabilityReport: SMCCapabilityReport?

    func refresh() async {
        let telemetry = await Task.detached(priority: .utility) {
            BatteryTelemetry.current()
        }.value

        let competing = await Task.detached(priority: .utility) {
            CompetingBatteryControllerProbe.detect()
        }.value
        competingController = competing

        let report: SMCCapabilityReport
        if let capabilityReport {
            report = capabilityReport
        } else {
            report = await Task.detached(priority: .utility) {
                SMCCapabilityProbe.probe()
            }.value
            capabilityReport = report
        }

        snapshot = BatteryCareSnapshot(
            levelPercent: telemetry.levelPercent,
            isCharging: telemetry.isCharging,
            externalPowerConnected: telemetry.externalPowerConnected,
            temperatureCelsius: telemetry.temperatureCelsius,
            cycleCount: telemetry.cycleCount,
            capabilities: report.capabilities,
            hardwareControlEnabled: false,
            controlStatus: competing.map {
                "唯讀模式：偵測到 \($0) 正在控制電池，CatCleaner 不會與其他控制器同時寫入 SMC"
            } ?? "唯讀模式：硬體控制 helper 尚未通過 M5 寫入／回滾驗證"
        )
    }

    var capabilitySummary: String {
        capabilityReport?.summary ?? "尚未探測"
    }
}
