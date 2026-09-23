import SwiftUI
import AppKit
import MacCleanKit

private enum SimilarPhotoReviewLevel: String, CaseIterable, Identifiable {
    case strict
    case balanced
    case broad

    var id: Self { self }

    var maximumDistance: Float {
        switch self {
        case .strict: 0.20
        case .balanced: 0.30
        case .broad: 0.42
        }
    }

    var title: String {
        switch self {
        case .strict:
            L10n.tr("严格", "Strict", "Строго")
        case .balanced:
            L10n.tr("平衡", "Balanced", "Баланс")
        case .broad:
            L10n.tr("宽松", "Broad", "Широко")
        }
    }
}

struct SimilarPhotosView: View {
    @State private var report: SimilarPhotoScanReport?
    @State private var reviewLevel: SimilarPhotoReviewLevel = .balanced
    @State private var isScanning = false
    @State private var scanTask: Task<Void, Never>?
    @State private var elapsedSeconds = 0
    @State private var timerTask: Task<Void, Never>?

    private var clusters: [SimilarPhotoCluster] {
        report?.clusters(maximumDistance: reviewLevel.maximumDistance) ?? []
    }

    var body: some View {
        Group {
            if isScanning {
                scanningView
            } else if let report {
                resultsView(report)
            } else {
                idleView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var idleView: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 10) {
                Text(L10n.tr("相似照片", "Similar Photos", "Похожие фото"))
                    .font(.system(size: 30, weight: .bold))

                Text(L10n.tr(
                    "使用 Apple Vision 特征向量寻找视觉上相似的照片\n结果仅供人工比较，不会自动删除",
                    "Use Apple Vision feature prints to find visually similar photos.\nResults are for manual review only and are never auto-deleted.",
                    "Поиск визуально похожих фото с помощью Apple Vision.\nРезультаты только для просмотра и никогда не удаляются автоматически."
                ))
                .font(.system(size: 14))
                .foregroundStyle(.primary.opacity(0.65))
                .multilineTextAlignment(.center)
            }

            reviewOnlyNotice

            ScanButton(
                title: L10n.tr("扫描", "Scan", "Сканировать"),
                subtitle: L10n.tr(
                    "图片、桌面与下载项目",
                    "Pictures, Desktop & Downloads",
                    "Изображения, Рабочий стол и Загрузки"
                ),
                theme: .files,
                action: scan
            )

            Text(L10n.tr(
                "最多分析 2,000 张照片；会先用尺寸与比例缩小候选，再进行视觉比较。",
                "Up to 2,000 photos are analyzed. Metadata narrows the candidate set before visual comparison.",
                "Анализируется до 2 000 фото. Сначала кандидаты сокращаются по метаданным, затем выполняется визуальное сравнение."
            ))
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private var scanningView: some View {
        VStack(spacing: 22) {
            Spacer()

            ProgressView()
                .controlSize(.large)
                .scaleEffect(1.35)

            Text(L10n.tr(
                "正在建立照片特征并比较相似度…",
                "Building image features and comparing similarity…",
                "Создание признаков изображений и сравнение сходства…"
            ))
            .font(.system(size: 15, weight: .semibold))

            Text(L10n.tr(
                "已用时：\(formatElapsed(elapsedSeconds))",
                "Elapsed: \(formatElapsed(elapsedSeconds))",
                "Прошло: \(formatElapsed(elapsedSeconds))"
            ))
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(.secondary)

            reviewOnlyNotice
                .frame(maxWidth: 620)

            Button(L10n.tr("取消", "Cancel", "Отмена")) {
                cancelScan()
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private func resultsView(_ report: SimilarPhotoScanReport) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("相似照片", "Similar Photos", "Похожие фото"))
                        .font(.system(size: 24, weight: .bold))
                    Text(L10n.tr(
                        "找到 \(clusters.count) 组建议人工比较",
                        "\(clusters.count) groups suggested for manual review",
                        "Групп для ручной проверки: \(clusters.count)"
                    ))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }

                Spacer()

                statistic(
                    value: "\(report.candidateCount)",
                    label: L10n.tr("候选照片", "Candidates", "Кандидаты")
                )
                statistic(
                    value: "\(report.comparedPairCount)",
                    label: L10n.tr("已比较", "Compared", "Сравнено")
                )
                if report.featureFailureCount > 0 {
                    statistic(
                        value: "\(report.featureFailureCount)",
                        label: L10n.tr("无法读取", "Unreadable", "Ошибки")
                    )
                }

                Button(L10n.tr("重新扫描", "Rescan", "Сканировать снова")) {
                    scan()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 10)

            HStack(spacing: 12) {
                Text(L10n.tr("相似度范围", "Similarity range", "Диапазон сходства"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Picker("", selection: $reviewLevel) {
                    ForEach(SimilarPhotoReviewLevel.allCases) { level in
                        Text("\(level.title)  ≤ \(String(format: "%.2f", level.maximumDistance))")
                            .tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 420)

                Spacer()

                Text(L10n.tr(
                    "距离越小代表越相似；门槛是 CatCleaner 的审查设定，不是 Apple 的删除标准。",
                    "Lower distance means more similar. These are CatCleaner review thresholds, not Apple deletion rules.",
                    "Меньшая дистанция означает большее сходство. Это пороги CatCleaner для просмотра, а не правила удаления Apple."
                ))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 360)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 10)

            Divider().opacity(0.3)

            ScrollView {
                LazyVStack(spacing: 16) {
                    reviewOnlyNotice

                    if report.truncatedCandidateCount > 0 {
                        infoBanner(
                            systemImage: "exclamationmark.triangle",
                            text: L10n.tr(
                                "照片数量超过本次上限，另有 \(report.truncatedCandidateCount) 张未分析。",
                                "\(report.truncatedCandidateCount) additional photos were not analyzed because the scan limit was reached.",
                                "Ещё \(report.truncatedCandidateCount) фото не проанализированы из-за ограничения сканирования."
                            )
                        )
                    }

                    if clusters.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "photo.stack")
                                .font(.system(size: 34))
                                .foregroundStyle(.secondary)
                            Text(L10n.tr(
                                "目前门槛下没有相似照片群组",
                                "No similar-photo groups at this threshold",
                                "При этом пороге похожие группы не найдены"
                            ))
                            .font(.system(size: 14, weight: .medium))
                            Text(L10n.tr(
                                "可以切换到“宽松”查看更多候选；仍需由你自行判断是否保留。",
                                "Try Broad to review more candidates; you still decide what to keep.",
                                "Переключитесь на широкий режим для большего числа кандидатов; решение о сохранении остаётся за вами."
                            ))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 50)
                    } else {
                        ForEach(Array(clusters.enumerated()), id: \.element.id) { index, cluster in
                            clusterCard(cluster, index: index + 1)
                        }
                    }
                }
                .padding(20)
            }
        }
    }

