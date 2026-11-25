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
    static let processor = Color(light: 0x0C9A66, dark: 0x4FE3A6)
    static let memory = Color(light: 0x2273DC, dark: 0x62B4FF)
    static let disks = Color(light: 0x7650DC, dark: 0xB7A0FF)
    static let network = Color(light: 0xC97A06, dark: 0xFFC253)
    static let power = Color(light: 0xD63A77, dark: 0xFF82B0)
    static let warning = Color(light: 0xD4700C, dark: 0xFFA23E)
    static let alert = Color(light: 0xD43535, dark: 0xFF6B62)
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
