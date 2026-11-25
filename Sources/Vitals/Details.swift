import AppKit
import SwiftUI
import VitalsCore

struct Fact: Identifiable {
    let label: String
    let value: String
    var tone: Color? = nil
    var help: String? = nil
    var copies: String? = nil

    var id: String { label }
}

/// Label and value pairs in two columns.
struct FactGrid: View {
    let facts: [Fact]
    @State private var copied: String?

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible())], spacing: 6) {
            ForEach(facts) { fact in
                HStack(spacing: 6) {
                    if let tone = fact.tone {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(tone)
                            .frame(width: 8, height: 8)
                    }
                    Text(fact.label)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(copied == fact.label ? "Kopiert" : fact.value)
                        .fontWeight(.medium)
                        .monospacedDigit()
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                .font(.system(size: 11.5))
                .contentShape(Rectangle())
                .onTapGesture {
                    guard let text = fact.copies else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = fact.label
                    Task {
                        try? await Task.sleep(for: .seconds(1.2))
                        if copied == fact.label { copied = nil }
                    }
                }
                .help(fact.help ?? (fact.copies == nil ? "" : "Klicken zum Kopieren"))
            }
        }
    }
}

/// Small caption above a block inside the details.
struct DetailCaption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Apps

@MainActor
enum IconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(for app: AppUsage) -> NSImage? {
        guard let path = app.bundlePath else { return nil }
        if let cached = cache[path] { return cached }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 32, height: 32)
        cache[path] = image
        return image
    }
}

/// The apps that weigh the most, helpers folded into their app.
struct AppList: View {
    enum Measure {
        case cpu, memory
    }

    let apps: [AppUsage]
    let measure: Measure
    let tone: Color

    var body: some View {
        let peak = apps.map(amount).max() ?? 0
        VStack(spacing: 3) {
            if apps.isEmpty {
                Text("Die Liste füllt sich in ein paar Sekunden")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 20)
            }
            ForEach(apps) { app in
                HStack(spacing: 8) {
                    Group {
                        if let icon = IconCache.icon(for: app) {
                            Image(nsImage: icon).resizable().interpolation(.high)
                        } else {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .frame(width: 16, height: 16)
                                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.primary.opacity(0.1)))
                        }
                    }
                    .frame(width: 16, height: 16)
                    Text(app.name)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    if app.processCount > 1 {
                        Text("\(app.processCount)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                            .help("\(app.processCount) Prozesse gehören zu \(app.name)")
                    }
                    Spacer(minLength: 6)
                    Capsule()
                        .fill(tone.opacity(0.75))
                        .frame(width: max(2, 54 * (peak > 0 ? amount(app) / peak : 0)), height: 3)
                        .frame(width: 54, alignment: .trailing)
                    Text(text(app))
                        .font(.system(size: 11.5, weight: .medium))
                        .monospacedDigit()
                        .frame(width: 58, alignment: .trailing)
                }
                .frame(height: 20)
            }
        }
    }

    private func amount(_ app: AppUsage) -> Double {
        measure == .cpu ? app.cpu : Double(app.memory)
    }

    private func text(_ app: AppUsage) -> String {
        measure == .cpu ? "\(Fmt.percent(app.cpu)) %" : Fmt.memory(app.memory).text
    }
}

// MARK: Processor

struct ProcessorDetail: View {
    let sample: Sample
    let topology: CPUTopology

    var body: some View {
        let groups = CoreGroup.split(cores: sample.cpu.cores, kinds: topology.kinds)
        VStack(spacing: 12) {
            GeometryReader { geo in
                let count = groups.reduce(0) { $0 + $1.loads.count }
                let gaps = CGFloat(max(0, groups.count - 1)) * 14 + CGFloat(max(0, count - groups.count)) * 3
                let cell = max(4, (geo.size.width - gaps) / CGFloat(max(1, count)))
                HStack(alignment: .top, spacing: 14) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 3) {
                                ForEach(Array(group.loads.enumerated()), id: \.offset) { _, load in
                                    CoreCell(load: load, width: cell, height: 30, radius: 3)
                                }
                            }
                            Text("\(group.loads.count) × \(group.name)")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.secondary)
                                .fixedSize()
                        }
                    }
                }
            }
            .frame(height: 49)
            FactGrid(facts: facts)
            VStack(spacing: 5) {
                DetailCaption(text: "Am meisten rechnen")
                AppList(apps: sample.processes.topCPU, measure: .cpu, tone: Tone.processor)
            }
        }
    }

    private var facts: [Fact] {
        var facts = [
            Fact(label: "Benutzer", value: "\(Fmt.percent(sample.cpu.user)) %"),
            Fact(label: "System", value: "\(Fmt.percent(sample.cpu.system)) %")
        ]
        if let gpu = sample.sensors.gpuUsage {
            facts.append(Fact(label: "Grafik", value: "\(Fmt.percent(gpu)) %"))
        }
        if let temperature = sample.sensors.cpuTemperature {
            facts.append(Fact(label: "Temperatur", value: Fmt.temperature(temperature),
                              tone: sample.sensors.thermal >= .serious ? Tone.alert : nil))
        }
        facts.append(Fact(label: "Last", value: Fmt.number(sample.cpu.loadAverage, decimals: 2),
                          help: "Durchschnittlich wartende Aufgaben in der letzten Minute"))
        facts.append(Fact(label: "Chip", value: topology.chip.replacingOccurrences(of: "Apple ", with: "")))
        return facts
    }
}

