import AppKit
import SwiftUI
import VitalsCore

/// The frame every vital sign shares: name and remark on the left, the live value on the right,
/// the trace across the full width, details on demand.
struct VitalRow<Accessory: View, Chart: View, Detail: View>: View {
    @Environment(Monitor.self) private var monitor
    let section: Monitor.Section?
    let title: String
    let remark: String
    var remarkTone: Color? = nil
    let value: Fmt.Quantity
    var valueTone: Color? = nil
    var valueSymbol: String? = nil
    /// A second value of equal rank; the two then share the place of the single numeral.
    var pairedValue: Fmt.Quantity? = nil
    /// Symbols in front of the two values, upper first.
    var pairedSymbols: [String] = []
    var hasChart = true
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var chart: Chart
    @ViewBuilder var detail: Detail

    @State private var hover = false

    private var isExpanded: Bool { section != nil && monitor.expanded == section }
    /// While one vital sign shows its details, the others step back to a single line.
    private var isCompact: Bool { monitor.expanded != nil && !isExpanded }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(title)
                                .font(.system(size: 13, weight: .semibold))
                            if section != nil {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8.5, weight: .bold))
                                    .foregroundStyle(.tertiary)
                                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                                    .opacity(hover || isExpanded ? 1 : 0)
                            }
                        }
                        HStack(spacing: 6) {
                            Text(remark)
                                .font(.system(size: 11.5, weight: remarkTone == nil ? .regular : .medium))
                                .foregroundStyle(remarkTone.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.secondary))
                                .lineLimit(1)
                                .monospacedDigit()
                            accessory
                        }
                        .frame(height: 15)
                    }
                    Spacer(minLength: 4)
                    if let pairedValue {
                        PairedReadout(upper: value, lower: pairedValue, symbols: pairedSymbols, upperTone: valueTone)
                    } else {
                        Readout(value: value, tone: valueTone, symbol: valueSymbol)
                    }
                }
                if !isCompact {
                    chart.transition(.opacity)
                }
            }
            .padding(.horizontal, Metrics.inset)
            .padding(.top, 10)
            .padding(.bottom, isCompact || !hasChart ? 10 : 9)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.primary.opacity(hover && section != nil ? 0.045 : 0))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
            }
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .onTapGesture {
                if let section { monitor.toggle(section) }
            }
            .help(section == nil ? "" : (isExpanded ? "Details ausblenden" : "Details anzeigen"))

            if isExpanded {
                detail
                    .padding(.horizontal, Metrics.inset)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
            if isCompact || isExpanded || !hasChart {
                Hairline()
            }
        }
    }
}

/// The big light numeral with its unit.
struct Readout: View {
    let value: Fmt.Quantity
    var tone: Color? = nil
    var symbol: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 1)
            }
            RollingText(text: value.number, font: .readout(27))
                .foregroundStyle(tone.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary))
            Text(value.unit)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .fixedSize()
    }
}

/// A number whose digits roll like a counter when it changes.
///
/// Not `.contentTransition(.numericText())`: that one scales and blurs every glyph a little differently
/// on each frame, and CoreGraphics keeps a bitmap of every one of those variants. With a value changing
/// every two seconds the app grew by about 1 MB per second while the window was open. Sliding a digit
/// only moves the same bitmap.
struct RollingText: View {
    let text: String
    let font: Font

    var body: some View {
        let characters = Array(text)
        HStack(spacing: 0) {
            // Identity is the place counted from the right plus the character: the ones stay the ones
            // when a digit is added in front, and a place whose digit changes swaps its view.
            ForEach(Array(characters.enumerated()), id: \.offset) { index, character in
                Text(String(character))
                    .font(font)
                    .monospacedDigit()
                    .id("\(characters.count - index)\(character)")
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .move(edge: .top).combined(with: .opacity)))
            }
        }
        .clipped()
    }
}

/// Two values of equal weight, one above the other: received and sent, charge and draw.
struct PairedReadout: View {
    let upper: Fmt.Quantity
    let lower: Fmt.Quantity
    var symbols: [String] = []
    var upperTone: Color? = nil

    var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: 4, verticalSpacing: 0) {
            line(upper, symbol: symbols.first, tone: upperTone)
            line(lower, symbol: symbols.count > 1 ? symbols[1] : nil, tone: nil)
        }
        .fixedSize()
        .padding(.top, -3)
    }

    private func line(_ value: Fmt.Quantity, symbol: String?, tone: Color?) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            if !symbols.isEmpty {
                Image(systemName: symbol ?? "circle")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.secondary)
                    .opacity(symbol == nil ? 0 : 1)
            }
            RollingText(text: value.number, font: .readout(17.5))
                .foregroundStyle(tone.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary))
            Text(value.unit)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.leading)
        }
        .frame(height: 19.5)
    }
}

// MARK: Processor

struct ProcessorRow: View {
    @Environment(Monitor.self) private var monitor

