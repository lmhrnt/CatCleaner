import AppIntents
import Foundation
import MacCleanKit

struct CatCleanerBatteryStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "查看 CatCleaner 電池狀態"
    static let description = IntentDescription("查看目前電量、充電狀態、電池溫度與 CatCleaner 目標充電上限。")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot = BatteryTelemetry.current()
        let level = snapshot.levelPercent.map { "\($0)%" } ?? "未知"
        let power = snapshot.externalPowerConnected ? "已接上電源" : "使用電池"
        let charging = snapshot.isCharging ? "正在充電" : "未充電"
        let temperature = snapshot.temperatureCelsius.map {
            String(format: "%.1f°C", $0)
        } ?? "未知"
        let target = BatteryCarePreferences.chargeLimit

        return .result(
            dialog: IntentDialog(
                stringLiteral: "目前電量 \(level)，\(power)，\(charging)，電池溫度 \(temperature)。CatCleaner 目標充電上限為 \(target)% 。"
            )
        )
    }
}

struct CatCleanerSetChargeLimitIntent: AppIntent {
    static let title: LocalizedStringResource = "設定 CatCleaner 目標充電上限"
    static let description = IntentDescription(
        "設定 CatCleaner Battery Care 的目標充電上限。硬體控制 helper 尚未啟用前，只會更新 CatCleaner 設定，不會直接寫入 SMC。"
    )
    static let openAppWhenRun = false

    @Parameter(
        title: "充電上限",
        description: "可設定 20% 到 100%。"
    )
    var limit: Int

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let clamped = BatteryCarePolicy.clampedChargeLimit(limit)
        BatteryCarePreferences.chargeLimit = clamped

        return .result(
            dialog: IntentDialog(
                stringLiteral: "已將 CatCleaner 目標充電上限設為 \(clamped)% 。目前硬體控制仍為唯讀模式，因此尚未改變 Mac 的實際充電控制。"
            )
        )
    }
}

struct CatCleanerBatteryShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CatCleanerBatteryStatusIntent(),
            phrases: [
                "查看 \(.applicationName) 電池狀態",
                "用 \(.applicationName) 查看電池",
            ],
            shortTitle: "電池狀態",
            systemImageName: "battery.75percent"
        )

        AppShortcut(
            intent: CatCleanerSetChargeLimitIntent(),
            phrases: [
                "設定 \(.applicationName) 充電上限",
                "用 \(.applicationName) 設定電池上限",
            ],
            shortTitle: "設定充電上限",
            systemImageName: "battery.50percent"
        )
    }
}
