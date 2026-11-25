import Foundation

/// German number and unit formatting, independent of the system locale.
public enum Fmt {
    public struct Quantity: Equatable, Sendable {
        public var number: String
        public var unit: String

        public init(number: String, unit: String) {
            self.number = number
            self.unit = unit
        }

        public var text: String { "\(number) \(unit)" }
    }

    static let locale = Locale(identifier: "de_DE")

    private static let formatters: [NumberFormatter] = (0...2).map { decimals in
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.minimumFractionDigits = decimals
        f.maximumFractionDigits = decimals
        f.roundingMode = .halfUp
        return f
    }

    public static func number(_ value: Double, decimals: Int) -> String {
        let f = formatters[min(max(decimals, 0), 2)]
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// Steps the value up through `units` and picks decimals so the result has about three digits.
    private static func scaled(_ value: Double, base: Double, units: [String], wholeUpTo: Int, trim: Bool) -> Quantity {
        var v = max(0, value)
        var i = 0
        while i < units.count - 1 {
            let decimals = i <= wholeUpTo ? 0 : (v < 99.95 ? 1 : 0)
            let shown = (v * pow(10, Double(decimals))).rounded() / pow(10, Double(decimals))
            if shown < base { break }
            v /= base
            i += 1
        }
        var decimals = i <= wholeUpTo ? 0 : (v < 99.95 ? 1 : 0)
        if trim, decimals > 0, abs(v - v.rounded()) < 0.05 { decimals = 0 }
        return Quantity(number: number(v, decimals: decimals), unit: units[i])
    }

    /// Memory sizes in binary steps, the way Activity Monitor counts.
    public static func memory(_ bytes: UInt64, trim: Bool = false) -> Quantity {
        scaled(Double(bytes) / 1024, base: 1024, units: ["KB", "MB", "GB", "TB"], wholeUpTo: 1, trim: trim)
    }

    /// Disk and transfer sizes in decimal steps, the way the Finder counts.
    public static func storage(_ bytes: UInt64, trim: Bool = true) -> Quantity {
        scaled(Double(bytes) / 1000, base: 1000, units: ["KB", "MB", "GB", "TB"], wholeUpTo: 1, trim: trim)
    }

    public static func rate(_ bytesPerSecond: Double) -> Quantity {
        scaled(bytesPerSecond / 1000, base: 1000, units: ["KB/s", "MB/s", "GB/s"], wholeUpTo: 0, trim: false)
    }

    /// "12" for 0.12; the caller adds the sign so it can style it.
    public static func percent(_ fraction: Double) -> String {
        number((fraction * 100).rounded(), decimals: 0)
    }

    public static func watts(_ watts: Double) -> Quantity {
        Quantity(number: number(watts, decimals: watts < 99.95 ? 1 : 0), unit: "W")
    }

    public static func temperature(_ celsius: Double) -> String {
        "\(number(celsius.rounded(), decimals: 0)) °C"
    }

    /// "15 Std. 8 Min.", "8 Min.", "3 T. 4 Std."
    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded()))
        if minutes < 1 { return "unter 1 Min." }
        if minutes < 60 { return "\(minutes) Min." }
        let hours = minutes / 60, rest = minutes % 60
        if hours < 24 { return rest == 0 ? "\(hours) Std." : "\(hours) Std. \(rest) Min." }
        let days = hours / 24, restHours = hours % 24
        return restHours == 0 ? "\(days) T." : "\(days) T. \(restHours) Std."
    }

    /// Distance into the past for the scrubber: "jetzt", "vor 45 Sek.", "vor 3 Min.", "vor 3 Min. 20 Sek."
    public static func ago(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded()))
        if s < 2 { return "jetzt" }
        if s < 60 { return "vor \(s) Sek." }
        let minutes = s / 60, rest = s % 60
        if minutes >= 10 || rest == 0 { return "vor \(minutes) Min." }
        return "vor \(minutes) Min. \(rest) Sek."
    }

    private static var clockFormatters: [String: DateFormatter] = [:]

    public static func clock(_ date: Date, seconds: Bool = false) -> String {
        let format = seconds ? "HH:mm:ss" : "HH:mm"
        if let f = clockFormatters[format] { return f.string(from: date) }
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = format
        clockFormatters[format] = f
        return f.string(from: date)
    }
}
