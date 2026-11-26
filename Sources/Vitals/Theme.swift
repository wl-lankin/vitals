import AppKit
import SwiftUI
import VitalsCore

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

extension Color {
    /// A colour that follows the appearance of the view it is drawn in.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

/// One hue per vital sign, the way a patient monitor tells its traces apart.
enum Tone {
    // The light values are deliberately deep: the popover material is translucent, and over a dark
    // window it turns grey. Each of them keeps at least 4.5:1 against white and stays readable on grey.
    static let processor = Color(light: 0x06713F, dark: 0x4FE3A6)
    static let memory = Color(light: 0x1B5FCC, dark: 0x62B4FF)
    static let disks = Color(light: 0x5B36C9, dark: 0xB7A0FF)
    static let network = Color(light: 0x96590A, dark: 0xFFC253)
    static let power = Color(light: 0xC2185B, dark: 0xFF82B0)
    static let warning = Color(light: 0xC2410C, dark: 0xFFA23E)
    static let alert = Color(light: 0xC81E1E, dark: 0xFF6B62)
}

/// In light mode the popover material turns grey when a dark window lies behind it, and everything on
/// it loses contrast. A veil of white keeps the surface light whatever is underneath.
struct PanelVeil: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Rectangle()
            .fill(scheme == .dark ? Color.clear : Color.white.opacity(0.52))
            .allowsHitTesting(false)
    }
}

extension Verdict.Level {
    var color: Color {
        switch self {
        case .calm: Tone.processor
        case .busy: Tone.network
        case .strained: Tone.warning
        case .alert: Tone.alert
        }
    }
}

enum Metrics {
    static let width: CGFloat = 340
    static let inset: CGFloat = 16
    static let traceHeight: CGFloat = 34
}

extension Font {
    /// Readouts: the light rounded numerals every live value is set in.
    static func readout(_ size: CGFloat) -> Font {
        .system(size: size, weight: .light, design: .rounded)
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(.primary.opacity(0.1))
            .frame(height: 1)
            .padding(.horizontal, Metrics.inset)
    }
}

/// A glow behind the header that takes the colour of the current state.
struct Aura: View {
    let color: Color
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Rectangle()
            .fill(RadialGradient(stops: [
                .init(color: color.opacity(scheme == .dark ? 0.34 : 0.26), location: 0),
                .init(color: color.opacity(scheme == .dark ? 0.14 : 0.10), location: 0.45),
                .init(color: color.opacity(0), location: 1)
            ], center: UnitPoint(x: 0.12, y: 0), startRadius: 0, endRadius: 250))
            .frame(height: 210)
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.6), value: color)
    }
}