    var body: some View {
        let sample = monitor.shown
        let top = sample.processes.topCPU.first
        VitalRow(section: .processor,
                 title: "Prozessor",
                 remark: top.flatMap { $0.cpu >= 0.1 ? "\($0.name) \(Fmt.percent($0.cpu)) %" : nil } ?? "Ruhig",
                 value: Fmt.Quantity(number: Fmt.percent(sample.cpu.total), unit: "%"),
                 valueTone: sample.cpu.total >= 0.9 ? Tone.warning : nil) {
            Spacer(minLength: 0)
            CoreStrip(cores: sample.cpu.cores, kinds: monitor.topology.kinds)
        } chart: {
            SingleTrace(color: Tone.processor) { $0.cpu.total }
        } detail: {
            ProcessorDetail(sample: sample, topology: monitor.topology)
        }
    }
}

/// All cores at a glance, performance cores first.
struct CoreStrip: View {
    let cores: [Double]
    let kinds: [CoreKind]

    var body: some View {
        let groups = CoreGroup.split(cores: cores, kinds: kinds)
        HStack(spacing: 5) {
            ForEach(groups) { group in
                HStack(spacing: 2) {
                    ForEach(Array(group.loads.enumerated()), id: \.offset) { _, load in
                        CoreCell(load: load, width: 4, height: 13, radius: 1.5)
                    }
                }
            }
        }
        .help(groups.map { "\($0.loads.count) \($0.longName)" }.joined(separator: ", "))
    }
}

struct CoreCell: View {
    let load: Double
    let width: CGFloat?
    let height: CGFloat
    let radius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(.primary.opacity(0.1))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(load >= 0.9 ? Tone.warning : Tone.processor)
                    .frame(height: max(1, height * min(1, max(0, load))))
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .frame(width: width, height: height)
    }
}

struct CoreGroup: Identifiable {
    let kind: CoreKind
    let loads: [Double]

    var id: String { kind.rawValue }

    var name: String {
        switch kind {
        case .performance: "Leistung"
        case .efficiency: "Effizienz"
        case .unknown: "Kerne"
        }
    }

    var longName: String {
        switch kind {
        case .performance: "Leistungskerne"
        case .efficiency: "Effizienzkerne"
        case .unknown: "Kerne"
        }
    }

    static func split(cores: [Double], kinds: [CoreKind]) -> [CoreGroup] {
        guard kinds.count == cores.count, Set(kinds).count > 1 else {
            return cores.isEmpty ? [] : [CoreGroup(kind: .unknown, loads: cores)]
        }
        return [CoreKind.performance, .efficiency, .unknown].compactMap { kind in
            let loads = zip(cores, kinds).filter { $0.1 == kind }.map(\.0)
            return loads.isEmpty ? nil : CoreGroup(kind: kind, loads: loads)
        }
    }
}

// MARK: Memory

struct MemoryRow: View {
    @Environment(Monitor.self) private var monitor

    var body: some View {
        let memory = monitor.shown.memory
        let pressure: (text: String, tone: Color)? = switch memory.pressure {
        case .normal: nil
        case .warning: ("Speicherdruck erhöht", Tone.warning)
        case .critical: ("Speicherdruck kritisch", Tone.alert)
        }
        VitalRow(section: .memory,
                 title: "Speicher",
                 remark: pressure?.text
                    ?? "\(Fmt.memory(memory.used).text) von \(Fmt.memory(memory.total, trim: true).text) belegt",
                 remarkTone: pressure?.tone,
                 value: Fmt.Quantity(number: Fmt.percent(memory.usedFraction), unit: "%"),
                 valueTone: memory.pressure == .critical ? Tone.alert : nil) {
            EmptyView()
        } chart: {
            MemoryTrace()
        } detail: {
            MemoryDetail(sample: monitor.shown)
        }
    }
}

// MARK: Disks

struct DisksRow: View {
    @Environment(Monitor.self) private var monitor

    var body: some View {
        let disk = monitor.shown.disk
        let startup = disk.volumes.first
        let busy = disk.readRate + disk.writeRate >= 100_000
        VStack(spacing: 0) {
            VitalRow(section: nil,
                     title: "Laufwerke",
                     remark: busy
                        ? "Liest \(Fmt.rate(disk.readRate).text), schreibt \(Fmt.rate(disk.writeRate).text)"
                        : "Ruhig",
                     value: startup.map {
                         let free = Fmt.storage($0.free)
                         return Fmt.Quantity(number: free.number, unit: "\(free.unit) frei")
                     } ?? Fmt.Quantity(number: "0", unit: "GB frei"),
                     valueTone: startup.map { $0.usedFraction > 0.95 ? Tone.warning : nil } ?? nil) {
                EmptyView()
            } chart: {
                MirroredTrace(color: Tone.disks, floor: 2_000_000,
                              upper: { $0.disk.readRate }, lower: { $0.disk.writeRate })
            } detail: {
                EmptyView()
            }
            if monitor.expanded == nil {
                VStack(spacing: 1) {
                    ForEach(disk.volumes.prefix(5)) { volume in
                        VolumeLine(volume: volume)
                    }
                    if disk.volumes.count > 5 {
                        Text("und \(disk.volumes.count - 5) weitere")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 37)
                            .padding(.vertical, 3)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, -2)
                .padding(.bottom, 6)
                .transition(.opacity)
            }
        }
    }
}

