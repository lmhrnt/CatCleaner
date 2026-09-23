import SwiftUI
import MacCleanKit

/// Developer / AI-tool storage dashboard.
///
/// Discovery and execution stay separate: the scanner classifies everything,
/// while cleanup actions appear only for a stable-ID allowlist of rebuildable,
/// freshly inactive roots. Retention/stateful data remains report-only.
struct DeveloperCleanupView: View {
    @Environment(AppState.self) private var appState

    @State private var candidates: [DeveloperCleanupCandidate] = []
    @State private var selectedIDs: Set<String> = []
    @State private var isScanning = false
    @State private var isCleaning = false
    @State private var hasScanned = false
    @State private var showCleanupConfirmation = false
    @State private var lastCleanupSummary: DeveloperCleanupExecutionSummary?

    private var totalSize: UInt64 {
        candidates.reduce(0) { $0 + $1.allocatedSize }
    }

    private var potentiallyCleanableSize: UInt64 {
        candidates
            .filter {
                DeveloperCleanupExecutionPolicy.method(for: $0) != nil
            }
            .reduce(0) { $0 + $1.allocatedSize }
    }

    private var selectedSize: UInt64 {
        candidates
            .filter { selectedIDs.contains($0.id) }
            .reduce(0) { $0 + $1.allocatedSize }
    }

