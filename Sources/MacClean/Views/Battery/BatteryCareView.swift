import SwiftUI
import ServiceManagement
import MacCleanKit

struct BatteryCareView: View {
    @State private var monitor = BatteryCareMonitor()
    @State private var helperManager = BatteryHardwareHelperManager.shared

    @AppStorage(BatteryCarePreferences.chargeLimitKey, store: SharedAppState.defaults) private var chargeLimit = 80
    @AppStorage(BatteryCarePreferences.automaticDischargeKey, store: SharedAppState.defaults) private var automaticDischarge = true
    @AppStorage(BatteryCarePreferences.clamshellDischargeKey, store: SharedAppState.defaults) private var clamshellDischarge = false
    @AppStorage(BatteryCarePreferences.heatProtectionKey, store: SharedAppState.defaults) private var heatProtection = true
    @AppStorage(BatteryCarePreferences.heatLimitKey, store: SharedAppState.defaults) private var heatLimit = 35
    @AppStorage(BatteryCarePreferences.sailingModeKey, store: SharedAppState.defaults) private var sailingMode = true
    @AppStorage(BatteryCarePreferences.sailingRangeKey, store: SharedAppState.defaults) private var sailingRange = 5
    @AppStorage(BatteryCarePreferences.magsafeLEDKey, store: SharedAppState.defaults) private var magsafeLED = false
    @AppStorage(BatteryCarePreferences.menuBarStyleKey, store: SharedAppState.defaults) private var menuBarStyle = "battery"
    @AppStorage(BatteryCarePreferences.compactPopupKey, store: SharedAppState.defaults) private var compactPopup = false
    @State private var hardwareControlMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                telemetryCards
                hardwareGate
                chargingSection
                protectionSection
                utilitySection
                appearanceSection
                compatibilitySection
            }
            .padding(24)
            .frame(maxWidth: 920, alignment: .leading)
        }
        .task {
            async let monitorRefresh: Void = monitor.refresh()
            async let helperRefresh: Void = helperManager.refresh()
            _ = await (monitorRefresh, helperRefresh)
        }
        .refreshable {
            async let monitorRefresh: Void = monitor.refresh()
            async let helperRefresh: Void = helperManager.refresh()
            _ = await (monitorRefresh, helperRefresh)
        }
        .alert(
            "硬體控制尚未啟用",
            isPresented: Binding(
                get: { hardwareControlMessage != nil },
                set: { if !$0 { hardwareControlMessage = nil } }
            )
        ) {
            Button("確定") {
                hardwareControlMessage = nil
            }
        } message: {
            Text(hardwareControlMessage ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "battery.75percent")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 3) {
                Text("電池保養")
                    .font(.title2.weight(.semibold))
                Text("充電上限、溫度保護、放電與電池校正")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("重新讀取") {
                Task { await monitor.refresh() }
            }
        }
    }

    private var telemetryCards: some View {
        let snapshot = monitor.snapshot
        return HStack(spacing: 12) {
            metricCard(
                title: "目前電量",
                value: snapshot.levelPercent.map { "\($0)%" } ?? "—",
                icon: "battery.75percent"
            )
            metricCard(
                title: "電源",
                value: snapshot.externalPowerConnected ? "已接上電源" : "使用電池",
                icon: snapshot.externalPowerConnected ? "powerplug.fill" : "bolt.slash"
            )
            metricCard(
                title: "充電狀態",
                value: snapshot.isCharging ? "正在充電" : "未充電",
                icon: snapshot.isCharging ? "bolt.fill" : "pause.circle"
            )
            metricCard(
                title: "電池溫度",
                value: snapshot.temperatureCelsius.map { String(format: "%.1f°C", $0) } ?? "—",
                icon: "thermometer.medium"
            )
            metricCard(
                title: "循環次數",
                value: snapshot.cycleCount.map(String.init) ?? "—",
                icon: "arrow.triangle.2.circlepath"
            )
        }
    }

    private func metricCard(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var hardwareGate: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: monitor.snapshot.hardwareControlEnabled
                    ? "checkmark.shield.fill"
                    : "lock.shield")
                    .foregroundStyle(monitor.snapshot.hardwareControlEnabled ? .green : .orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text(monitor.snapshot.hardwareControlEnabled
                        ? "硬體控制已啟用"
                        : "硬體控制目前維持唯讀")
                        .font(.headline)
                    Text(monitor.snapshot.controlStatus)
                        .foregroundStyle(.secondary)
                    Text("目前偵測到的 SMC 鍵：\(monitor.capabilitySummary)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    if monitor.directSMCWriteBlocked {
                        Text("此韌體版本對一般第三方直接 SMC 寫入有限制。macOS 26.4 以上仍提供 80%～100% 的原生充電上限。")
                            .font(.caption)
                            .foregroundStyle(.orange)

                        Link(
                            "開啟 macOS 電池設定",
                            destination: URL(
                                string: "x-apple.systempreferences:com.apple.Battery-Settings.extension"
                            )!
                        )
                        .font(.caption.weight(.semibold))
                    }

                    Divider()
                        .padding(.vertical, 4)

                    HStack {
                        Text("CatCleaner 特權 helper")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(helperManager.statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(helperManager.helperStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let lastProbeMessage = helperManager.lastProbeMessage {
                        Label(
                            lastProbeMessage,
                            systemImage: helperManager.lastProbePassed
                                ? "checkmark.shield.fill"
                                : "xmark.shield"
                        )
                        .font(.caption)
                        .foregroundStyle(helperManager.lastProbePassed ? .green : .orange)
                    }

                    helperControlButtons
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("安全狀態", systemImage: "shield.checkered")
        }
    }

    @ViewBuilder
    private var helperControlButtons: some View {
        HStack(spacing: 8) {
            switch helperManager.status {
            case .notRegistered, .notFound:
                Button("註冊硬體 helper") {
                    Task { await helperManager.register() }
                }

            case .requiresApproval:
                Button("開啟背景項目設定") {
                    helperManager.openApprovalSettings()
                }
                Button("重新檢查") {
                    Task { await helperManager.refresh() }
                }

            case .enabled:
                Button("重新檢查 helper") {
                    Task { await helperManager.refresh() }
                }
                Button("零變更寫入測試") {
                    Task { await helperManager.probeSameValueWrite() }
                }
                .disabled(monitor.competingController != nil)

                Button("停用 helper", role: .destructive) {
                    Task { await helperManager.unregister() }
                }

            @unknown default:
                Button("重新檢查") {
                    Task { await helperManager.refresh() }
                }
            }

            if helperManager.isBusy {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .disabled(helperManager.isBusy)

        if monitor.competingController != nil, helperManager.status == .enabled {
            Text("零變更寫入測試目前停用：先結束其他電池控制器，CatCleaner 才會允許 helper 寫入探針。")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private var chargingSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("充電上限")
                            .font(.headline)
                        Text("目標 \(chargeLimit)%")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Stepper(
                        "",
                        value: Binding(
                            get: { chargeLimit },
                            set: { chargeLimit = BatteryCarePolicy.clampedChargeLimit($0) }
                        ),
                        in: BatteryCarePolicy.chargeLimitRange
                    )
                    .labelsHidden()
                }

                Slider(
                    value: Binding(
                        get: { Double(chargeLimit) },
                        set: { chargeLimit = BatteryCarePolicy.clampedChargeLimit(Int($0.rounded())) }
                    ),
                    in: Double(BatteryCarePolicy.chargeLimitRange.lowerBound)...Double(BatteryCarePolicy.chargeLimitRange.upperBound),
                    step: 1
                )

                Divider()

                featureToggle(
                    "自動放電",
                    subtitle: "電量高於設定上限且接上電源時，自動降回目標電量。",
                    isOn: $automaticDischarge
                )
                featureToggle(
                    "闔蓋模式放電",
                    subtitle: "允許在外接螢幕／闔蓋模式下執行放電策略。",
                    isOn: $clamshellDischarge
                )

                HStack(spacing: 10) {
                    Button("立即放電至 \(chargeLimit)%") {
                        explainUnavailableHardwareControl("放電")
                    }
                    Button("充到 100%") {
                        explainUnavailableHardwareControl("充到 100%")
                    }
                }

                if !monitor.snapshot.hardwareControlEnabled {
                    Text("以上控制設定已可儲存；真正的 SMC 寫入會在 M5 helper 驗證通過後才啟用。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            Label("充電與放電", systemImage: "bolt.batteryblock")
        }
    }

    private var protectionSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                featureToggle(
                    "過熱保護",
                    subtitle: "電池溫度達到門檻時暫停充電；低電量安全區不強制暫停。",
                    isOn: $heatProtection
                )

                HStack {
                    Text("溫度上限")
                    Slider(
                        value: Binding(
                            get: { Double(heatLimit) },
                            set: { heatLimit = BatteryCarePolicy.clampedHeatLimit(Int($0.rounded())) }
                        ),
                        in: Double(BatteryCarePolicy.heatProtectionRange.lowerBound)...Double(BatteryCarePolicy.heatProtectionRange.upperBound),
                        step: 1
                    )
                    Text("\(heatLimit)°C")
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }
                .disabled(!heatProtection)

                Divider()

                featureToggle(
                    "航行模式",
                    subtitle: "達到上限後先停止充電，等電量自然下降一段範圍後再恢復充電。",
                    isOn: $sailingMode
                )

                HStack {
                    Text("航行範圍")
                    Slider(
                        value: Binding(
                            get: { Double(sailingRange) },
                            set: { sailingRange = BatteryCarePolicy.clampedSailingRange(Int($0.rounded())) }
                        ),
                        in: Double(BatteryCarePolicy.sailingRange.lowerBound)...Double(BatteryCarePolicy.sailingRange.upperBound),
                        step: 1
                    )
                    Text("\(sailingRange)%")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
                .disabled(!sailingMode)
            }
        } label: {
            Label("電池保護", systemImage: "thermometer.and.liquid.waves")
        }
    }

    private var utilitySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                featureToggle(
                    "MagSafe 指示燈控制",
                    subtitle: "依充電、放電與達標狀態調整 MagSafe 指示燈。",
                    isOn: $magsafeLED
                )

                HStack {
                    Button("開始校正模式") {
                        explainUnavailableHardwareControl("校正模式")
                    }
                    Link("Apple 捷徑", destination: URL(string: "shortcuts://")!)
                }

                Text("校正模式將採受控的充電／放電循環；硬體控制未啟用前不會執行。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Label("進階功能", systemImage: "wrench.and.screwdriver")
        }
    }

    private var appearanceSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Picker("選單列圖示", selection: $menuBarStyle) {
                    ForEach(BatteryCareMenuBarStyle.allCases) { style in
                        Text(style.localizedName).tag(style.rawValue)
                    }
                }

                Toggle("使用精簡彈出視窗", isOn: $compactPopup)
            }
        } label: {
            Label("外觀", systemImage: "paintpalette")
        }
    }

    private var compatibilitySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                capabilityRow("充電限制", capability: .chargeLimit)
                capabilityRow("停止充電", capability: .inhibitCharge)
                capabilityRow("強制放電", capability: .forceDischarge)
                capabilityRow("電池溫度", capability: .batteryTemperature)
                capabilityRow("MagSafe 指示燈", capability: .magsafeLED)
            }
        } label: {
            Label("硬體相容性", systemImage: "cpu")
        }
    }

    private func capabilityRow(
        _ title: String,
        capability: BatteryControlCapability
    ) -> some View {
        let keyVisible = monitor.snapshot.capabilities.contains(capability)
        let writeRestricted = monitor.directSMCWriteBlocked
            && capability != .batteryTemperature

        return HStack {
            Image(systemName: capabilityIcon(
                keyVisible: keyVisible,
                writeRestricted: writeRestricted
            ))
            .foregroundStyle(capabilityColor(
                keyVisible: keyVisible,
                writeRestricted: writeRestricted
            ))

            Text(title)
            Spacer()
            Text(capabilityStatus(
                keyVisible: keyVisible,
                writeRestricted: writeRestricted
            ))
            .foregroundStyle(.secondary)
        }
    }

    private func capabilityIcon(
        keyVisible: Bool,
        writeRestricted: Bool
    ) -> String {
        if writeRestricted, keyVisible { return "exclamationmark.triangle.fill" }
        return keyVisible ? "checkmark.circle.fill" : "minus.circle"
    }

    private func capabilityColor(
        keyVisible: Bool,
        writeRestricted: Bool
    ) -> Color {
        if writeRestricted, keyVisible { return .orange }
        return keyVisible ? .green : .secondary
    }

    private func capabilityStatus(
        keyVisible: Bool,
        writeRestricted: Bool
    ) -> String {
        if writeRestricted, keyVisible { return "Key 可見／寫入受限" }
        return keyVisible ? "已偵測" : "尚未確認"
    }

    private func explainUnavailableHardwareControl(_ action: String) {
        if monitor.snapshot.hardwareControlEnabled {
            hardwareControlMessage = "\(action)控制介面已就緒，但目前版本尚未綁定已驗證的寫入 helper。"
            return
        }

        if let competingController = monitor.competingController {
            hardwareControlMessage = "\(action)未執行：偵測到 \(competingController) 正在控制電池。為避免兩個控制器同時寫入 SMC，CatCleaner 維持唯讀。"
        } else {
            hardwareControlMessage = "\(action)未執行：\(monitor.snapshot.controlStatus)"
        }
    }

    private func featureToggle(
        _ title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
