import SwiftUI
import MacCleanKit

/// The module "Scan" control. At rest it is CatCleaner's cat eye — a slit
/// pupil that opens slightly on hover — with the action named underneath.
/// While scanning, the pupil dilates with progress and a ring tracks it.
public struct ScanButton: View {
    let title: String
    let subtitle: String?
    let theme: ModuleTheme
    let isScanning: Bool
    let progress: Double
    let action: () -> Void

    @State private var isHovering = false

    public init(
        title: String = L10n.tr("扫描", "Scan", "Сканировать"),
        subtitle: String? = nil,
        theme: ModuleTheme = .smartScan,
        isScanning: Bool = false,
        progress: Double = 0,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.theme = theme
        self.isScanning = isScanning
        self.progress = progress
        self.action = action
    }

    public var body: some View {
        if isScanning {
            scanningContent
        } else {
            Button(action: action) {
                idleContent
            }
            .buttonStyle(CatEyeButtonStyle())
            .onHover { isHovering = $0 }
            .accessibilityLabel(subtitle.map { "\(title), \($0)" } ?? title)
        }
    }

    private var idleContent: some View {
        VStack(spacing: 14) {
            CatEye(dilation: isHovering ? 0.32 : 0.06, size: 132)

            VStack(spacing: 3) {
                Text(title)
                    .font(CatType.action)
                    .foregroundStyle(CatPalette.onAmber)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(theme.buttonGradient))
                if let subtitle {
                    Text(subtitle)
                        .font(CatType.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
        }
        .contentShape(Rectangle())
    }

    private var scanningContent: some View {
        VStack(spacing: 12) {
            CatEye(dilation: progress, progress: progress, size: 96)
            Text("\(Int(progress * 100))%")
                .font(CatType.figure)
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
        }
    }
}

public struct ScanProgressRing: View {
    let progress: Double
    let phase: String
    let detail: String?
    let theme: ModuleTheme

    public init(progress: Double, phase: String, detail: String? = nil, theme: ModuleTheme = .smartScan) {
        self.progress = progress
        self.phase = phase
        self.detail = detail
        self.theme = theme
    }

    public var body: some View {
        VStack(spacing: 18) {
            CatEye(dilation: 0.1 + 0.9 * progress, progress: progress, size: 104)

            VStack(spacing: 6) {
                // Some callers already put the percentage in `phase`
                // ("Cleaning… 42%"); don't print it twice.
                if !phase.contains("%") {
                    Text("\(Int(progress * 100))%")
                        .font(CatType.figure)
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                }

                Text(phase)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .contentTransition(.interpolate)
                    .animation(.easeInOut(duration: 0.2), value: phase)

                if let detail {
                    Text(detail)
                        .font(CatType.body)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(Int(progress * 100))%")
    }
}
