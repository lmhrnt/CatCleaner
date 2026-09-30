import SwiftUI
import AppKit

extension Color {
    /// A color that resolves to `light` or `dark` based on the active
    /// appearance, so the same value renders correctly in both Light and Dark
    /// without threading `colorScheme` through every view.
    init(light: Color, dark: Color) {
        self = Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(dark) : NSColor(light)
        })
    }
}

/// Neutral background used when "Remove background colors" is enabled in
/// Settings, replacing per-module themed gradients. Light-grey in Light mode,
/// near-black in Dark.
private let neutralGradient = LinearGradient(
    colors: [
        Color(light: Color(red: 0.95, green: 0.95, blue: 0.96), dark: Color(red: 0.12, green: 0.12, blue: 0.14)),
        Color(light: Color(red: 0.92, green: 0.92, blue: 0.94), dark: Color(red: 0.16, green: 0.16, blue: 0.18)),
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

public enum ModuleTheme {
    case smartScan
    case cleanup
    case protection
    case performance
    case applications
    case files
    case settings

    public var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    public var buttonGradient: LinearGradient {
        LinearGradient(colors: buttonColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Window canvas. Every module now shares the same slate canvas; module
    /// identity comes from `accentColor` (a faint corner glow + sidebar icon)
    /// rather than a full-screen gradient, so the app reads as one product.
    public var colors: [Color] {
        [CatPalette.canvas, CatPalette.canvas, CatPalette.canvasDeep]
    }

    /// Primary actions use the single cat-eye amber accent in every module.
    /// Labels on it are dark ink (see `CatPalette.onAmber`), not white.
    public var buttonColors: [Color] {
        [Color(catHex: 0xE9AE4A), CatPalette.amberDeep]
    }

    /// Module hue — muted, similar lightness across modules so no one
    /// section shouts. Legible on both the Light and Dark sidebar.
    public var accentColor: Color {
        switch self {
        case .smartScan: Color(catHex: 0xD4952C)
        case .cleanup: Color(catHex: 0x4F9A72)
        case .protection: Color(catHex: 0xC4574A)
        case .performance: Color(catHex: 0x5B7FC4)
        case .applications: Color(catHex: 0x8A6BBE)
        case .files: Color(catHex: 0x3E949A)
        case .settings: Color(catHex: 0x7B8591)
        }
    }
}

public struct GradientBackgroundView: View {
    let theme: ModuleTheme
    @AppStorage("removeBackgroundColors") private var removeBackgroundColors = false

    public init(theme: ModuleTheme) {
        self.theme = theme
    }

    public var body: some View {
        if removeBackgroundColors {
            neutralGradient
        } else {
            ZStack {
                theme.gradient
                // A faint glow of the module hue from the top-trailing corner:
                // enough to tell sections apart, never enough to tint text.
                RadialGradient(
                    colors: [theme.accentColor.opacity(0.12), theme.accentColor.opacity(0)],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 560
                )
            }
        }
    }
}
