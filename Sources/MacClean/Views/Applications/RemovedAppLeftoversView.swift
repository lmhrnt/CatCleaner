import SwiftUI
import AppKit
import MacCleanKit

struct RemovedAppLeftoversView: View {
    @Environment(AppState.self) private var appState

    @State private var items: [FileItem] = []
    @State private var selectedItems: Set<URL> = []
    @State private var isScanning = false
    @State private var isCleaning = false
    @State private var hasScanned = false
    @State private var showCleanConfirmation = false
    @State private var lastCleanupMessage: String?

    private var totalSize: UInt64 {
        items.reduce(0) { $0 + $1.size }
    }

    private var selectedSize: UInt64 {
        items
            .filter { selectedItems.contains($0.url) }
            .reduce(0) { $0 + $1.size }
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
            L10n.tr(
                "将选中的残留移到垃圾桶？",
                "Move selected leftovers to Trash?",
                "Переместить выбранные остатки в Корзину?"
            ),
            isPresented: $showCleanConfirmation
        ) {
            Button(L10n.tr("取消", "Cancel", "Отмена"), role: .cancel) {}
            Button(
                L10n.tr("移到垃圾桶", "Move to Trash", "Переместить в Корзину"),
                role: .destructive
            ) {
                cleanSelected()
            }
        } message: {
            Text(L10n.tr(
                "将移动 \(selectedItems.count) 项（\(FileSizeFormatter.format(selectedSize))）。这些项目来自安全的 Library 缓存/日志/Web 数据目录，并通过已安装 App bundle ID 交叉检查；仍建议逐项确认。操作可从垃圾桶恢复。",
                "\(selectedItems.count) items (\(FileSizeFormatter.format(selectedSize))) will be moved. They come only from safe Library cache/log/web-data roots and were cross-checked against installed app bundle IDs; review each item anyway. You can restore them from Trash.",
                "Будет перемещено объектов: \(selectedItems.count) (\(FileSizeFormatter.format(selectedSize))). Они найдены только в безопасных каталогах кэша/журналов/web-данных Library и сверены с bundle ID установленных приложений; всё равно проверьте каждый объект. Их можно восстановить из Корзины."
            ))
        }
    }

    private var idleView: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 9) {
                Text(L10n.tr(
                    "已移除 App 残留",
                    "Removed App Leftovers",
                    "Остатки удалённых приложений"
                ))
                .font(.system(size: 28, weight: .bold))

                Text(L10n.tr(
                    "寻找已卸载 App 留下的安全可审查资料\n默认不会勾选或删除任何项目",
                    "Find reviewable data left behind by uninstalled apps.\nNothing is selected or removed by default.",
                    "Поиск данных, оставшихся после удалённых приложений.\nПо умолчанию ничего не выбирается и не удаляется."
                ))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }

            ScanButton(
                title: L10n.tr("扫描", "Scan", "Сканировать"),
                subtitle: L10n.tr(
                    "仅检查安全的 Library 残留位置",
                    "Only safe Library leftover locations",
                    "Только безопасные расположения Library"
                ),
                theme: .applications,
                action: scan
            )

            safetyNotice
                .frame(maxWidth: 700)

            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private var resultsView: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr(
                        "已移除 App 残留",
                        "Removed App Leftovers",
                        "Остатки удалённых приложений"
                    ))
                    .font(.system(size: 23, weight: .bold))

                    Text(L10n.tr(
                        "找到 \(items.count) 个候选；默认全部不勾选",
                        "\(items.count) candidates found; none selected by default",
                        "Найдено кандидатов: \(items.count); по умолчанию ничего не выбрано"
                    ))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }

                Spacer()

                metric(
                    value: FileSizeFormatter.format(totalSize),
                    label: L10n.tr("候选总计", "Candidates", "Кандидаты")
                )
                metric(
                    value: FileSizeFormatter.format(selectedSize),
                    label: L10n.tr("已选择", "Selected", "Выбрано")
                )

                Button(L10n.tr("重新扫描", "Rescan", "Сканировать снова")) {
                    scan()
                }
                .buttonStyle(.bordered)
                .disabled(isScanning || isCleaning)

                Button(L10n.tr("清理已选", "Clean Selected", "Очистить выбранное")) {
                    showCleanConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(selectedItems.isEmpty || isScanning || isCleaning)
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 10)

            if isScanning || isCleaning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(isCleaning
                        ? L10n.tr("正在移动到垃圾桶…", "Moving to Trash…", "Перемещение в Корзину…")
                        : L10n.tr("正在交叉检查已安装 App…", "Cross-checking installed apps…", "Сверка с установленными приложениями…")
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)
            }

            Divider().opacity(0.3)

            ScrollView {
                LazyVStack(spacing: 10) {
                    if let lastCleanupMessage {
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundStyle(.green)
                            Text(lastCleanupMessage)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(11)
                        .background(.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                    }

                    safetyNotice

                    ForEach(items) { item in
                        leftoverRow(item)
                    }

                    if items.isEmpty && !isScanning {
                        VStack(spacing: 10) {
                            Image(systemName: "checkmark.seal")
                                .font(.system(size: 34))
                                .foregroundStyle(.secondary)
                            Text(L10n.tr(
                                "没有发现可安全判定的已移除 App 残留",
                                "No safely identifiable removed-app leftovers found",
                                "Безопасно определяемых остатков удалённых приложений не найдено"
                            ))
                            .font(.system(size: 13, weight: .medium))
                        }
                        .padding(.vertical, 46)
                    }
                }
                .padding(20)
            }
        }
    }

    private func leftoverRow(_ item: FileItem) -> some View {
        HStack(spacing: 12) {
            Toggle(
                "",
                isOn: Binding(
                    get: { selectedItems.contains(item.url) },
                    set: { selected in
                        if selected {
                            selectedItems.insert(item.url)
                        } else {
                            selectedItems.remove(item.url)
                        }
                    }
                )
            )
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(isScanning || isCleaning)

            Image(systemName: item.isDirectory ? "folder.badge.minus" : "doc.badge.minus")
                .font(.system(size: 17))
                .foregroundStyle(.orange)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(item.url.deletingLastPathComponent().path(percentEncoded: false))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 16)

            Text(item.formattedSize)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .contextMenu {
            Button(L10n.tr("在 Finder 中显示", "Reveal in Finder", "Показать в Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
        }
    }

    private var safetyNotice: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "shield.lefthalf.filled")
                .foregroundStyle(.orange)

            Text(L10n.tr(
                "只扫描 Caches、Logs、HTTPStorages、Saved Application State 与 WebKit 顶层项目；不会把 Preferences、Containers、Group Containers 或 Keychain 当成孤立残留。只有格式可信的 reverse-DNS bundle ID、没有已安装 App 同 lineage，且没有仍在使用相同 vendor namespace 时才列出。",
                "Only top-level entries in Caches, Logs, HTTPStorages, Saved Application State, and WebKit are scanned. Preferences, Containers, Group Containers, and Keychain data are not treated as orphan leftovers. A candidate must look like a real reverse-DNS bundle ID, have no installed app in the same lineage, and have no installed app still using the same vendor namespace.",
                "Сканируются только верхние уровни Caches, Logs, HTTPStorages, Saved Application State и WebKit. Preferences, Containers, Group Containers и Keychain не считаются остатками. Кандидат должен выглядеть как настоящий reverse-DNS bundle ID, не иметь установленного приложения той же линии и не использовать namespace поставщика, который всё ещё нужен установленным приложениям."
            ))
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(11)
        .background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    private func metric(value: String, label: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    private func scan() {
        guard !isScanning, !isCleaning else { return }
        isScanning = true

        Task {
            let result = await Task.detached(priority: .userInitiated) {
                AppLeftoversScanner.scan()
            }.value

            items = result.filter { CleanFilter.isActionable($0.url) }
            selectedItems.formIntersection(Set(items.map(\.url)))
            hasScanned = true
            isScanning = false
        }
    }

    private func cleanSelected() {
        guard !selectedItems.isEmpty, !isScanning, !isCleaning else { return }

        let selection = selectedItems
        let snapshot = items
        isCleaning = true

        Task {
            let result = await CleanActions.executeUserClean(
                items: snapshot,
                selectedItems: selection,
                engine: appState.cleaningEngine
            )

            selectedItems.removeAll()
            lastCleanupMessage = L10n.tr(
                "已移动 \(result.removedCount) 项（\(FileSizeFormatter.format(result.freedBytes))）到垃圾桶；阻挡/略过 \(result.skippedCount) 项，错误 \(result.errors.count) 项。清空垃圾桶后才会真正释放空间。",
                "Moved \(result.removedCount) items (\(FileSizeFormatter.format(result.freedBytes))) to Trash; \(result.skippedCount) blocked/skipped and \(result.errors.count) errors. Disk space is reclaimed only after Trash is emptied.",
                "В Корзину перемещено объектов: \(result.removedCount) (\(FileSizeFormatter.format(result.freedBytes))); заблокировано/пропущено: \(result.skippedCount), ошибок: \(result.errors.count). Место освободится только после очистки Корзины."
            )

            let rescanned = await Task.detached(priority: .userInitiated) {
                AppLeftoversScanner.scan()
            }.value

            items = rescanned.filter { CleanFilter.isActionable($0.url) }
            isCleaning = false
        }
    }
}