    private func clusterCard(_ cluster: SimilarPhotoCluster, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.tr(
                        "群组 \(index) · \(cluster.count) 张",
                        "Group \(index) · \(cluster.count) photos",
                        "Группа \(index) · фото: \(cluster.count)"
                    ))
                    .font(.system(size: 14, weight: .semibold))

                    Text(L10n.tr(
                        "最远 Vision 距离 \(String(format: "%.3f", cluster.farthestDistance))",
                        "Farthest Vision distance \(String(format: "%.3f", cluster.farthestDistance))",
                        "Макс. дистанция Vision \(String(format: "%.3f", cluster.farthestDistance))"
                    ))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Text(L10n.tr("仅供审查", "REVIEW ONLY", "ТОЛЬКО ПРОСМОТР"))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.orange.opacity(0.12), in: Capsule())
            }

            ScrollView(.horizontal, showsIndicators: true) {
                LazyHStack(spacing: 12) {
                    SimilarPhotoCard(
                        asset: cluster.anchor,
                        badge: L10n.tr("基准", "ANCHOR", "ОПОРА"),
                        distance: nil
                    )

                    ForEach(cluster.members, id: \.asset.url) { member in
                        SimilarPhotoCard(
                            asset: member.asset,
                            badge: L10n.tr("相似", "SIMILAR", "ПОХОЖЕ"),
                            distance: member.distanceToAnchor
                        )
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .padding(14)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
    }

    private var reviewOnlyNotice: some View {
        infoBanner(
            systemImage: "eye.fill",
            text: L10n.tr(
                "相似照片不是重复文件。此功能不会预选、删除、移动到垃圾桶或进行 APFS 合并；请逐组人工确认。",
                "Similar photos are not duplicates. This feature never preselects, deletes, trashes, or APFS-consolidates files; review each group manually.",
                "Похожие фото не являются дубликатами. Функция ничего не выбирает, не удаляет, не перемещает в Корзину и не объединяет через APFS — проверяйте группы вручную."
            )
        )
    }

    private func infoBanner(systemImage: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: systemImage)
                .foregroundStyle(.orange)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    private func statistic(value: String, label: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    private func scan() {
        guard !isScanning else { return }

        isScanning = true
        elapsedSeconds = 0
        scanTask?.cancel()
        timerTask?.cancel()

        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                elapsedSeconds += 1
            }
        }

        scanTask = Task {
            let result = await SimilarPhotosModule().scan()
            if Task.isCancelled { return }

            timerTask?.cancel()
            timerTask = nil
            report = result
            isScanning = false
            scanTask = nil
        }
    }

    private func cancelScan() {
        scanTask?.cancel()
        timerTask?.cancel()
        scanTask = nil
        timerTask = nil
        isScanning = false
        elapsedSeconds = 0
    }

    private func formatElapsed(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct SimilarPhotoCard: View {
    let asset: SimilarPhotoAsset
    let badge: String
    let distance: Float?

    private let cardWidth: CGFloat = 196

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SimilarPhotoThumbnail(url: asset.url)
                .frame(width: cardWidth, height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 9))

            HStack(spacing: 6) {
                Text(badge)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(distance == nil ? Color.blue : Color.secondary)

                if let distance {
                    Text("d=\(String(format: "%.3f", distance))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Text(asset.url.lastPathComponent)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)

            Text("\(asset.pixelWidth)×\(asset.pixelHeight) · \(ByteCountFormatter.string(fromByteCount: Int64(asset.fileSize), countStyle: .file))")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            Text(asset.url.deletingLastPathComponent().path(percentEncoded: false))
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .frame(width: cardWidth, alignment: .leading)
        .padding(10)
        .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 11))
        .contextMenu {
            Button(L10n.tr("在 Finder 中显示", "Reveal in Finder", "Показать в Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([asset.url])
            }
            Button(L10n.tr("打开", "Open", "Открыть")) {
                NSWorkspace.shared.open(asset.url)
            }
        }
    }
}

/// Lazy cards mean this synchronous preview load happens only for visible
/// review items, not for every candidate found by the scanner.
private struct SimilarPhotoThumbnail: View {
    let url: URL

    var body: some View {
        Group {
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.primary.opacity(0.06)
                    Image(systemName: "photo")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .clipped()
    }
}
