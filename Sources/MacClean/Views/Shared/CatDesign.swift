import SwiftUI

// MARK: - Palette
//
// CatCleaner's visual identity: a cool "Russian Blue" slate canvas with a
// single warm accent taken from a cat's iris. Module hues survive only as
// small signals (sidebar icons, a faint corner glow) so the app reads as one
// product instead of a rainbow of full-screen gradients.

extension Color {
    /// 0xRRGGBB literal. Internal to CatCleaner's design tokens.
    init(catHex hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

enum CatPalette {
    /// Window canvas — cool fog in Light, deep slate in Dark.
    static let canvas = Color(light: Color(catHex: 0xECEFF2), dark: Color(catHex: 0x161A1F))
    static let canvasDeep = Color(light: Color(catHex: 0xE1E5EA), dark: Color(catHex: 0x1C2128))

    /// Cat-eye amber: the one accent. Used for primary actions and progress.
    static let amber = Color(catHex: 0xE3A33B)
    static let amberDeep = Color(catHex: 0xD08E27)
    static let irisLight = Color(catHex: 0xF6D57A)
    static let irisDeep = Color(catHex: 0xA5621A)
    static let pupil = Color(catHex: 0x14181C)

    /// Text/icon color placed ON amber (white on amber fails contrast).
    static let onAmber = Color(catHex: 0x1C2126)

    /// Row selection wash in the sidebar.
    static let selection = Color(light: Color(catHex: 0xE3A33B, opacity: 0.22),
                                 dark: Color(catHex: 0xE3A33B, opacity: 0.20))
}

// MARK: - Type scale (1.25 ratio, 13pt body)

enum CatType {
    static let display = Font.system(size: 28, weight: .semibold, design: .rounded)
    static let title = Font.system(size: 20, weight: .semibold, design: .rounded)
    static let action = Font.system(size: 16, weight: .semibold, design: .rounded)
    static let body = Font.system(size: 13)
    static let lead = Font.system(size: 14)
    static let caption = Font.system(size: 11)
    static let figure = Font.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit()
}

// MARK: - Cat eye
//
// The signature element. An amber iris with a slit pupil: nearly closed at
// rest, it dilates as a scan or clean progresses — the cat looking harder.
// When `progress` is non-nil an amber ring tracks it around the eye.

struct CatEye: View {
    /// 0 = thin slit, 1 = fully round pupil.
    var dilation: Double
    var progress: Double? = nil
    var size: CGFloat = 132

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var ringWidth: CGFloat { max(4, size * 0.05) }
    private var ringGap: CGFloat { size * 0.09 }

    var body: some View {
        let d = min(max(dilation, 0), 1)
        ZStack {
            if let progress {
                Circle()
                    .stroke(CatPalette.amber.opacity(0.18), lineWidth: ringWidth)
                Circle()
                    .trim(from: 0, to: min(max(progress, 0), 1))
                    .stroke(CatPalette.amber, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }

            eye(dilation: d)
                .frame(width: size, height: size)
        }
        .frame(width: size + (progress == nil ? 0 : 2 * (ringGap + ringWidth)),
               height: size + (progress == nil ? 0 : 2 * (ringGap + ringWidth)))
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.8), value: d)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: progress ?? 0)
        .accessibilityHidden(true)
    }

    private func eye(dilation d: Double) -> some View {
        ZStack {
            // Dark limbal rim.
            Circle().fill(CatPalette.pupil)

            // Iris.
            Circle()
                .fill(RadialGradient(
                    colors: [CatPalette.irisLight, CatPalette.amber, CatPalette.irisDeep],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.47
                ))
                .padding(size * 0.035)

            // Iris fibres: a faint angular sheen so it isn't a flat disc.
            Circle()
                .fill(AngularGradient(
                    colors: [.white.opacity(0.0), .white.opacity(0.22), .clear,
                             .black.opacity(0.10), .clear, .white.opacity(0.14), .white.opacity(0.0)],
                    center: .center
                ))
                .padding(size * 0.035)
                .blendMode(.overlay)

            // Pupil: a pointed slit that rounds out as it dilates.
            CatPupil(roundness: d)
                .fill(CatPalette.pupil)
                .frame(width: size * (0.09 + 0.50 * d),
                       height: size * (0.76 - 0.14 * d))

            // Catchlight.
            Circle()
                .fill(.white.opacity(0.85))
                .frame(width: size * 0.075, height: size * 0.075)
                .offset(x: -size * 0.14, y: -size * 0.18)
        }
        .compositingGroup()
        .shadow(color: CatPalette.irisDeep.opacity(0.30), radius: size * 0.10, y: size * 0.05)
    }
}

/// Press feedback for the eye button: a slight squint (scale) — no chrome.
struct CatEyeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Vertical cat pupil. At `roundness` 0 the ends are sharp points (a vesica);
/// at 1 it is an ellipse. Control points interpolate between the two.
struct CatPupil: Shape {
    var roundness: Double

    var animatableData: Double {
        get { roundness }
        set { roundness = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = CGFloat(min(max(roundness, 0), 1))
        let midX = rect.midX, w = rect.width / 2
        let top = CGPoint(x: midX, y: rect.minY)
        let bottom = CGPoint(x: midX, y: rect.maxY)
        // Pointed: control points sit well down the sides, so the curve
        // leaves each tip steeply. Round: controls level with the tips, the
        // classic two-cubic ellipse, so the ends flatten out.
        let reach = rect.height * 0.34 * (1 - r)
        var p = Path()
        p.move(to: top)
        p.addCurve(to: bottom,
                   control1: CGPoint(x: midX + w * 1.33, y: rect.minY + reach),
                   control2: CGPoint(x: midX + w * 1.33, y: rect.maxY - reach))
        p.addCurve(to: top,
                   control1: CGPoint(x: midX - w * 1.33, y: rect.maxY - reach),
                   control2: CGPoint(x: midX - w * 1.33, y: rect.minY + reach))
        p.closeSubpath()
        return p
    }
}
