import Foundation

/// The recent past, oldest sample first.
public struct History: Sendable {
    public private(set) var samples: [Sample] = []
    public var retention: TimeInterval

    public init(retention: TimeInterval = 3600) {
        self.retention = retention
    }

    public var latest: Sample? { samples.last }

    public mutating func append(_ sample: Sample) {
        // A clock that jumped backwards would put samples out of order; start over instead.
        if let last = samples.last, sample.time <= last.time { samples.removeAll() }
        samples.append(sample)
        let cutoff = sample.time.addingTimeInterval(-retention)
        if let first = samples.first, first.time < cutoff {
            samples.removeFirst(samples.prefix { $0.time < cutoff }.count)
        }
    }

    /// The last `span` seconds in at most about `maxPoints` samples. Longer spans are folded into
    /// buckets aligned to absolute time, so a bucket keeps its content while newer samples arrive.
    public func window(span: TimeInterval, maxPoints: Int, interval: TimeInterval) -> [Sample] {
        guard let last = samples.last else { return [] }
        let cutoff = last.time.addingTimeInterval(-span)
        let firstRecent = samples.firstIndex { $0.time >= cutoff } ?? samples.endIndex
        let recent = samples[firstRecent...]
        let bucket = span / Double(maxPoints)
        if bucket < interval * 1.5 { return Array(recent) }

        var result: [Sample] = []
        result.reserveCapacity(maxPoints + 1)
        var start = recent.startIndex
        var key = (recent.first?.time.timeIntervalSinceReferenceDate ?? 0) / bucket
        key.round(.down)
        for i in recent.indices {
            let k = (recent[i].time.timeIntervalSinceReferenceDate / bucket).rounded(.down)
            if k != key {
                result.append(Sample.merged(recent[start..<i]))
                start = i
                key = k
            }
        }
        if start < recent.endIndex { result.append(Sample.merged(recent[start...])) }
        return result
    }

    /// The sample closest to `time`.
    public static func nearest(in samples: [Sample], to time: Date) -> Sample? {
        guard !samples.isEmpty else { return nil }
        var low = 0, high = samples.count - 1
        while low < high {
            let mid = (low + high) / 2
            if samples[mid].time < time { low = mid + 1 } else { high = mid }
        }
        if low > 0, time.timeIntervalSince(samples[low - 1].time) < samples[low].time.timeIntervalSince(time) {
            return samples[low - 1]
        }
        return samples[low]
    }
}

extension Sample {
    /// Folds neighbouring samples into one: measurements are averaged, states come from the newest
    /// sample, and the app list from the busiest moment (that is the one worth looking back at).
    public static func merged(_ group: ArraySlice<Sample>) -> Sample {
        guard var out = group.last else { preconditionFailure("merged() needs at least one sample") }
        guard group.count > 1 else { return out }
        let n = Double(group.count)
        func mean(_ value: (Sample) -> Double) -> Double { group.reduce(0) { $0 + value($1) } / n }
        func mean(_ value: (Sample) -> UInt64) -> UInt64 { UInt64(group.reduce(0) { $0 + Double(value($1)) } / n) }
        func mean(_ value: (Sample) -> Double?) -> Double? {
            let present = group.compactMap(value)
            return present.isEmpty ? nil : present.reduce(0, +) / Double(present.count)
        }

        out.cpu.total = mean { $0.cpu.total }
        out.cpu.user = mean { $0.cpu.user }
        out.cpu.system = mean { $0.cpu.system }
        let coreCount = out.cpu.cores.count
        out.cpu.cores = (0..<coreCount).map { c in
            mean { $0.cpu.cores.count == coreCount ? $0.cpu.cores[c] : 0 }
        }

        out.memory.app = mean { $0.memory.app }
        out.memory.wired = mean { $0.memory.wired }
        out.memory.compressed = mean { $0.memory.compressed }
        out.memory.cached = mean { $0.memory.cached }
        out.memory.free = mean { $0.memory.free }
        out.memory.pressure = group.map(\.memory.pressure).max() ?? .normal

        out.disk.readRate = mean { $0.disk.readRate }
        out.disk.writeRate = mean { $0.disk.writeRate }
        out.network.downRate = mean { $0.network.downRate }
        out.network.upRate = mean { $0.network.upRate }
        out.power.systemWatts = mean { $0.power.systemWatts }
        out.sensors.cpuTemperature = mean { $0.sensors.cpuTemperature }
        out.sensors.gpuUsage = mean { $0.sensors.gpuUsage }
        out.sensors.thermal = group.map(\.sensors.thermal).max() ?? .nominal

        if let busiest = group.max(by: { $0.cpu.total < $1.cpu.total }) {
            out.processes = busiest.processes
        }
        return out
    }
}
