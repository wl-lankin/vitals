import Foundation

/// The state of the Mac in one phrase, with the reason behind it.
public struct Verdict: Equatable, Sendable {
    public enum Level: Int, Sendable, Comparable {
        case calm, busy, strained, alert

        public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    public var level: Level
    public var title: String
    public var detail: String

    public init(level: Level, title: String, detail: String) {
        self.level = level
        self.title = title
        self.detail = detail
    }

    /// `load` is the processor load to judge by; pass a short average so the phrase does not flicker.
    public static func assess(_ sample: Sample, load: Double? = nil) -> Verdict {
        let load = load ?? sample.cpu.total
        let topCPU = sample.processes.topCPU.first
        let topMemory = sample.processes.topMemory.first

        if sample.sensors.thermal >= .serious {
            return Verdict(level: .alert, title: "Heiß gelaufen",
                           detail: "Der Mac drosselt, um abzukühlen")
        }
        if let battery = sample.power.battery, battery.state == .battery, battery.percent <= 10 {
            let rest = battery.timeRemaining.map { ", reicht noch \(Fmt.duration($0))" } ?? ""
            return Verdict(level: .alert, title: "Akku fast leer", detail: "Noch \(battery.percent) %\(rest)")
        }
        let memoryDetail = topMemory.map { "\($0.name) belegt \(Fmt.memory($0.memory).text)" }
            ?? "\(Fmt.memory(sample.memory.used).text) von \(Fmt.memory(sample.memory.total, trim: true).text) belegt"
        if sample.memory.pressure == .critical {
            return Verdict(level: .alert, title: "Speicher am Limit", detail: memoryDetail)
        }
        if let startup = sample.disk.volumes.first, startup.total > 0,
           startup.free < 10_000_000_000 || Double(startup.free) / Double(startup.total) < 0.05 {
            return Verdict(level: .strained, title: "Startvolume fast voll",
                           detail: "Noch \(Fmt.storage(startup.free).text) frei auf \(startup.name)")
        }
        if sample.memory.pressure == .warning {
            return Verdict(level: .strained, title: "Speicher wird knapp", detail: memoryDetail)
        }
        if load >= 0.6 {
            return Verdict(level: .strained, title: "Unter Last", detail: cpuDetail(topCPU))
        }
        if load >= 0.25 {
            return Verdict(level: .busy, title: "Beschäftigt", detail: cpuDetail(topCPU))
        }
        return Verdict(level: .calm, title: "Entspannt", detail: "Alles im grünen Bereich")
    }

    private static func cpuDetail(_ app: AppUsage?) -> String {
        guard let app, app.cpu >= 0.2 else { return "Viele kleine Aufgaben zugleich" }
        let cores = Int(app.cpu.rounded())
        if cores >= 2 { return "\(app.name) lastet \(cores) Kerne aus" }
        return "Am meisten rechnet \(app.name)"
    }
}
