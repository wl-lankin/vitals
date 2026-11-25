import AppKit
import Foundation
import Observation
import SwiftUI
import VitalsCore

/// The visible stretch of history, laid out along the time axis all traces share.
struct Timeline {
    var samples: [Sample] = []
    /// Horizontal position of each sample, 0 at the left edge and 1 at "now".
    var xs: [Double] = []
    /// True where a line has to start anew because the Mac slept or sampling paused.
    var starts: [Bool] = []
    var span: TimeInterval = 600
    var end = Date.distantPast

    init() {}

    init(samples: [Sample], span: TimeInterval, step: TimeInterval) {
        self.samples = samples
        self.span = span
        end = samples.last?.time ?? .distantPast
        xs = samples.map { 1 - end.timeIntervalSince($0.time) / span }
        starts = samples.indices.map { i in
            i == 0 || samples[i].time.timeIntervalSince(samples[i - 1].time) > step * 3
        }
    }

    func fraction(of time: Date) -> Double {
        min(1, max(0, 1 - end.timeIntervalSince(time) / span))
    }
}

/// Everything the window shows. Published values only change while the window is open, so a closed
/// window costs no view updates; the recorder underneath keeps running.
@MainActor
@Observable
final class Monitor {
    enum Section: String {
        case processor, memory, network, power
    }

    enum Span: String, CaseIterable, Identifiable {
        case tenMinutes, hour

        var id: String { rawValue }
        var seconds: TimeInterval { self == .tenMinutes ? 600 : 3600 }
        var label: String { self == .tenMinutes ? "Letzte 10 Minuten" : "Letzte Stunde" }
    }

    let topology: CPUTopology
    let bootTime: Date

    private(set) var latest: Sample
    private(set) var timeline = Timeline()
    /// Processor load averaged over a few samples; steadier than a single reading.
    private(set) var load = 0.0
    private(set) var span: Span
    /// How far back the pointer reaches into the traces, nil while showing the present.
    private(set) var scrubAge: TimeInterval?
    var expanded: Section?

    @ObservationIgnored private var history = History()
    @ObservationIgnored private let sampler: Sampler
    @ObservationIgnored private(set) var isOpen = false
    /// The newest sample, also while the window is closed. For the menu bar.
    @ObservationIgnored private(set) var current: Sample
    @ObservationIgnored private(set) var currentLoad = 0.0
    @ObservationIgnored var onSample: (() -> Void)?

    init(source: VitalsSource, prefill: [Sample] = [], autostart: Bool = true) {
        topology = source.topology
        bootTime = Self.readBootTime()
        span = Span(rawValue: UserDefaults.standard.string(forKey: "span") ?? "") ?? .tenMinutes
        sampler = Sampler(source: source)
        let first = prefill.last ?? Sample.empty(cores: source.topology.kinds.count)
        latest = first
        current = first
        prefill.forEach { history.append($0) }
        sampler.onSample = { [weak self] sample in self?.receive(sample) }
        if autostart { sampler.start() }
        if !prefill.isEmpty { publish() }
    }

    // MARK: What the views read

    /// The moment on display: the present, or the one under the pointer.
    var shown: Sample {
        guard let scrubAge,
              let past = History.nearest(in: timeline.samples, to: latest.time.addingTimeInterval(-scrubAge))
        else { return latest }
        return past
    }

    var isLive: Bool { scrubAge == nil }

    /// Position of the scrub cursor on the time axis.
    var cursor: Double? {
        scrubAge == nil ? nil : timeline.fraction(of: shown.time)
    }

    var verdict: Verdict {
        isLive ? Verdict.assess(latest, load: load) : Verdict.assess(shown)
    }

    var uptime: TimeInterval { latest.time.timeIntervalSince(bootTime) }

    // MARK: Interaction

    func scrub(toFraction fraction: Double) {
        scrubAge = (1 - min(1, max(0, fraction))) * timeline.span
    }

    func endScrub() {
        scrubAge = nil
    }

    func toggle(_ section: Section) {
        withAnimation(.snappy(duration: 0.28)) {
            expanded = expanded == section ? nil : section
        }
    }

    func setSpan(_ span: Span) {
        guard span != self.span else { return }
        self.span = span
        UserDefaults.standard.set(span.rawValue, forKey: "span")
        publish()
    }

    func setOpen(_ open: Bool) {
        isOpen = open
        sampler.setForeground(open)
        if open {
            publish()
        } else {
            scrubAge = nil
        }
    }

    func volumesChanged() {
        sampler.refreshVolumes()
    }

    // MARK: Recording

    private func receive(_ sample: Sample) {
        history.append(sample)
        current = sample
        currentLoad = recentLoad()
        onSample?()
        if isOpen { publish(animated: isLive) }
    }

    private func recentLoad() -> Double {
        let recent = history.samples.suffix(4)
        return recent.isEmpty ? 0 : recent.reduce(0) { $0 + $1.cpu.total } / Double(recent.count)
    }

    /// Whether new readings glide in. Off when the user turned it off here or asked the system for less motion.
    var animates: Bool {
        (UserDefaults.standard.object(forKey: "animations") == nil || UserDefaults.standard.bool(forKey: "animations"))
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func publish(animated: Bool = false) {
        guard let last = history.latest else { return }
        let window = history.window(span: span.seconds, maxPoints: 300, interval: sampler.interval)
        let step = max(sampler.interval, span.seconds / 300)
        let update = {
            self.latest = last
            self.timeline = Timeline(samples: window, span: self.span.seconds, step: step)
            self.load = self.recentLoad()
        }
        if animated && animates {
            withAnimation(.snappy(duration: 0.4), update)
        } else {
            update()
        }
    }

    private static func readBootTime() -> Date {
        var time = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctlbyname("kern.boottime", &time, &size, nil, 0) == 0, time.tv_sec > 0 else { return Date() }
        return Date(timeIntervalSince1970: TimeInterval(time.tv_sec))
    }
}