    var body: some View {
        Group {
            if hasScanned {
                resultsView
            } else {
                idleView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert(
            L10n.tr("确认清理", "Confirm Cleanup", "Подтвердить очистку"),
            isPresented: $showCleanupConfirmation
        ) {
            Button(L10n.tr("取消", "Cancel", "Отмена"), role: .cancel) {}
            Button(L10n.tr("清理已选", "Clean Selected", "Очистить выбранное")) {
                cleanSelected()
            }
        } message: {
            Text(L10n.tr(
                "只会处理明确列入执行白名单、且重新检查后确认没有正在使用的可重建数据。一般缓存会移到 macOS 垃圾桶（清空垃圾桶前不会真正释放空间）；CatDesk 编译缓存会使用其受限 GC 立即回收。",
                "Only explicitly allowlisted rebuildable data that is still inactive after a fresh check will be processed. General caches move to the macOS Trash (space is not reclaimed until Trash is emptied); CatDesk build caches use its bounded GC for immediate reclaim.",
                "Будут обработаны только явно разрешённые восстанавливаемые данные, которые после повторной проверки не используются. Обычные кэши перемещаются в Корзину macOS (место освободится только после её очистки); кэш сборки CatDesk очищается ограниченным GC."
            ))
        }
    }

    private var idleView: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 10) {
                Text(L10n.tr("开发者清理", "Developer Cleanup", "Очистка для разработчиков"))
                    .font(.system(size: 30, weight: .bold))

                Text(L10n.tr(
                    "识别开发工具、AI 工具与运行时占用，\n先判断能否重建与是否正在使用",
                    "Find storage used by developer and AI tools,\nthen classify rebuildability and active use before cleanup.",
                    "Находит данные инструментов разработки и ИИ,\nсначала проверяя возможность восстановления и активное использование."
                ))
                .font(.system(size: 14))
                .foregroundStyle(.primary.opacity(0.65))
                .multilineTextAlignment(.center)
            }

            if isScanning {
                ProgressView()
                    .controlSize(.large)
                Text(L10n.tr(
                    "正在读取已知工具的容量与运行状态…",
                    "Reading known tool sizes and running-state information…",
                    "Проверка размеров и состояния известных инструментов…"
                ))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            } else {
                ScanButton(
                    title: L10n.tr("扫描", "Scan", "Сканировать"),
                    subtitle: L10n.tr(
                        "先扫描再手动选择；默认不清理",
                        "Scan first, then select manually; nothing is selected by default",
                        "Сначала сканирование, затем ручной выбор; по умолчанию ничего не выбрано"
                    ),
                    theme: .cleanup
                ) {
                    scan()
                }
            }

            safetyNotice
            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private var resultsView: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("开发者清理", "Developer Cleanup", "Очистка для разработчиков"))
                        .font(.system(size: 24, weight: .bold))
                    Text(L10n.tr(
                        "已识别 \(candidates.count) 个储存区域",
                        "\(candidates.count) storage areas identified",
                        "Найдено областей хранения: \(candidates.count)"
                    ))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }

                Spacer()

                summaryMetric(
                    value: FileSizeFormatter.format(totalSize),
                    label: L10n.tr("已识别", "Identified", "Найдено")
                )
                summaryMetric(
                    value: FileSizeFormatter.format(potentiallyCleanableSize),
                    label: L10n.tr("目前可清", "Cleanable now", "Можно очистить")
                )
                summaryMetric(
                    value: FileSizeFormatter.format(selectedSize),
                    label: L10n.tr("已选择", "Selected", "Выбрано")
                )

                Button(L10n.tr("重新扫描", "Rescan", "Сканировать снова")) {
                    scan()
                }
                .buttonStyle(.bordered)
                .disabled(isScanning || isCleaning)

                Button(L10n.tr("清理已选", "Clean Selected", "Очистить выбранное")) {
                    showCleanupConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .tint(ModuleTheme.cleanup.accentColor)
                .disabled(selectedIDs.isEmpty || isScanning || isCleaning)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)

            if isScanning || isCleaning {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(isCleaning
                        ? L10n.tr("正在重新验证并清理…", "Revalidating and cleaning…", "Повторная проверка и очистка…")
                        : L10n.tr("正在扫描…", "Scanning…", "Сканирование…")
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    if let lastCleanupSummary {
                        cleanupSummaryBanner(lastCleanupSummary)
                    }

                    ForEach(candidates) { candidate in
                        candidateRow(candidate)
                    }

                    if candidates.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "checkmark.seal")
                                .font(.system(size: 34))
                            Text(L10n.tr(
                                "未发现已知的开发者储存区域",
                                "No known developer storage areas found",
                                "Известные области данных разработчика не найдены"
                            ))
                            .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 50)
                    }

                    safetyNotice
                        .padding(.top, 6)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }

    private func candidateRow(_ candidate: DeveloperCleanupCandidate) -> some View {
        HStack(spacing: 14) {
            if DeveloperCleanupExecutionPolicy.method(for: candidate) != nil {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { selectedIDs.contains(candidate.id) },
                        set: { selected in
                            if selected {
                                selectedIDs.insert(candidate.id)
                            } else {
                                selectedIDs.remove(candidate.id)
                            }
                        }
                    )
                )
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(isCleaning || isScanning)
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 16)
            }

            Image(systemName: icon(for: candidate.kind))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(statusColor(candidate))
                .frame(width: 34, height: 34)
                .background(statusColor(candidate).opacity(0.12), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(L10n.tr(candidate.titleKey))
                        .font(.system(size: 14, weight: .semibold))

                    Text(statusText(candidate))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(statusColor(candidate))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(statusColor(candidate).opacity(0.12), in: Capsule())
                }

                Text(candidate.url.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                Text(L10n.tr(candidate.policyNoteKey))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 20)

            VStack(alignment: .trailing, spacing: 4) {
                Text(FileSizeFormatter.format(candidate.allocatedSize))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))

                Text(candidate.owner)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var safetyNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "shield.lefthalf.filled")
                .foregroundStyle(ModuleTheme.cleanup.accentColor)
            Text(L10n.tr(
                "安全模式：只有明确列入执行白名单、且重新验证为未使用中的可重建资料能够手动勾选。恢复记录、快照、模型、虚拟机、容器与会话不会获得一键清理权限。",
                "Safety mode: only explicitly allowlisted rebuildable data that is freshly verified as inactive can be selected manually. Recovery data, snapshots, models, VMs, containers, and sessions never receive one-click cleanup authority.",
                "Безопасный режим: вручную можно выбрать только явно разрешённые восстанавливаемые данные, повторно подтверждённые как неиспользуемые. Данные восстановления, снимки, модели, ВМ, контейнеры и сеансы не получают права очистки в один клик."
            ))
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    private func cleanupSummaryBanner(
        _ summary: DeveloperCleanupExecutionSummary
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: summary.errors.isEmpty ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(summary.errors.isEmpty ? .green : .orange)

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.tr(
                    "上次清理：CatDesk GC 立即回收 \(FileSizeFormatter.format(summary.garbageCollectedBytes))；移到垃圾桶 \(FileSizeFormatter.format(summary.movedToTrashBytes))。",
                    "Last cleanup: CatDesk GC immediately reclaimed \(FileSizeFormatter.format(summary.garbageCollectedBytes)); \(FileSizeFormatter.format(summary.movedToTrashBytes)) moved to Trash.",
                    "Последняя очистка: GC CatDesk сразу освободил \(FileSizeFormatter.format(summary.garbageCollectedBytes)); в Корзину перемещено \(FileSizeFormatter.format(summary.movedToTrashBytes))."
                ))
                .font(.system(size: 11, weight: .medium))

                Text(L10n.tr(
                    "垃圾桶中的资料仍占用磁碟空间，需清空垃圾桶才会真正释放。阻挡：\(summary.blockedCount)；错误：\(summary.errors.count)。",
                    "Items in Trash still consume disk space until Trash is emptied. Blocked: \(summary.blockedCount); errors: \(summary.errors.count).",
                    "Данные в Корзине продолжают занимать место до её очистки. Заблокировано: \(summary.blockedCount); ошибок: \(summary.errors.count)."
                ))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

                if let firstError = summary.errors.first {
                    Text(firstError)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(11)
        .background(
            (summary.errors.isEmpty ? Color.green : Color.orange).opacity(0.07),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }

    private func summaryMetric(value: String, label: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private func statusText(_ candidate: DeveloperCleanupCandidate) -> String {
        if candidate.ownerActive {
            return L10n.tr("使用中", "In use", "Используется")
        }

        switch candidate.disposition {
        case .safeWhenInactive:
            return L10n.tr("可重建", "Rebuildable", "Восстанавливаемо")
        case .retentionReview:
            return L10n.tr("需审查", "Review required", "Требует проверки")
        case .reportOnly:
            return L10n.tr("仅报告", "Report only", "Только отчёт")
        }
    }

    private func statusColor(_ candidate: DeveloperCleanupCandidate) -> Color {
        if candidate.ownerActive { return .orange }

        switch candidate.disposition {
        case .safeWhenInactive: return .green
        case .retentionReview: return .yellow
        case .reportOnly: return .secondary
        }
    }

    private func icon(for kind: DeveloperCleanupKind) -> String {
        switch kind {
        case .rebuildableCache: "arrow.triangle.2.circlepath.circle"
        case .boundedRetention: "clock.arrow.circlepath"
        case .downloadedModel: "brain.head.profile"
        case .statefulRuntime: "externaldrive.badge.timemachine"
        }
    }

    private func scan() {
        guard !isScanning, !isCleaning else { return }
        isScanning = true

        Task {
            let result = await loadCandidates()
            applyScanResult(result)
            hasScanned = true
            isScanning = false
        }
    }

    private func cleanSelected() {
        guard !selectedIDs.isEmpty, !isScanning, !isCleaning else { return }

        let ids = selectedIDs
        isCleaning = true

        Task {
            let summary = await DeveloperCleanupExecutor().execute(
                selectedIDs: ids,
                engine: appState.cleaningEngine
            )

            lastCleanupSummary = summary
            selectedIDs.removeAll()

            let result = await loadCandidates()
            applyScanResult(result)
            hasScanned = true
            isCleaning = false
        }
    }

    private func loadCandidates() async -> [DeveloperCleanupCandidate] {
        await Task.detached(priority: .userInitiated) {
            await DeveloperCleanupScanner().scan()
        }.value
    }

    private func applyScanResult(_ result: [DeveloperCleanupCandidate]) {
        candidates = result
        let eligibleIDs = Set(
            result.compactMap {
                DeveloperCleanupExecutionPolicy.method(for: $0) == nil ? nil : $0.id
            }
        )
        selectedIDs.formIntersection(eligibleIDs)
    }
}
