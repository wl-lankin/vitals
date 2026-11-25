import Foundation

/// Where samples come from: the real machine, or generated data for screenshots.
public protocol VitalsSource: AnyObject {
    var topology: CPUTopology { get }
    /// The cheap readings, combined with the process list handed in.
    func read(at time: Date, processes: ProcessSample) -> Sample
    /// The process table. May block for tens of milliseconds.
    func readProcesses() -> ProcessSample
    /// The set of mounted volumes changed; do not serve a cached list next time.
    func invalidateVolumes()
}

public extension VitalsSource {
    func invalidateVolumes() {}
}

/// Reads the source on its own queue at a steady pace and hands each sample to the main thread.
/// Nothing here touches the main thread while reading: a stalled network volume must not freeze the menu bar.
public final class Sampler: @unchecked Sendable {
    public let interval: TimeInterval
    public var onSample: (@MainActor (Sample) -> Void)?

    private let source: VitalsSource
    private let queue = DispatchQueue(label: "vitals.sampler", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var tick = 0
    private var foreground = false
    private var processes = ProcessSample.zero

    public init(source: VitalsSource, interval: TimeInterval = 2) {
        self.source = source
        self.interval = interval
    }

    public func start() {
        queue.async { [self] in
            guard timer == nil else { return }
            // Rates need two readings a full interval apart, so take the baseline now and the
            // first real sample one interval later.
            _ = source.read(at: Date(), processes: .zero)
            _ = source.readProcesses()
            tick = 1
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(100))
            timer.setEventHandler { [weak self] in self?.fire() }
            self.timer = timer
            timer.resume()
        }
    }

    public func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
        }
    }

    /// While the window is open the process list refreshes every other tick, otherwise every fifth:
    /// spawning `ps` is the only costly part, and nobody is looking.
    public func setForeground(_ on: Bool) {
        queue.async { [self] in
            foreground = on
            if on { tick = 0 }
        }
    }

    /// Takes a fresh sample right away, with a new look at the mounted volumes.
    public func refreshVolumes() {
        queue.async { [self] in
            source.invalidateVolumes()
            guard timer != nil else { return }
            fire()
        }
    }

    private func fire() {
        let every = foreground ? 2 : 5
        if tick % every == 0 { processes = source.readProcesses() }
        tick += 1
        let sample = source.read(at: Date(), processes: processes)
        let handler = onSample
        DispatchQueue.main.async {
            MainActor.assumeIsolated { handler?(sample) }
        }
    }
}
