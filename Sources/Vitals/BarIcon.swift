import AppKit
import VitalsCore

enum BarStyle: String, CaseIterable, Identifiable {
    case icon, processor, memory, network, power

    var id: String { rawValue }

    var label: String {
        switch self {
        case .icon: "Nur Symbol"
        case .processor: "Symbol und Prozessor"
        case .memory: "Symbol und Speicher"
        case .network: "Symbol und Netzwerk"
        case .power: "Symbol und Verbrauch"
        }
    }
}

/// What the menu bar shows. Equatable so the status item is only touched when something changes.
struct BarLabel: Equatable {
    /// 0...5, how hard the pulse in the icon beats.
    var level: Int
    var text: String?

    static func make(sample: Sample, load: Double) -> BarLabel {
        let level: Int = switch load {
        case ..<0.08: 0
        case ..<0.2: 1
        case ..<0.35: 2
        case ..<0.55: 3
        case ..<0.75: 4
        default: 5
        }
        let style = BarStyle(rawValue: UserDefaults.standard.string(forKey: "barStyle") ?? "") ?? .icon
        let text: String? = switch style {
        case .icon: nil
        case .processor: "\(padded(Fmt.percent(load), to: 2)) %"
        case .memory: "\(padded(Fmt.percent(sample.memory.usedFraction), to: 2)) %"
        case .network: "↓ \(Fmt.rate(sample.network.downRate).text)"
        case .power: sample.power.systemWatts.map { Fmt.watts($0).text }
        }
        return BarLabel(level: level, text: text)
    }

    /// Pads with figure spaces so the item keeps its width while the digits change.
    private static func padded(_ digits: String, to count: Int) -> String {
        String(repeating: "\u{2007}", count: max(0, count - digits.count)) + digits
    }
}

/// Menu bar glyph: a rounded tile with a heartbeat punched out, so it tints like a system icon.
/// The beat grows with the processor load.
enum BarIcon {
    private static var cache: [Int: NSImage] = [:]

    static func image(level: Int) -> NSImage {
        if let cached = cache[level] { return cached }
        let image = NSImage(size: NSSize(width: 19, height: 16), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let tile = NSRect(x: 1, y: 0.5, width: 17, height: 15)
            NSColor.black.setFill()
            NSBezierPath(roundedRect: tile, xRadius: 4.2, yRadius: 4.2).fill()

            ctx.setBlendMode(.destinationOut)
            let mid = tile.midY
            let amplitude = 1.6 + CGFloat(level) * 0.85
            let left = tile.minX + 2.6
            let beat = NSBezierPath()
            beat.move(to: NSPoint(x: left, y: mid))
            beat.line(to: NSPoint(x: left + 3.1, y: mid))
            beat.line(to: NSPoint(x: left + 4.7, y: mid + amplitude))
            beat.line(to: NSPoint(x: left + 6.9, y: mid - amplitude * 0.8))
            beat.line(to: NSPoint(x: left + 8.4, y: mid))
            beat.line(to: NSPoint(x: left + 11.8, y: mid))
            beat.lineWidth = 1.5
            beat.lineCapStyle = .round
            beat.lineJoinStyle = .round
            NSColor.black.setStroke()
            beat.stroke()
            return true
        }
        image.isTemplate = true
        cache[level] = image
        return image
    }
}
