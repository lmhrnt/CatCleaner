import SwiftUI
import MacCleanKit

private enum LargeFileDisplayFilter: Hashable {
    case all
    case kind(LargeFileKind)
    case old
}

/// Filter chrome for Large & Old Files.
///
/// It deliberately reuses FileListView and the parent's selectedItems binding,
/// so switching categories never changes cleanup authority or selection state.
struct LargeFileCategoryResultsView: View {
    let results: [ScanResult]
    @Binding var selectedItems: Set<URL>

    @State private var filter: LargeFileDisplayFilter = .all

    private var largeItems: [FileItem] {
        uniqueItems(
            results.first(where: { $0.category == .largeFiles })?.items ?? []
        )
    }

    private var oldItems: [FileItem] {
        uniqueItems(
            results.first(where: { $0.category == .oldFiles })?.items ?? []
        )
    }

    private var groups: [(kind: LargeFileKind, items: [FileItem])] {
        LargeFileKind.grouped(largeItems)
    }

    private var displayedItems: [FileItem] {
        switch filter {
        case .all:
            return largeItems
        case .kind(let kind):
            return groups.first(where: { $0.kind == kind })?.items ?? []
        case .old:
            return oldItems
        }
    }

    private var displayedCategory: ScanCategory {
        filter == .old ? .oldFiles : .largeFiles
    }

    private var displayedResults: [ScanResult] {
        guard !displayedItems.isEmpty else { return [] }
        return [
            ScanResult(
                category: displayedCategory,
                items: displayedItems,
                autoSelect: false
            )
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            categoryBar

            if displayedItems.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                    Text(L10n.tr(
                        "这个分类目前没有项目",
                        "No items in this category",
                        "В этой категории нет объектов"
                    ))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                FileListView(
                    results: displayedResults,
                    selectedItems: $selectedItems
                )
            }
        }
    }

    private var categoryBar: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip(
                        filter: .all,
                        title: L10n.tr("全部", "All", "Все"),
                        systemImage: "square.grid.2x2",
                        count: largeItems.count,
                        size: totalSize(largeItems)
                    )

                    ForEach(groups.indices, id: \.self) { index in
                        let group = groups[index]
                        filterChip(
                            filter: .kind(group.kind),
                            title: group.kind.title,
                            systemImage: group.kind.systemImage,
                            count: group.items.count,
                            size: totalSize(group.items)
                        )
                    }

                    if !oldItems.isEmpty {
                        filterChip(
                            filter: .old,
                            title: L10n.tr("旧文件", "Old Files", "Старые файлы"),
                            systemImage: "clock.arrow.circlepath",
                            count: oldItems.count,
                            size: totalSize(oldItems)
                        )
                    }
                }
                .padding(.horizontal, 12)
            }

            HStack {
                Text(L10n.tr(
                    "大型文件与特殊数据默认不勾选；虚拟机与 iOS 备份以整包显示，不拆成内部文件。",
                    "Large files and special data are never preselected. VMs and iOS backups are shown as whole bundles, not internal files.",
                    "Большие файлы и специальные данные не выбираются заранее. ВМ и резервные копии iOS показываются целиком, без внутренних файлов."
                ))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

                Spacer()

                Text(L10n.tr(
                    "显示 \(displayedItems.count) 项 · \(FileSizeFormatter.format(totalSize(displayedItems)))",
                    "Showing \(displayedItems.count) · \(FileSizeFormatter.format(totalSize(displayedItems)))",
                    "Показано: \(displayedItems.count) · \(FileSizeFormatter.format(totalSize(displayedItems)))"
                ))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private func filterChip(
        filter chipFilter: LargeFileDisplayFilter,
        title: String,
        systemImage: String,
        count: Int,
        size: UInt64
    ) -> some View {
        let selected = filter == chipFilter

        return Button {
            filter = chipFilter
        } label: {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)

                    Text("\(count) · \(FileSizeFormatter.format(size))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(selected ? Color.primary.opacity(0.75) : Color.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                selected
                    ? Color.accentColor.opacity(0.16)
                    : Color.primary.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 9)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(
                        selected ? Color.accentColor.opacity(0.45) : Color.clear,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private func uniqueItems(_ items: [FileItem]) -> [FileItem] {
        var seen = Set<URL>()
        return items.filter { seen.insert($0.url.standardizedFileURL).inserted }
    }

    private func totalSize(_ items: [FileItem]) -> UInt64 {
        items.reduce(0) { $0 + $1.size }
    }
}
