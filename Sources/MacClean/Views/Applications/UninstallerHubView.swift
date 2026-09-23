import SwiftUI
import MacCleanKit

private enum UninstallerHubMode: String, CaseIterable, Identifiable {
    case installedApps
    case removedAppLeftovers

    var id: Self { self }

    var title: String {
        switch self {
        case .installedApps:
            L10n.tr("已安装 App", "Installed Apps", "Установленные приложения")
        case .removedAppLeftovers:
            L10n.tr("已移除 App 残留", "Removed App Leftovers", "Остатки удалённых приложений")
        }
    }
}

/// Keeps installed-app uninstall/reset operations separate from orphan cleanup.
/// The two pages never share selection state.
struct UninstallerHubView: View {
    @State private var mode: UninstallerHubMode = .installedApps

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) {
                ForEach(UninstallerHubMode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 470)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Group {
                switch mode {
                case .installedApps:
                    UninstallerView()
                case .removedAppLeftovers:
                    RemovedAppLeftoversView()
                }
            }
        }
    }
}