struct VolumeLine: View {
    @Environment(Monitor.self) private var monitor
    let volume: Volume
    @State private var hover = false
    @State private var ejecting = false

    private var symbol: String {
        switch volume.kind {
        case .internalDisk: "internaldrive.fill"
        case .external: "externaldrive.fill"
        case .network: "externaldrive.connected.to.line.below.fill"
        case .image: "opticaldisc.fill"
        }
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(volume.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(Fmt.storage(volume.free).text) frei von \(Fmt.storage(volume.total).text)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                GeometryReader { geo in
                    Capsule()
                        .fill(.primary.opacity(0.1))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(volume.usedFraction > 0.95 ? Tone.warning : Tone.disks)
                                .frame(width: max(3, geo.size.width * volume.usedFraction))
                        }
                }
                .frame(height: 3)
            }
            if volume.isEjectable {
                Button {
                    eject()
                } label: {
                    Image(systemName: "eject.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(.primary.opacity(hover ? 0.1 : 0)))
                }
                .buttonStyle(.plain)
                .disabled(ejecting)
                .help("\(volume.name) auswerfen")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.primary.opacity(hover ? 0.045 : 0)))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture {
            NSWorkspace.shared.open(URL(fileURLWithPath: volume.id))
        }
        .help("\(volume.name) im Finder öffnen")
    }

    private func eject() {
        ejecting = true
        let url = URL(fileURLWithPath: volume.id)
        Task.detached {
            try? NSWorkspace.shared.unmountAndEjectDevice(at: url)
            await MainActor.run {
                ejecting = false
                monitor.volumesChanged()
            }
        }
    }
}

// MARK: Network

struct NetworkRow: View {
    @Environment(Monitor.self) private var monitor

    var body: some View {
        let network = monitor.shown.network
        VitalRow(section: .network,
                 title: "Netzwerk",
                 remark: network.link.map { link in
                     [link.kind.label, link.ipv4].compactMap { $0 }.joined(separator: ", ")
                 } ?? "Keine Verbindung",
                 value: Fmt.rate(network.downRate),
                 pairedValue: Fmt.rate(network.upRate),
                 pairedSymbols: ["arrow.down", "arrow.up"]) {
            EmptyView()
        } chart: {
            MirroredTrace(color: Tone.network, floor: 200_000,
                          upper: { $0.network.downRate }, lower: { $0.network.upRate })
        } detail: {
            NetworkDetail(sample: monitor.shown, timeline: monitor.timeline)
        }
    }
}

extension LinkKind {
    var label: String {
        switch self {
        case .wifi: "WLAN"
        case .ethernet: "Ethernet"
        case .cellular: "Mobilfunk"
        case .vpn: "VPN"
        case .other: "Verbunden"
        }
    }
}

// MARK: Power

struct PowerRow: View {
    @Environment(Monitor.self) private var monitor

    var body: some View {
        let power = monitor.shown.power
        if power.battery != nil || power.systemWatts != nil {
            VitalRow(section: power.battery == nil ? nil : .power,
                     title: power.battery == nil ? "Energie" : "Akku",
                     remark: power.battery.map { Self.remark($0, at: monitor.shown.time) } ?? "Am Stromnetz",
                     value: power.battery.map { Fmt.Quantity(number: "\($0.percent)", unit: "%") }
                        ?? power.systemWatts.map { Fmt.watts($0) } ?? Fmt.Quantity(number: "", unit: ""),
                     valueTone: power.battery.flatMap { battery in
                         battery.state == .battery && battery.percent <= 10 ? Tone.alert
                             : battery.state == .battery && battery.percent <= 20 ? Tone.warning : nil
                     },
                     pairedValue: power.battery == nil ? nil : power.systemWatts.map { Fmt.watts($0) },
                     hasChart: power.systemWatts != nil) {
                EmptyView()
            } chart: {
                if power.systemWatts != nil {
                    SingleTrace(color: Tone.power, ceiling: nil, floor: 10) { $0.power.systemWatts }
                }
            } detail: {
                if let battery = power.battery {
                    PowerDetail(battery: battery, time: monitor.shown.time)
                }
            }
        }
    }

    static func remark(_ battery: BatterySample, at time: Date) -> String {
        switch battery.state {
        case .battery:
            guard let rest = battery.timeRemaining else { return "Restlaufzeit wird berechnet" }
            return "Reicht noch \(Fmt.duration(rest))"
        case .charging:
            guard let rest = battery.timeRemaining else { return "Lädt" }
            return "Lädt, voll in \(Fmt.duration(rest))"
        case .pluggedIn:
            return battery.percent >= 99 ? "Voll geladen, am Netzteil" : "Am Netzteil, lädt gerade nicht"
        }
    }
}
