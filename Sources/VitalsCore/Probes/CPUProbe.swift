import Foundation
import IOKit

struct CPUTicks: Equatable {
    var user: UInt64
    var system: UInt64
    var idle: UInt64
}

enum CPUMath {
    /// Fractions of the elapsed ticks. Counters that went backwards or an empty delta give zeros.
    static func fractions(previous: CPUTicks, current: CPUTicks) -> (total: Double, user: Double, system: Double) {
        guard current.user >= previous.user, current.system >= previous.system, current.idle >= previous.idle else {
            return (0, 0, 0)
        }
        let u = Double(current.user - previous.user)
        let s = Double(current.system - previous.system)
        let i = Double(current.idle - previous.idle)
        let all = u + s + i
        guard all > 0 else { return (0, 0, 0) }
        return ((u + s) / all, u / all, s / all)
    }

    /// Cluster labels from the device tree ("P"/"E") mapped onto logical core indices.
    static func kinds(count: Int, clusterByCPU: [Int: String], performanceCount: Int?, efficiencyCount: Int?) -> [CoreKind] {
        guard count > 0 else { return [] }
        if clusterByCPU.count >= count, (0..<count).allSatisfy({ clusterByCPU[$0] != nil }) {
            return (0..<count).map { index in
                switch clusterByCPU[index] {
                case "P": return .performance
                case "E": return .efficiency
                default: return .unknown
                }
            }
        }
        if let p = performanceCount, let e = efficiencyCount, p + e == count {
            // perflevel0 is the fastest level; the kernel numbers efficiency cores first.
            return Array(repeating: .efficiency, count: e) + Array(repeating: .performance, count: p)
        }
        return Array(repeating: .unknown, count: count)
    }
}

public final class CPUProbe {
    public let topology: CPUTopology
    private var previous: [CPUTicks] = []

    public init() {
        topology = CPUProbe.readTopology()
    }

    public func read() -> CPUSample {
        let current = Self.readTicks()
        defer { previous = current }
        var load = [Double](repeating: 0, count: 1)
        let loadAverage = getloadavg(&load, 1) >= 1 ? load[0] : 0

        guard !current.isEmpty else {
            return CPUSample(total: 0, user: 0, system: 0, cores: [], loadAverage: loadAverage)
        }
        guard previous.count == current.count else {
            return CPUSample(total: 0, user: 0, system: 0, cores: Array(repeating: 0, count: current.count),
                             loadAverage: loadAverage)
        }

        var cores: [Double] = []
        cores.reserveCapacity(current.count)
        var sumPrev = CPUTicks(user: 0, system: 0, idle: 0)
        var sumCur = CPUTicks(user: 0, system: 0, idle: 0)
        for (p, c) in zip(previous, current) {
            cores.append(CPUMath.fractions(previous: p, current: c).total)
            sumPrev.user &+= p.user; sumPrev.system &+= p.system; sumPrev.idle &+= p.idle
            sumCur.user &+= c.user; sumCur.system &+= c.system; sumCur.idle &+= c.idle
        }
        let f = CPUMath.fractions(previous: sumPrev, current: sumCur)
        return CPUSample(total: f.total, user: f.user, system: f.system, cores: cores, loadAverage: loadAverage)
    }

    private static func readTicks() -> [CPUTicks] {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(cpuHostPort, PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return [] }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        let stride = Int(CPU_STATE_MAX)
        guard Int(infoCount) >= Int(count) * stride else { return [] }
        var ticks: [CPUTicks] = []
        ticks.reserveCapacity(Int(count))
        for i in 0..<Int(count) {
            let base = i * stride
            let user = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]))
                + UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
            let system = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]))
            let idle = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]))
            ticks.append(CPUTicks(user: user, system: system, idle: idle))
        }
        return ticks
    }

    private static func readTopology() -> CPUTopology {
        let chip = cpuSysctlString("machdep.cpu.brand_string") ?? "Unknown"
        let count = max(readTicks().count, cpuSysctlInt("hw.logicalcpu") ?? 0)
        #if arch(arm64)
        let kinds = CPUMath.kinds(count: count, clusterByCPU: deviceTreeClusters(),
                                  performanceCount: cpuSysctlInt("hw.perflevel0.logicalcpu"),
                                  efficiencyCount: cpuSysctlInt("hw.perflevel1.logicalcpu"))
        #else
        let kinds = Array(repeating: CoreKind.performance, count: count)
        #endif
        return CPUTopology(chip: chip, kinds: kinds)
    }

    private static func deviceTreeClusters() -> [Int: String] {
        var result: [Int: String] = [:]
        let cpus = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/cpus")
        guard cpus != 0 else { return result }
        defer { IOObjectRelease(cpus) }
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(cpus, kIODeviceTreePlane, &iterator) == KERN_SUCCESS else { return result }
        defer { IOObjectRelease(iterator) }
        while case let child = IOIteratorNext(iterator), child != 0 {
            defer { IOObjectRelease(child) }
            guard let cluster = property(child, "cluster-type").flatMap(string(from:)),
                  let id = property(child, "logical-cpu-id").flatMap(int(from:)) else { continue }
            result[id] = cluster
        }
        return result
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private static func string(from value: Any) -> String? {
        if let s = value as? String { return s }
        if let d = value as? Data {
            return String(bytes: d.prefix { $0 != 0 }, encoding: .utf8)
        }
        return nil
    }

    private static func int(from value: Any) -> Int? {
        if let n = value as? NSNumber { return n.intValue }
        if let d = value as? Data, d.count >= 4 {
            return Int(d[d.startIndex]) | Int(d[d.startIndex + 1]) << 8 | Int(d[d.startIndex + 2]) << 16
                | Int(d[d.startIndex + 3]) << 24
        }
        return nil
    }
}

// mach_host_self() hands out a new send right on every call; ask once.
fileprivate let cpuHostPort = mach_host_self()

fileprivate func cpuSysctlString(_ name: String) -> String? {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
    return String(cString: buffer)
}

fileprivate func cpuSysctlInt(_ name: String) -> Int? {
    var value: Int64 = 0
    var size = MemoryLayout<Int64>.size
    guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
    if size == 4 { return Int(Int32(truncatingIfNeeded: value)) }
    return Int(value)
}
