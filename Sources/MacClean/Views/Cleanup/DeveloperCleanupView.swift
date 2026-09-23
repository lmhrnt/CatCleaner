import SwiftUI
import MacCleanKit

/// Scan-only dashboard for developer / AI-tool storage.
///
/// V1 deliberately does not expose deletion actions. The scanner classifies
/// data first so future execution adapters can be enabled one owning tool at a
/// time without turning every large path into "junk".
struct DeveloperCleanupView: View {
    @State private var candidates: [DeveloperCleanupCandidate] = []
    @State private var isScanning = false
    @State private var hasScanned = false

    private var totalSize: UInt64 {
        candidates.reduce(0) { $0 + $1.allocatedSize }
    }

    private var potentiallyCleanableSize: UInt64 {
        candidates
            .filter(\.canBecomeCleanable)
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
                    subtitle: L10n.tr("仅扫描，不会删除", "Scan only — nothing is deleted", "Только сканирование — без удаления"),
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
                    label: L10n.tr("目前可重建", "Rebuildable now", "Можно восстановить")
                )

                Button(L10n.tr("重新扫描", "Rescan", "Сканировать снова")) {
                    scan()
                }
                .buttonStyle(.borderedProminent)
                .tint(ModuleTheme.cleanup.accentColor)
                .disabled(isScanning)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)

            if isScanning {
                ProgressView()
                    .controlSize(.small)
                    .padding(.bottom, 8)
            }

            ScrollView {
                LazyVStack(spacing: 10) {
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
                "安全模式：此版本只扫描与分类。可重建缓存也必须等拥有它的 App 停止运行；恢复记录、快照、虚拟机、容器与会话不会被当成一键垃圾。",
                "Safety mode: this version only scans and classifies. Even rebuildable caches require their owning app to be inactive; recovery data, snapshots, VMs, containers, and sessions are never treated as one-click junk.",
                "Безопасный режим: эта версия только сканирует и классифицирует. Даже восстанавливаемые кэши требуют остановки приложения; данные восстановления, снимки, ВМ, контейнеры и сеансы не считаются мусором для удаления в один клик."
            ))
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
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
        guard !isScanning else { return }
        isScanning = true

        Task {
            let result = await Task.detached(priority: .userInitiated) {
                await DeveloperCleanupScanner().scan()
            }.value

            candidates = result
            hasScanned = true
            isScanning = false
        }
    }
}
