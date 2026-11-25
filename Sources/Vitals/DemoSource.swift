import Foundation
import VitalsCore

/// Generated readings of a made-up afternoon: for screenshots and for looking at the window
/// without showing what is really running. `Vitals --demo` uses it.
final class DemoSource: VitalsSource {
    let topology = CPUTopology(chip: "Apple M5",
                               kinds: Array(repeating: .efficiency, count: 6) + Array(repeating: .performance, count: 4))
    private let start = Date()
    private let interval: TimeInterval = 2

    func read(at time: Date, processes: ProcessSample) -> Sample {
        Self.sample(index: Int(time.timeIntervalSince(start) / interval) + 300, time: time, topology: topology)
    }

    func readProcesses() -> ProcessSample { .zero }

    /// Ten minutes of history ending now.
    func prefill(count: Int = 300) -> [Sample] {
        let now = Date()
        return (0..<count).map { i in
            Self.sample(index: i, time: now.addingTimeInterval(-Double(count - 1 - i) * interval), topology: topology)
        }
    }

    private static func noise(_ i: Int, _ salt: Int) -> Double {
        var x = UInt64(truncatingIfNeeded: i &* 2_654_435_761 &+ salt &* 40_503)
        x ^= x >> 13
        x = x &* 0x9E37_79B9_7F4A_7C15
        x ^= x >> 29
        return Double(x % 10_000) / 10_000
    }

    private static func bump(_ i: Int, at center: Double, width: Double) -> Double {
        let d = (Double(i) - center) / width
        return exp(-d * d)
    }

    static func sample(index i: Int, time: Date, topology: CPUTopology) -> Sample {
        let t = Double(i)
        let build = bump(i, at: 120, width: 26) * 0.62 + bump(i, at: 236, width: 12) * 0.34
        let total = min(0.97, 0.07 + 0.03 * sin(t / 11) + build + 0.035 * noise(i, 1))
        let cores: [Double] = topology.kinds.indices.map { c in
            let weight = topology.kinds[c] == .performance ? 1.45 : 0.7
            return min(1, max(0.01, total * weight * (0.75 + 0.5 * noise(i, 10 + c))))
        }
        let cpu = CPUSample(total: total, user: total * 0.72, system: total * 0.28, cores: cores,
                            loadAverage: 1.4 + total * 6)

        let gb: Double = 1_073_741_824
        let app = (9.1 + 1.6 * bump(i, at: 130, width: 40) + 0.2 * sin(t / 37)) * gb
        let wired = (3.3 + 0.1 * sin(t / 53)) * gb
        let compressed = (1.6 + 0.9 * bump(i, at: 150, width: 50)) * gb
        let cached = (6.2 - 1.2 * bump(i, at: 140, width: 45)) * gb
        let totalMemory = 24 * gb
        let memory = MemorySample(total: UInt64(totalMemory), app: UInt64(app), wired: UInt64(wired),
                                  compressed: UInt64(compressed), cached: UInt64(cached),
                                  free: UInt64(max(0, totalMemory - app - wired - compressed - cached)),
                                  swapUsed: UInt64(1.2 * gb), swapTotal: UInt64(2 * gb), pressure: .normal)

        let read = (bump(i, at: 112, width: 10) * 310 + bump(i, at: 240, width: 5) * 90 + noise(i, 3) * 1.5) * 1_000_000
        let write = (bump(i, at: 128, width: 16) * 140 + bump(i, at: 60, width: 4) * 45 + noise(i, 4) * 0.8) * 1_000_000
        let disk = DiskSample(volumes: [
            Volume(id: "/", name: "Macintosh HD", total: 994_610_155_520, free: 432_900_000_000,
                   kind: .internalDisk, isEjectable: false),
            Volume(id: "/Volumes/Archiv", name: "Archiv", total: 2_000_398_934_016, free: 612_400_000_000,
                   kind: .external, isEjectable: true)
        ], readRate: read, writeRate: write)

        let down = (bump(i, at: 70, width: 14) * 38 + bump(i, at: 200, width: 20) * 11
                    + 0.25 * noise(i, 5) + 0.1) * 1_000_000
        let up = (bump(i, at: 205, width: 16) * 4.2 + bump(i, at: 74, width: 10) * 1.1 + 0.06 * noise(i, 6)) * 1_000_000
        let network = NetworkSample(downRate: down, upRate: up,
                                    totalDown: 22_196_146_157 + UInt64(i) * 400_000,
                                    totalUp: 4_639_670_157 + UInt64(i) * 60_000,
                                    link: NetworkLink(name: "en0", kind: .wifi, ipv4: "192.168.0.34", router: "192.168.0.1"))

        let watts = 4.2 + total * 31 + 0.6 * noise(i, 7)
        let battery = BatterySample(percent: 82, state: .battery, timeRemaining: 6.4 * 3600 - total * 9000,
                                    health: 0.96, cycles: 178, temperature: 30.4, adapterWatts: nil, lowPowerMode: false)
        let power = PowerSample(battery: battery, systemWatts: watts)
        let sensors = SensorSample(cpuTemperature: 38 + total * 44, gpuUsage: 0.08 + total * 0.4, thermal: .nominal)

        func usage(_ name: String, _ path: String, _ pid: Int32, cpu: Double, memory: Double, count: Int) -> AppUsage {
            AppUsage(id: path, name: name, bundlePath: path, pid: pid, cpu: cpu, memory: UInt64(memory * gb),
                     processCount: count)
        }
        let apps = [
            usage("Xcode", "/Applications/Xcode.app", 411, cpu: 0.04 + build * 6.1, memory: 3.4 + build * 1.5, count: 9),
            usage("Safari", "/Applications/Safari.app", 502, cpu: 0.06 + 0.3 * bump(i, at: 70, width: 14), memory: 2.6, count: 14),
            usage("Musik", "/System/Applications/Music.app", 618, cpu: 0.03 + 0.01 * noise(i, 8), memory: 0.41, count: 2),
            usage("Mail", "/System/Applications/Mail.app", 733, cpu: 0.01 + 0.02 * noise(i, 9), memory: 0.62, count: 3),
            usage("Finder", "/System/Library/CoreServices/Finder.app", 320, cpu: 0.008, memory: 0.28, count: 1)
        ]
        let processes = ProcessSample(topCPU: apps.sorted { $0.cpu > $1.cpu },
                                      topMemory: apps.sorted { $0.memory > $1.memory }, processCount: 642)

        return Sample(time: time, cpu: cpu, memory: memory, disk: disk, network: network, power: power,
                      sensors: sensors, processes: processes)
    }
}