// MARK: Memory

struct MemoryDetail: View {
    let sample: Sample

    var body: some View {
        let memory = sample.memory
        VStack(spacing: 12) {
            FactGrid(facts: [
                Fact(label: "App-Speicher", value: Fmt.memory(memory.app).text, tone: MemoryTrace.app),
                Fact(label: "Reserviert", value: Fmt.memory(memory.wired).text, tone: MemoryTrace.wired,
                     help: "Speicher, den das System nicht auslagern kann"),
                Fact(label: "Komprimiert", value: Fmt.memory(memory.compressed).text, tone: MemoryTrace.compressed),
                Fact(label: "Cache", value: Fmt.memory(memory.cached).text, tone: .primary.opacity(0.2),
                     help: "Zwischengespeicherte Dateien; wird bei Bedarf sofort frei"),
                Fact(label: "Frei", value: Fmt.memory(memory.free).text),
                Fact(label: "Ausgelagert", value: Fmt.memory(memory.swapUsed).text,
                     help: "Auf die SSD ausgelagerter Speicher (Swap)")
            ])
            VStack(spacing: 5) {
                DetailCaption(text: "Am meisten belegen")
                AppList(apps: sample.processes.topMemory, measure: .memory, tone: Tone.memory)
            }
        }
    }
}

// MARK: Network

struct NetworkDetail: View {
    let sample: Sample
    let timeline: Timeline

    var body: some View {
        let network = sample.network
        var facts: [Fact] = []
        if let link = network.link {
            facts.append(Fact(label: "Anschluss", value: "\(link.kind.label) (\(link.name))"))
            if let ip = link.ipv4 {
                facts.append(Fact(label: "IP-Adresse", value: ip, copies: ip))
            }
            if let router = link.router {
                facts.append(Fact(label: "Router", value: router, copies: router))
            }
        }
        let peak = timeline.samples.map(\.network.downRate).max() ?? 0
        facts.append(Fact(label: "Spitze", value: Fmt.rate(peak).text,
                          help: "Höchste Empfangsrate im sichtbaren Zeitraum"))
        facts.append(Fact(label: "Empfangen", value: Fmt.storage(network.totalDown).text, help: "Seit dem Start des Mac"))
        facts.append(Fact(label: "Gesendet", value: Fmt.storage(network.totalUp).text, help: "Seit dem Start des Mac"))
        return FactGrid(facts: facts)
    }
}

// MARK: Power

struct PowerDetail: View {
    let battery: BatterySample
    let time: Date

    var body: some View {
        var facts: [Fact] = []
        if let rest = battery.timeRemaining, battery.state != .pluggedIn {
            facts.append(Fact(label: battery.state == .battery ? "Leer um" : "Voll um",
                              value: "\(Fmt.clock(time.addingTimeInterval(rest))) Uhr",
                              help: "Hochgerechnet aus dem Verbrauch der letzten Minuten"))
        }
        if let health = battery.health {
            facts.append(Fact(label: "Zustand", value: "\(Fmt.percent(health)) %",
                              tone: health < 0.8 ? Tone.warning : nil,
                              help: "Heutige Kapazität im Vergleich zum Neuzustand"))
        }
        if let cycles = battery.cycles {
            facts.append(Fact(label: "Ladezyklen", value: "\(cycles)"))
        }
        if let temperature = battery.temperature {
            facts.append(Fact(label: "Temperatur", value: Fmt.temperature(temperature)))
        }
        if let adapter = battery.adapterWatts {
            facts.append(Fact(label: "Netzteil", value: "\(adapter) W"))
        }
        facts.append(Fact(label: "Stromsparmodus", value: battery.lowPowerMode ? "An" : "Aus"))
        return FactGrid(facts: facts)
    }
}
