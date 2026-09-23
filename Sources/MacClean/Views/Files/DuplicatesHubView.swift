import SwiftUI
import MacCleanKit

private enum DuplicatesHubMode: String, CaseIterable, Identifiable {
    case exact
    case similarPhotos

    var id: Self { self }

    var title: String {
        switch self {
        case .exact:
            L10n.tr("完全相同", "Exact Duplicates", "Точные дубликаты")
        case .similarPhotos:
            L10n.tr("相似照片", "Similar Photos", "Похожие фото")
        }
    }
}

/// Keeps destructive exact-duplicate cleanup structurally separate from
/// review-only visual similarity. The two modes never share selection state.
struct DuplicatesHubView: View {
    @State private var mode: DuplicatesHubMode = .exact

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) {
                ForEach(DuplicatesHubMode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 430)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Group {
                switch mode {
                case .exact:
                    DuplicatesView()
                case .similarPhotos:
                    SimilarPhotosView()
                }
            }
        }
    }
}
